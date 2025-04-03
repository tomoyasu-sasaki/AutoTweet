import glob
import logging
import os
from pathlib import Path

from django.conf import settings
from django.core.files import File
from django.core.management.base import BaseCommand
from django.utils import timezone
from x_scheduler.models import DailyPostCounter, SystemSetting, TweetSchedule
from x_scheduler.utils import TwitterAPIClient

# ロガーの設定 (settings.py の設定を使用するように修正)
logger = logging.getLogger(__name__)  # or logger = logging.getLogger('x_scheduler')


def extract_number(filename):
    # ファイル名から数字部分を抽出（例：image_0085.pngから85を取得）
    import re

    match = re.search(r"image_(\d+)", filename)
    return int(match.group(1)) if match else 0


class Command(BaseCommand):
    help = "指定されたテキストと画像を使って自動投稿を作成する"

    def add_arguments(self, parser):
        parser.add_argument(
            "--text",
            type=str,
            default=os.getenv("DEFAULT_TWEET_TEXT", "#投稿テキスト"),
            help="投稿するテキスト",
        )
        parser.add_argument(
            "--image-dir",
            type=str,
            default=os.getenv("DEFAULT_IMAGE_DIR", "auto_post_images"),
            help="画像が保存されているディレクトリ（mediaディレクトリからの相対パス）",
        )
        parser.add_argument(
            "--post-now",
            action="store_true",
            help="すぐに投稿する（指定しない場合はスケジュールのみ作成）",
        )
        parser.add_argument(
            "--interval",
            type=int,
            default=int(os.getenv("POST_INTERVAL_MINUTES", "90")),
            help="次回投稿までの間隔（分）",
        )
        parser.add_argument(
            "--skip-api-test",
            action="store_true",
            help="API接続テストをスキップする",
        )
        parser.add_argument(
            "--force-api-test",
            action="store_true",
            help="API接続テストを強制的に実行する",
        )
        parser.add_argument(
            "--peak-hour",
            action="store_true",
            help="ピーク時間帯（6時、12時、18時）の処理であることを示す",
        )

    def _select_next_image(self, image_dir_path):
        """指定されたディレクトリから次に使用する画像を選択し、パスと番号を返す。"""
        # 画像ファイルのリストを取得（数字順にソート）
        image_files = sorted(glob.glob(os.path.join(image_dir_path, "image_*.png")))
        image_files.extend(
            sorted(glob.glob(os.path.join(image_dir_path, "image_*.jpg")))
        )
        image_files.extend(
            sorted(glob.glob(os.path.join(image_dir_path, "image_*.jpeg")))
        )

        if not image_files:
            logger.warning(f"画像が見つかりません: {image_dir_path}")
            return None, -1

        # 画像ファイルを番号でソート
        try:
            image_files = sorted(image_files, key=extract_number)
        except Exception as e:
            logger.error(f"画像ファイル名の数値抽出またはソート中にエラー: {e}")
            pass

        # 最後に使用した画像の番号を取得
        last_index_str = SystemSetting.get_value(
            "last_image_index", "0"
        )
        try:
            last_index = int(last_index_str)
        except ValueError:
            logger.warning(
                f"SystemSetting の 'last_image_index' の値が無効です: '{last_index_str}'。0として扱います。"
            )
            last_index = 0

        logger.info(f"最後に使用した画像番号: {last_index}")

        # 次の画像を選択
        next_image_path = None
        selected_image_number = -1
        for image_file_path in image_files:
            try:
                current_number = extract_number(image_file_path)
                if current_number > last_index:
                    next_image_path = image_file_path
                    selected_image_number = current_number
                    break
            except Exception as e:
                logger.warning(
                    f"ファイル名からの数値抽出エラー: {os.path.basename(image_file_path)}, {e}"
                )
                continue

        # 最後まで到達した場合は最初に戻る
        if next_image_path is None:
            if image_files:
                next_image_path = image_files[0]
                try:
                    selected_image_number = extract_number(image_files[0])
                    logger.info(
                        f"最後の画像まで使用したため、最初に戻ります: {os.path.basename(next_image_path)}"
                    )
                except Exception as e:
                    logger.error(
                        f"最初の画像の数値抽出エラー: {os.path.basename(image_files[0])}, {e}"
                    )
                    selected_image_number = -1
            else:
                logger.error("画像選択中に予期せず画像リストが空になりました")
                return None, -1

        return next_image_path, selected_image_number

    def handle(self, *args, **options):
        text = options["text"]
        image_dir = options["image_dir"]
        post_now = options["post_now"]
        interval_minutes = options["interval"]
        skip_api_test = options["skip_api_test"]
        force_api_test = options["force_api_test"]

        # APIクライアントをインスタンス化
        api_client = TwitterAPIClient()
        if not api_client.api_v1 or not api_client.client_v2:
            logger.error("APIクライアントの初期化に失敗しました。処理を中断します。")
            return

        # API接続テストの処理 (api_client.test_connection を使用)
        if force_api_test or (not skip_api_test):
            now_test = timezone.now()  # APIテスト用の時刻取得
            today_str = now_test.date().isoformat()
            last_test_date = SystemSetting.get_value("api_test_last_date")
            already_tested_today = last_test_date == today_str

            if not already_tested_today:
                logger.info("API接続テストを実行しています...")
                test_result = (
                    api_client.test_connection()
                )  # 修正: クラスのメソッドを使用
                if test_result["success"]:
                    # APIテスト成功時の処理 (変更なし)
                    hour = now_test.hour
                    time_of_day = (
                        "morning"
                        if 5 <= hour < 12
                        else "afternoon" if 12 <= hour < 18 else "evening"
                    )
                    SystemSetting.set_value("api_test_last_date", today_str)
                    SystemSetting.set_value("api_test_last_time_of_day", time_of_day)
                    logger.info(f"API接続テスト成功")
                else:
                    logger.error(f'API接続テスト失敗: {test_result["error"]}')
                    return  # APIテスト失敗時は終了
            else:
                logger.info(
                    "今日はすでにAPI接続テストが完了しています。スキップします。"
                )
        else:
            logger.info("API接続テストはスキップされました。")

        # 投稿数制限のチェック (変更なし)
        counter = DailyPostCounter.get_today_counter()
        if counter.is_limit_reached:
            # 修正: settings定数を参照
            logger.warning(
                f"本日の投稿上限（{settings.MAX_DAILY_POSTS_PER_USER}）に達しました。投稿をスキップします。"
            )
            return

        # 画像ディレクトリ、作成、選択 (変更: selected_image_number を受け取る)
        image_dir_path = os.path.join(settings.MEDIA_ROOT, image_dir)
        if not os.path.exists(image_dir_path):
            os.makedirs(image_dir_path)
            logger.info(f"画像ディレクトリを作成しました: {image_dir_path}")
        next_image_path, selected_image_number = self._select_next_image(image_dir_path)
        if not next_image_path:
            logger.error("使用する画像が見つからなかったため、処理を終了します。")
            return
        if selected_image_number == -1:
            logger.error("選択された画像の番号が取得できなかったため、処理を終了します。")
            return

        logger.info(f"使用する画像: {os.path.basename(next_image_path)} (番号: {selected_image_number})")

        # 現在時刻、スケジュール時間設定 (変更なし)
        now = timezone.now()
        logger.info(
            f"現在時刻: {now} (タイムゾーン: {timezone.get_current_timezone()})"
        )
        if post_now:
            scheduled_time = now
            logger.info(f"即時投稿モード: 予定時刻 = {scheduled_time}")
        else:
            scheduled_time = now + timezone.timedelta(minutes=interval_minutes)
            logger.info(
                f"スケジュール投稿モード: 予定時刻 = {scheduled_time} (現在時刻から{interval_minutes}分後)"
            )

        # Determine initial status based on post_now
        initial_status = 'pending' if post_now else 'scheduled'

        # TweetScheduleオブジェクト作成 (status を設定)
        tweet = TweetSchedule(
            content=text,
            scheduled_time=scheduled_time,
            status=initial_status # Set initial status
        )

        # 画像ファイルをTweetScheduleに紐付け (まだ保存しない)
        relative_image_path = "" # スコープ外でも参照できるよう初期化
        try:
            with open(next_image_path, "rb") as image_file:
                # ファイル名をモデルフィールドに合わせて調整
                relative_image_path = os.path.join(image_dir, os.path.basename(next_image_path))
                tweet.image.save(relative_image_path, File(image_file), save=False) # DB保存は後で
            logger.info(f"画像パス確認OK: {next_image_path}")
        except FileNotFoundError:
            logger.error(f"画像ファイルが見つかりません: {next_image_path}")
            # TweetSchedule は未保存なのでここで終了
            return
        except Exception as e:
            logger.error(f"画像ファイルのオープンまたは読み込み中にエラー: {e}")
            # TweetSchedule は未保存なのでここで終了
            return

        # TweetScheduleをデータベースに保存 (スケジュールのみの場合も一旦保存)
        try:
            tweet.save()
            logger.info(
                f"投稿スケジュールを作成/更新しました: ID={tweet.id}, Status={tweet.status}, Scheduled={tweet.scheduled_time}"
            )
        except Exception as e:
            logger.error(f"TweetScheduleの保存中にエラー: {e}", exc_info=True)
            # DB保存に失敗した場合、続行できないので終了
            return

        # 即時投稿(--post-now)の場合の処理
        if post_now:
            logger.info(f"即時投稿処理を開始します: {tweet.id}")
            try:
                # APIクライアントを使って実際に投稿
                with open(next_image_path, "rb") as image_file_for_upload: # 再度ファイルを開く
                    logger.info(f"画像ファイルを開きます(投稿用): {next_image_path}")
                    # API経由で投稿
                    post_result = api_client.post_tweet_with_media(
                        text=tweet.content, media_file=image_file_for_upload
                    )

                # 投稿成功時の処理
                if post_result["success"]:
                    tweet.status = "posted"
                    tweet.posted_at = timezone.now()
                    tweet.tweet_id = post_result.get("tweet_id") # tweet_idを取得して保存
                    # --- 成功時の更新処理 ---
                    # 1. DailyPostCounter をインクリメント
                    counter.increment_post_count()
                    logger.info(f"本日の投稿数をインクリメントしました。")
                    # 2. SystemSetting の last_image_index を更新
                    SystemSetting.set_value( # Update last index only on success
                        "last_image_index",
                        str(selected_image_number),
                        f"auto_post成功による更新 ({os.path.basename(next_image_path)})",
                    )
                    logger.info(f"最後に使用した画像番号を {selected_image_number} に更新しました。")
                    # 3. TweetSchedule のステータス等を保存
                    tweet.save()
                    logger.info(
                        f"ツイート投稿成功: ID={tweet.id}, TweetID={tweet.tweet_id}"
                    )
                    logger.info(f"投稿に成功しました！今日の投稿数: {counter.post_count}/{settings.MAX_DAILY_POSTS_PER_USER}")

                # 投稿失敗時の処理
                else:
                    error_message = post_result.get("error", "不明なエラー")
                    tweet.status = "failed"
                    tweet.error_message = f"Tweet posting error (API): {error_message}" # Indicate API error
                    # --- 失敗時の処理 ---
                    # カウンター、画像インデックスは更新しない
                    tweet.save() # エラーステータスを保存
                    logger.error(
                        f"ツイート投稿失敗 (API): {tweet.id}, Error: {tweet.error_message}"
                    )
                    # 失敗を記録して終了

            # 即時投稿時の try ブロックに対する一般的な Exception ハンドリング
            except Exception as e:
                # 予期せぬエラーが発生した場合
                error_message = str(e)
                tweet.status = "failed"
                # traceback を含めると詳細がわかる
                import traceback
                tb_str = traceback.format_exc()
                tweet.error_message = f"Unexpected error during post: {error_message}
{tb_str}"
                # --- 失敗時の処理 ---
                # カウンター、画像インデックスは更新しない
                tweet.save() # エラーステータスを保存
                logger.error(f"即時投稿中に予期せぬエラー: {tweet.id}, Error: {error_message}", exc_info=True)
                # 失敗を記録して終了

        # コマンド終了ログ
        logger.info("auto_post コマンドの実行を終了します。")
