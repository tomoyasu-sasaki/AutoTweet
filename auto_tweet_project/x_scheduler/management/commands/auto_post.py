import os
import glob
import logging
from django.core.management.base import BaseCommand
from django.conf import settings
from django.core.files import File
from django.utils import timezone
from x_scheduler.models import TweetSchedule, DailyPostCounter, SystemSetting
from x_scheduler.utils import post_tweet, test_api_connection

logger = logging.getLogger(__name__)

class Command(BaseCommand):
    help = '指定されたテキストと画像を使って自動投稿を作成する'

    def add_arguments(self, parser):
        parser.add_argument('--text', type=str, default='#投稿テキスト', help='投稿するテキスト')
        parser.add_argument('--image-dir', type=str, default='auto_post_images', help='画像が保存されているディレクトリ（mediaディレクトリからの相対パス）')
        parser.add_argument('--post-now', action='store_true', help='すぐに投稿する（指定しない場合はスケジュールのみ作成）')
        parser.add_argument('--interval', type=int, default=90, help='次回投稿までの間隔（分）')
        parser.add_argument('--skip-api-test', action='store_true', help='API接続テストをスキップする')
        parser.add_argument('--force-api-test', action='store_true', help='API接続テストを強制的に実行する')
        parser.add_argument('--peak-hour', action='store_true', help='ピーク時間帯（6時、12時、18時）の処理であることを示す')

    def handle(self, *args, **options):
        text = options['text']
        image_dir = options['image_dir']
        post_now = options['post_now']
        interval_minutes = options['interval']
        skip_api_test = options['skip_api_test']
        force_api_test = options['force_api_test']
        
        # API接続テストの処理
        if force_api_test or (not skip_api_test and not SystemSetting.is_api_test_done_today()):
            self.stdout.write('API接続テストを実行しています...')
            test_result = test_api_connection()
            if test_result['success']:
                SystemSetting.mark_api_test_done(peak=options.get('peak_hour', False))
                self.stdout.write(self.style.SUCCESS('API接続テスト成功'))
            else:
                self.stdout.write(self.style.ERROR(f'API接続テスト失敗: {test_result["error"]}'))
                return
        elif SystemSetting.is_api_test_done_today():
            self.stdout.write('今日はすでにAPI接続テストが完了しています。スキップします。')
        
        # 投稿数制限のチェック
        counter = DailyPostCounter.get_or_create_today()
        if counter.limit_reached:
            self.stdout.write(self.style.WARNING(f'本日の投稿上限（{counter.max_daily_posts}）に達しました。投稿をスキップします。'))
            return
        
        # 画像ディレクトリのパス
        image_dir_path = os.path.join(settings.MEDIA_ROOT, image_dir)
        
        # ディレクトリが存在しない場合は作成
        if not os.path.exists(image_dir_path):
            os.makedirs(image_dir_path)
            self.stdout.write(self.style.SUCCESS(f'画像ディレクトリを作成しました: {image_dir_path}'))
        
        # 画像ファイルのリストを取得（数字順にソート）
        image_files = sorted(glob.glob(os.path.join(image_dir_path, 'image_*.png')))
        image_files.extend(sorted(glob.glob(os.path.join(image_dir_path, 'image_*.jpg'))))
        image_files.extend(sorted(glob.glob(os.path.join(image_dir_path, 'image_*.jpeg'))))
        
        if not image_files:
            self.stdout.write(self.style.WARNING(f'画像が見つかりません: {image_dir_path}'))
            return
        
        # SystemSettingから最後に使用した画像のインデックスを取得
        next_index = SystemSetting.get_next_image_index(len(image_files))
        next_image = image_files[next_index]
        
        self.stdout.write(f'使用する画像: {os.path.basename(next_image)}')
        
        # 現在時刻を取得
        now = timezone.now()
        self.stdout.write(f'現在時刻: {now} (タイムゾーン: {timezone.get_current_timezone()})')
        
        # スケジュール時間を設定（すぐに投稿する場合は現在時刻）
        if post_now:
            scheduled_time = now
            self.stdout.write(f'即時投稿モード: 予定時刻 = {scheduled_time}')
        else:
            # 指定された間隔後の時間をスケジュール
            scheduled_time = now + timezone.timedelta(minutes=interval_minutes)
            self.stdout.write(f'スケジュール投稿モード: 予定時刻 = {scheduled_time} (現在時刻から{interval_minutes}分後)')
        
        # TweetScheduleオブジェクトを作成
        tweet = TweetSchedule(
            content=text,
            scheduled_time=scheduled_time
        )
        
        # 画像を設定
        with open(next_image, 'rb') as img_file:
            img_name = os.path.basename(next_image)
            tweet.image.save(img_name, File(img_file), save=False)
        
        tweet.save()
        
        self.stdout.write(self.style.SUCCESS(
            f'投稿スケジュールを作成しました: ID={tweet.id}, 予定時刻={scheduled_time}, 画像={img_name}'
        ))
        
        # すぐに投稿する場合
        if post_now:
            try:
                # 画像のパスを取得
                image_path = tweet.image.path if tweet.image else None
                
                # 投稿を実行
                post_result = post_tweet(tweet.content, image_path)
                
                if post_result['success']:
                    tweet.status = 'posted'
                    tweet.save()
                    # 投稿カウントを増加
                    counter.increment_count()
                    self.stdout.write(self.style.SUCCESS(f'投稿に成功しました！今日の投稿数: {counter.post_count}/{counter.max_daily_posts}'))
                else:
                    tweet.status = 'failed'
                    tweet.error_message = post_result['error']
                    tweet.save()
                    self.stdout.write(self.style.ERROR(f'投稿に失敗しました: {post_result["error"]}'))
            
            except Exception as e:
                logger.error(f'投稿処理中にエラーが発生しました: {str(e)}')
                tweet.status = 'failed'
                tweet.error_message = str(e)
                tweet.save()
                self.stdout.write(self.style.ERROR(f'エラーが発生しました: {str(e)}')) 