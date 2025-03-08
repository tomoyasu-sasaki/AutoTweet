from django.core.management.base import BaseCommand
from x_scheduler.utils import process_scheduled_tweets, test_api_connection
from django.conf import settings
import logging
import time
import datetime
from x_scheduler.models import TweetSchedule, DailyPostCounter, SystemSetting
from django.utils import timezone

logger = logging.getLogger('x_scheduler')

class Command(BaseCommand):
    help = '待機中の予定時刻を過ぎたツイートを投稿する'

    def add_arguments(self, parser):
        parser.add_argument('--skip-api-test', action='store_true', help='API接続テストをスキップする')
        parser.add_argument('--abort-on-error', action='store_true', help='API接続テストに失敗した場合に処理を中止する')
        parser.add_argument('--max-retries', type=int, default=3, help='レート制限エラー時の最大リトライ回数')
        parser.add_argument('--peak-hour', action='store_true', help='ピーク時間帯（6時、12時、18時）に実行する場合のフラグ')
        parser.add_argument('--force-api-test', action='store_true', help='API接続テストを強制的に実行する')
        parser.add_argument('--max-posts', type=int, default=None, help='この実行で処理する最大投稿数')

    def handle(self, *args, **options):
        try:
            skip_api_test = options['skip_api_test']
            abort_on_error = options['abort_on_error']
            max_retries = options['max_retries']
            force_api_test = options['force_api_test']
            peak_hour = options['peak_hour']
            
            # APIキーの確認
            logger.info(f"APIキー: {settings.X_API_KEY[:5]}... (最初の5文字のみ表示)")
            logger.info(f"APIシークレット: {settings.X_API_SECRET[:5]}... (最初の5文字のみ表示)")
            logger.info(f"アクセストークン: {settings.X_ACCESS_TOKEN[:5]}... (最初の5文字のみ表示)")
            
            # 先に処理対象のツイート数を確認
            now = timezone.now()
            pending_tweets = TweetSchedule.objects.filter(
                status='pending',
                scheduled_time__lte=now
            )
            pending_count = pending_tweets.count()
            logger.info(f"処理対象のツイート数: {pending_count}")
            
            # ツイートがなく、強制実行オプションがなければAPI接続テストをスキップ
            if pending_count == 0 and not force_api_test:
                logger.info("処理対象のツイートがないため、API接続テストをスキップします")
                skip_api_test = True
            
            # 今日すでにAPI接続テストを行ったかチェック（DBから）
            already_tested_today = SystemSetting.is_api_test_done_today()
            peak_hour_tested = SystemSetting.is_peak_hour_tested_today() if already_tested_today else False
            
            if already_tested_today:
                logger.info(f"本日はすでにAPI接続テストを実施済みです。ピーク時間帯テスト状況: {peak_hour_tested}")
            
            # 以下の場合に接続テストをスキップ:
            # 1. 明示的にスキップが指定されている
            # 2. 今日すでにテスト済みで、現在がピーク時間でない、またはピーク時間でも既にテスト済み
            should_skip_test = skip_api_test or (already_tested_today and (not peak_hour or peak_hour_tested))
            
            # API接続テスト
            api_connected = True
            if not should_skip_test:
                logger.info("API接続テストを実行します。(/2/users/me エンドポイントは24時間に25リクエストの制限があります)")
                retry_count = 0
                while retry_count <= max_retries:
                    try:
                        # API接続テスト関数を使用
                        test_result = test_api_connection()
                        
                        if test_result["success"]:
                            logger.info("X APIに正常に接続できました。")
                            
                            # 接続テスト成功をDBに記録（ピーク時間帯かどうかも記録）
                            SystemSetting.mark_api_test_done(peak=peak_hour)
                            
                            break
                        else:
                            raise Exception(test_result["error"])
                    except Exception as e:
                        retry_count += 1
                        error_msg = str(e)
                        logger.error(f"X APIへの接続テストに失敗しました ({retry_count}/{max_retries}): {error_msg}")
                        
                        # レート制限エラーの場合
                        if "429 Too Many Requests" in error_msg:
                            wait_time = min(60 * retry_count, 300)  # 再試行ごとに待機時間を長くする（最大5分）
                            logger.info(f"レート制限に達しました。{wait_time}秒間待機します...")
                            time.sleep(wait_time)
                        elif retry_count >= max_retries:
                            logger.error(f"最大再試行回数に達しました。API接続テストを中止します。")
                            api_connected = False
                            if abort_on_error:
                                logger.error("処理を中止します。")
                                return
                            break
                        else:
                            # その他のエラーの場合は短い待機時間
                            time.sleep(5)
            else:
                logger.info("API接続テストはスキップします。")
            
            # 接続テストに失敗し、かつ中断オプションが指定されている場合
            if not api_connected and abort_on_error:
                logger.error("API接続テストに失敗したため、処理を中止します。")
                return
            
            # 投稿数制限のチェック
            counter = DailyPostCounter.get_or_create_today()
            if counter.limit_reached:
                logger.warning(f"本日の投稿上限（{counter.max_daily_posts}）に達しています。残り投稿数: {counter.remaining_posts}")
            else:
                logger.info(f"本日の投稿数: {counter.post_count}/{counter.max_daily_posts}, 残り: {counter.remaining_posts}")
            
            # ツイート処理
            logger.info("スケジュールされたツイートを処理します")
            
            # 状態が「保留中」のスケジュールを取得
            pending_schedules = TweetSchedule.objects.filter(
                status='pending',
                scheduled_time__lte=timezone.now()
            ).order_by('scheduled_time')
            
            if not pending_schedules:
                logger.info("処理対象のツイートがありません。")
                return
            
            logger.info(f"処理対象のツイート数: {pending_schedules.count()}")
            
            # 最大投稿数の制限
            max_posts = options.get('max_posts')
            if max_posts is not None and max_posts > 0:
                logger.info(f"最大投稿数が設定されています: {max_posts}")
                if pending_schedules.count() > max_posts:
                    logger.info(f"処理対象を {max_posts} 件に制限します")
                    pending_schedules = pending_schedules[:max_posts]
            
            # 日次投稿制限のチェック
            available_posts = counter.remaining_posts
            if max_posts is not None:
                available_posts = min(available_posts, max_posts)
            
            if available_posts <= 0:
                logger.warning("本日の投稿可能数が0のため、処理をスキップします。")
                return
            
            if pending_schedules.count() > available_posts:
                logger.info(f"制限により処理対象を {available_posts} 件に制限します")
                pending_schedules = pending_schedules[:available_posts]
            
            # 残りの処理続行
            processed_count = process_scheduled_tweets()
            
            # 投稿カウントを更新
            if processed_count > 0:
                for _ in range(processed_count):
                    counter.increment_count()
                logger.info(f"投稿カウントを更新しました。現在の投稿数: {counter.post_count}/{counter.max_daily_posts}")
            
            self.stdout.write(
                self.style.SUCCESS(f'{processed_count}件のスケジュールされたツイートを処理しました。')
            )
        except Exception as e:
            logger.error(f"ツイート処理中にエラーが発生しました: {str(e)}")
            self.stdout.write(
                self.style.ERROR(f'エラーが発生しました: {str(e)}')
            ) 