from x_scheduler.utils import process_scheduled_tweets, TwitterAPIClient
from django.conf import settings
import logging
import time
# import datetime # 未使用
# import os # 未使用
from x_scheduler.models import TweetSchedule, DailyPostCounter, SystemSetting
from django.utils import timezone
from django.core.management.base import BaseCommand

# ロガーの設定
logger = logging.getLogger(__name__)


class Command(BaseCommand):
    help = "待機中の予定時刻を過ぎたツイートを投稿する"

    def add_arguments(self, parser):
        parser.add_argument(
            "--skip-api-test", action="store_true", help="API接続テストをスキップする"
        )
        parser.add_argument(
            "--abort-on-error",
            action="store_true",
            help="API接続テストに失敗した場合に処理を中止する",
        )
        parser.add_argument(
            "--max-retries",
            type=int,
            default=3,
            help="レート制限エラー時の最大リトライ回数",
        )
        parser.add_argument(
            "--peak-hour",
            action="store_true",
            help="ピーク時間帯（6時、12時、18時）に実行する場合のフラグ",
        )
        parser.add_argument(
            "--force-api-test",
            action="store_true",
            help="API接続テストを強制的に実行する",
        )
        parser.add_argument(
            "--max-posts", type=int, default=None, help="この実行で処理する最大投稿数"
        )

    def _perform_api_connection_test(self, options, api_client):
        """API接続テストを実行し、成功/失敗を返す。APIクライアントを受け取るように変更。"""
        max_retries = options['max_retries']
        abort_on_error = options['abort_on_error']
        # peak_hour = options['peak_hour'] # 未使用のためコメントアウト
        retry_count = 0
        
        logger.info("API接続テストを実行します。")
        while retry_count <= max_retries:
            try:
                # 修正: 引数で受け取った api_client のメソッドを使用
                test_result = api_client.test_connection()
                if test_result["success"]:
                    logger.info("X APIに正常に接続できました。")
                    today_str = timezone.now().date().isoformat()
                    hour = timezone.now().hour
                    time_of_day = (
                        "morning"
                        if 5 <= hour < 12
                        else "afternoon" if 12 <= hour < 18 else "evening"
                    )
                    SystemSetting.set_value("api_test_last_date", today_str)
                    SystemSetting.set_value("api_test_last_time_of_day", time_of_day)
                    logger.info(
                        f"API接続テスト実行済みとしてマーク: {today_str} ({time_of_day})"
                    )
                    return True  # 接続成功
                else:
                    # エラーメッセージは test_connection 内でログ出力されるはず
                    raise Exception(test_result["error"])  # 再試行のために例外を発生
            except Exception as e:
                retry_count += 1
                error_msg = str(e)
                logger.error(
                    f"X APIへの接続テスト試行に失敗 ({retry_count}/{max_retries}): {error_msg}"
                )

                # test_connection の戻り値だけではレートリミットか判断できないため、エラーメッセージで判断
                # TODO: test_connection の戻り値に is_rate_limit を含める改善検討
                if "429" in error_msg or "Rate limit" in error_msg:  # 簡易的な判定
                    wait_time = min(60 * retry_count, 300)  # 待機時間
                    logger.info(f"レート制限の可能性。{wait_time}秒間待機します...")
                    time.sleep(wait_time)
                elif retry_count > max_retries:
                    logger.error(
                        f"最大再試行回数({max_retries}回)に達しました。API接続テストを中止します。"
                    )
                    break  # ループを抜ける (接続失敗)
                else:
                    # その他のエラーの場合、少し待機して再試行
                    time.sleep(5 * retry_count)

        # ループ終了後 (失敗時)
        if abort_on_error:
            logger.error(
                "API接続テストに失敗し、abort-on-errorが指定されているため処理を中止します。"
            )
            return False  # 接続失敗 (処理中止)
        else:
            logger.warning("API接続テストに失敗しましたが、処理を続行します。")
            return True  # 接続失敗だが処理は続行

    def handle(self, *args, **options):
        try:
            skip_api_test = options['skip_api_test']
            # abort_on_error = options['abort_on_error'] # _perform_api_connection_test に渡されるが、このスコープでは未使用
            force_api_test = options['force_api_test']
            peak_hour = options['peak_hour'] # APIテスト判定ロジックで必要
            # max_posts = options.get('max_posts') # 現状未使用のためコメントアウト
            
            # APIクライアントをインスタンス化
            api_client = TwitterAPIClient()
            if not api_client.api_v1 or not api_client.client_v2:
                logger.error(
                    "APIクライアントの初期化に失敗しました。処理を中断します。"
                )
                return

            # --- APIキーログ出力 (削除) ---
            # logger.info(f"APIキー: {settings.X_API_KEY[:5]}... (最初の5文字のみ表示)")

            # --- API接続テストの要否判定 --- (変更なし)
            now = timezone.now()
            today_str = now.date().isoformat()
            hour = now.hour
            current_time_of_day = (
                "morning"
                if 5 <= hour < 12
                else "afternoon" if 12 <= hour < 18 else "evening"
            )
            pending_tweets = TweetSchedule.objects.filter(
                status="pending", scheduled_time__lte=now
            )
            pending_count = pending_tweets.count()
            logger.info(f"処理対象のツイート数(テスト判定前): {pending_count}")
            if pending_count == 0 and not force_api_test:
                logger.info(
                    "処理対象ツイートがなく、強制実行もないためAPI接続テストをスキップします"
                )
                skip_api_test = True
            last_test_date = SystemSetting.get_value("api_test_last_date")
            already_tested_today = last_test_date == today_str
            last_time_of_day = SystemSetting.get_value("api_test_last_time_of_day", "")
            peak_hour_tested = (
                already_tested_today and current_time_of_day == last_time_of_day
            )
            if already_tested_today:
                logger.info(
                    f"本日はすでにAPI接続テストを実施済みです。最後にテストした時間帯: {last_time_of_day}"
                )
            should_skip_test = skip_api_test or (
                already_tested_today and (not peak_hour or peak_hour_tested)
            )

            # --- API接続テスト実行 --- (変更: api_client を渡す)
            if not should_skip_test:
                if not self._perform_api_connection_test(options, api_client):
                    return  # テスト失敗 and abort の場合
            else:
                logger.info("API接続テストはスキップします。")

            # --- 投稿数制限チェック --- (変更なし)
            counter = DailyPostCounter.get_today_counter()
            if counter.is_limit_reached:
                logger.warning(
                    f"本日の投稿上限（{settings.MAX_DAILY_POSTS_PER_USER}）に達しています。残り投稿数: {counter.remaining_posts}"
                )
            else:
                logger.info(
                    f"本日の投稿数: {counter.post_count}/{settings.MAX_DAILY_POSTS_PER_USER}, 残り: {counter.remaining_posts}"
                )

            # --- ツイート処理実行 ---
            logger.info("スケジュールされたツイートを処理します")

            # process_scheduled_tweets は内部で再度クエリ＆APIクライアント初期化を行うため、
            # ここでの追加のフィルタリングやAPIクライアントの受け渡しは不要。
            # ただし、投稿制限の事前チェックは有効。
            available_posts = counter.remaining_posts
            if available_posts <= 0:
                logger.warning(
                    "本日の投稿可能数が0のため、ツイート処理をスキップします。"
                )
                return
            else:
                logger.info(f"本日の残り投稿可能数: {available_posts}")
                # process_scheduled_tweets 側で最終的な投稿数制限がかかることに注意。

            # utils.process_scheduled_tweets を呼び出す (これは内部で TwitterAPIClient を使う)
            processed_count = process_scheduled_tweets()

            # 投稿カウントを更新 (utils側でやったので不要？ いや、DailyPostCounter の更新はこちらでやるべきか)
            # → DailyPostCounter の更新は utils 側ではなく、呼び出し側 (コマンド) の責務とする方が良い。
            #   utils.process_scheduled_tweets は純粋にツイート処理に専念する。
            #   ただし、現状の utils.process_scheduled_tweets は成功カウントを返すだけなので、
            #   どのツイートが成功したかの情報がない。これを改善する必要がある。
            #
            #   一旦、現状の動作を維持し、戻り値の件数だけカウントアップする。
            #   (リファクタリングの余地あり)
            if processed_count > 0:
                logger.info(
                    f"utils.process_scheduled_tweets が {processed_count} 件の処理を報告しました。カウンターを更新します。"
                )
                # DailyPostCounter を最新の状態にする
                counter = DailyPostCounter.get_today_counter()
                initial_count = counter.post_count
                target_count = min(
                    initial_count + processed_count, settings.MAX_DAILY_POSTS_PER_USER
                )
                incremented = 0
                # 実際にカウントを増やす (上限を超えないように)
                for _ in range(target_count - initial_count):
                    counter.increment_count()
                    incremented += 1

                if incremented > 0:
                    # counter = DailyPostCounter.get_today_counter() # DBから再取得して確認
                    logger.info(
                        f"投稿カウンターを {incremented} 件増加させました。現在の投稿数: {counter.post_count}/{settings.MAX_DAILY_POSTS_PER_USER}"
                    )
                else:
                    logger.info(
                        "投稿カウンターの増加はありませんでした（既に上限 or 処理件数0）。"
                    )

            logger.info(
                f"{processed_count}件のスケジュールされたツイート処理が試行されました。"
            )  # ログメッセージ変更
        except Exception as e:
            logger.exception(
                f"ツイート処理コマンド全体で予期せぬエラーが発生しました: {str(e)}"
            )
