import os
import glob
import logging
from django.core.management.base import BaseCommand
from django.conf import settings
from django.core.files import File
from django.utils import timezone
from x_scheduler.models import TweetSchedule, DailyPostCounter, SystemSetting
from x_scheduler.utils import post_tweet, test_api_connection

# 親プロセスのPIDを取得（環境変数から）
PARENT_PID = os.getenv('SCRIPT_PID', '0')

# ロガーの設定
logger = logging.getLogger('x_scheduler')
formatter = logging.Formatter(f'%(asctime)s: [PID:{PARENT_PID}] [%(levelname)s] %(message)s', datefmt='%Y-%m-%d %H:%M:%S')
handler = logging.StreamHandler()
handler.setFormatter(formatter)
logger.handlers = [handler]  # 既存のハンドラをクリアして新しいハンドラのみを設定
logger.propagate = False  # 重複ログを防ぐ

def extract_number(filename):
    # ファイル名から数字部分を抽出（例：image_0085.pngから85を取得）
    import re
    match = re.search(r'image_(\d+)', filename)
    return int(match.group(1)) if match else 0

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
        
        tweet = None
        next_image = None
        
        try:
            # API接続テストの処理
            if force_api_test or (not skip_api_test and not SystemSetting.is_api_test_done_today()):
                logger.info('API接続テストを実行しています...')
                test_result = test_api_connection()
                if test_result['success']:
                    SystemSetting.mark_api_test_done(peak=options.get('peak_hour', False))
                    logger.info('API接続テスト成功')
                else:
                    logger.error(f'API接続テスト失敗: {test_result["error"]}')
                    return
            elif SystemSetting.is_api_test_done_today():
                logger.info('今日はすでにAPI接続テストが完了しています。スキップします。')
            
            # 投稿数制限のチェック
            counter = DailyPostCounter.get_or_create_today()
            if counter.limit_reached:
                logger.warning(f'本日の投稿上限（{counter.max_daily_posts}）に達しました。投稿をスキップします。')
                return
            
            # 画像ディレクトリのパス
            image_dir_path = os.path.join(settings.MEDIA_ROOT, image_dir)
            
            # ディレクトリが存在しない場合は作成
            if not os.path.exists(image_dir_path):
                os.makedirs(image_dir_path)
                logger.info(f'画像ディレクトリを作成しました: {image_dir_path}')
            
            # 画像ファイルのリストを取得（数字順にソート）
            image_files = sorted(glob.glob(os.path.join(image_dir_path, 'image_*.png')))
            image_files.extend(sorted(glob.glob(os.path.join(image_dir_path, 'image_*.jpg'))))
            image_files.extend(sorted(glob.glob(os.path.join(image_dir_path, 'image_*.jpeg'))))
            
            if not image_files:
                logger.warning(f'画像が見つかりません: {image_dir_path}')
                return
            
            # 画像ファイルを番号でソート
            image_files = sorted(image_files, key=extract_number)

            # 最後に使用した画像の番号を取得
            last_index = SystemSetting.get_last_image_index()
            logger.info(f'最後に使用した画像番号: {last_index}')

            # 次の画像を選択
            for image_file in image_files:
                current_number = extract_number(image_file)
                if current_number > last_index:
                    next_image = image_file
                    break

            # 最後まで到達した場合は最初に戻る
            if next_image is None:
                next_image = image_files[0]
                first_number = extract_number(image_files[0])
                logger.info(f'最後の画像まで使用したため、最初に戻ります: {os.path.basename(next_image)}')
            
            logger.info(f'使用する画像: {os.path.basename(next_image)}')
            
            # 現在時刻を取得
            now = timezone.now()
            logger.info(f'現在時刻: {now} (タイムゾーン: {timezone.get_current_timezone()})')
            
            # スケジュール時間を設定（すぐに投稿する場合は現在時刻）
            if post_now:
                scheduled_time = now
                logger.info(f'即時投稿モード: 予定時刻 = {scheduled_time}')
            else:
                # 指定された間隔後の時間をスケジュール
                scheduled_time = now + timezone.timedelta(minutes=interval_minutes)
                logger.info(f'スケジュール投稿モード: 予定時刻 = {scheduled_time} (現在時刻から{interval_minutes}分後)')
            
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
            
            logger.info(f'投稿スケジュールを作成しました: ID={tweet.id}, 予定時刻={scheduled_time}, 画像={img_name}')
            
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
                        # 画像インデックスを更新（成功時のみ）
                        current_number = extract_number(next_image)
                        SystemSetting.update_last_image_index(current_number)
                        logger.info(f'投稿に成功しました！今日の投稿数: {counter.post_count}/{counter.max_daily_posts}')
                    else:
                        if post_result.get('rate_limited'):
                            # レートリミットの場合は特別な処理
                            tweet.status = 'rate_limited'
                            tweet.error_message = post_result['error']
                            tweet.save()
                            logger.warning(f'レートリミットに達しました: {post_result["error"]}')
                        else:
                            tweet.status = 'failed'
                            tweet.error_message = post_result['error']
                            tweet.save()    
                            logger.error(f'投稿に失敗しました: {post_result["error"]}')
                
                except Exception as e:
                    logger.error(f'投稿処理中にエラーが発生しました: {str(e)}')
                    if tweet:
                        tweet.status = 'failed'
                        tweet.error_message = str(e)
                        tweet.save()
        
        except Exception as e:
            logger.error(f'処理中にエラーが発生しました: {str(e)}')
            if tweet:
                tweet.status = 'failed'
                tweet.error_message = str(e)
                try:
                    tweet.save()
                except Exception as save_error:
                    logger.error(f'エラー状態の保存に失敗しました: {str(save_error)}') 