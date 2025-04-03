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
        """指定されたディレクトリから次に使用する画像を選択し、パスを返す。"""
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
            return None  # 画像が見つからない場合は None を返す

        # 画像ファイルを番号でソート
        try:
            image_files = sorted(image_files, key=extract_number)
        except Exception as e:
            logger.error(f"画像ファイル名の数値抽出またはソート中にエラー: {e}")
            # ソートに失敗した場合は、単純なファイル名ソートの結果を使う（あるいはエラーにする）
            pass  # ここでは単純ソートの結果で続行

        # 最後に使用した画像の番号を取得
        last_index_str = SystemSetting.get_value(
            "last_image_index", "0"
        )  # デフォルトを '0' に変更
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
        selected_image_number = -1  # ループ内で見つかったかどうかのフラグ兼数値
        for image_file_path in image_files:
            try:
                current_number = extract_number(image_file_path)
                if current_number > last_index:
                    next_image_path = image_file_path
                    selected_image_number = current_number
                    break  # 次の画像が見つかったらループ終了
            except Exception as e:
                logger.warning(
                    f"ファイル名からの数値抽出エラー: {os.path.basename(image_file_path)}, {e}"
                )
                # エラーが発生したファイルはスキップして続行
                continue

        # 最後まで到達した場合は最初に戻る
        if next_image_path is None:
            if image_files:  # 画像リストが空でないことを確認
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
                    # 最初の画像の数値が取れない場合、インデックス更新は行わずパスのみ返す
                    selected_image_number = -1  # 更新しないマーク
            else:
                # このケースは起こらないはずだが念のため
                logger.error("画像選択中に予期せず画像リストが空になりました")
                return None

        # 最後に使用したインデックスを更新 (有効な数値が取得できた場合のみ)
        if selected_image_number != -1:
            SystemSetting.set_value(
                "last_image_index",
                str(selected_image_number),
                "最後に使用した画像のインデックス",  # description は任意
            )
            logger.info(
                f"次に使用する画像番号として {selected_image_number} を記録しました。"
            )
        else:
            logger.warning(
                "選択された画像の番号が不正なため、最後に使用したインデックスの更新をスキップします。"
            )

        return next_image_path

    def handle(self, *args, **options):
        text = options["text"]
        image_dir = options["image_dir"]
        post_now = options["post_now"]
        interval_minutes = options["interval"]
        skip_api_test = options["skip_api_test"]
        force_api_test = options["force_api_test"]

        # APIクライアントをインスタンス化
        api_client = TwitterAPIClient()
        if not api_client.api_v1 or not api_client.client_v2:  # 初期化失敗チェック
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

        # 画像ディレクトリ、作成、選択 (変更なし)
        image_dir_path = os.path.join(settings.MEDIA_ROOT, image_dir)
        if not os.path.exists(image_dir_path):
            os.makedirs(image_dir_path)
            logger.info(f"画像ディレクトリを作成しました: {image_dir_path}")
        next_image_path = self._select_next_image(image_dir_path)
        if not next_image_path:
            logger.error("使用する画像が見つからなかったため、処理を終了します。")
            return
        logger.info(f"使用する画像: {os.path.basename(next_image_path)}")

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
        initial_status = 'pending' # Use model's default, will be updated if post_now
        if not post_now:
            initial_status = 'scheduled'

        # TweetScheduleオブジェクト作成 (status を追加)
        tweet = TweetSchedule(
            content=text,
            scheduled_time=scheduled_time,
            status=initial_status # Set initial status
        )
        img_name = None  # スコープ外で参照するため初期化
        try:
            # Read the image content first
            with open(next_image_path, 'rb') as image_file_content:
                img_name = os.path.basename(next_image_path)
                # Assign to the image field, but don't save the model yet
                tweet.image.save(img_name, File(image_file_content), save=False)

            # Save the TweetSchedule model to DB (this should save the image file physically)
            tweet.save()
            logger.info(
                f"投稿スケジュールを作成しました: ID={tweet.id}, 予定時刻={tweet.scheduled_time}, 画像={img_name}"
            )

            if post_now:
                logger.info(f"即時投稿処理を開始します: {tweet.id}")
                # Ensure the image path exists after saving the model
                if tweet.image and hasattr(tweet.image, 'path') and os.path.exists(tweet.image.path):
                    logger.info(f"画像パス確認OK: {tweet.image.path}")
                    image_file_object = None
                    try:
                        # Use the saved image path for posting
                        logger.info(f"画像ファイルを開きます: {tweet.image.path}")
                        image_file_object = tweet.image.open("rb")
                        post_result_dict = api_client.post_tweet(
                            content=tweet.content,
                            filename=tweet.image.name, # ファイル名も渡す
                            file=image_file_object # ファイルオブジェクトを渡す
                        )

                        if post_result_dict["success"]:
                            # 投稿成功時の処理
                            tweet.status = 'posted'
                            tweet.save(update_fields=['status', 'updated_at'])
                            counter.increment_count() # Increment counter on successful post
                            # 成功時のレスポンスデータは post_tweet 内でログ出力されているので、ここではシンプルに
                            logger.info(f"ツイート投稿成功: {tweet.id}")
                            logger.info(f"ステータスを POSTED に更新しました: {tweet.id}")
                            logger.info(f"投稿に成功しました！今日の投稿数: {counter.post_count}/{settings.MAX_DAILY_POSTS_PER_USER}")
                        else:
                            tweet.status = 'failed'
                            tweet.error_message = post_result_dict["error"]
                            tweet.save(update_fields=['status', 'error_message', 'updated_at'])
                            logger.error(f"ツイート投稿失敗: {tweet.id}, Error: {post_result_dict['error']}")
                    except Exception as e:
                        tweet.status = 'failed'
                        tweet.error_message = f"投稿処理中にエラー: {e}"
                        tweet.save(update_fields=['status', 'error_message', 'updated_at'])
                        logger.exception(f"即時投稿処理中に予期せぬエラー: {tweet.id}")
                    finally:
                        # ファイルオブジェクトを閉じる
                        if image_file_object:
                            try:
                                image_file_object.close()
                                logger.info(f"画像ファイルを閉じました: {tweet.image.name}")
                            except Exception as e_close:
                                logger.error(f"画像ファイルクローズエラー: {e_close}")
                else:
                    logger.error(f"即時投稿エラー: 保存された画像が見つかりません。Path: {getattr(tweet.image, 'path', 'N/A')}")
                    tweet.status = 'failed'
                    tweet.error_message = "投稿用画像が見つかりません"
                    tweet.save(update_fields=['status', 'error_message', 'updated_at'])

        except IOError as e:
            logger.error(f"画像ファイル処理エラー: {next_image_path}, エラー: {e}")
            # ここでスケジュール作成失敗の処理が必要な場合がある
            # 例: tweet.delete() など
            # 今回はエラーログのみ
            # Schedule creation might fail here if image is crucial, handle appropriately
            # For now, we log the error and potentially proceed without image or fail
            # tweet.status = 'failed' ... # Handle failure if needed

        logger.info("auto_post コマンドの実行を終了します。")
