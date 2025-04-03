import tweepy
import logging
from django.conf import settings
from django.utils import timezone

# import tempfile # 不要になったので削除

# ロガーの設定
logger = logging.getLogger(__name__)


# --- TwitterAPIClient Class ---
class TwitterAPIClient:
    """
    Tweepy API v1.1 と v2 のクライアントを管理し、
    関連する操作 (テスト接続、ツイート投稿) を提供するクラス。
    """

    def __init__(self):
        self.api_v1 = self._initialize_api_v1()
        self.client_v2 = self._initialize_client_v2()

    def _initialize_api_v1(self):
        """API v1.1 クライアントを初期化"""
        try:
            auth = tweepy.OAuth1UserHandler(
                settings.X_API_KEY,
                settings.X_API_SECRET,
                settings.X_ACCESS_TOKEN,
                settings.X_ACCESS_TOKEN_SECRET,
            )
            api = tweepy.API(auth)
            logger.debug("Tweepy API v1.1 client initialized successfully.")
            return api
        except Exception as e:
            logger.error(f"Failed to initialize Tweepy API v1.1 client: {str(e)}")
            return None

    def _initialize_client_v2(self):
        """API v2 クライアントを初期化"""
        try:
            client = tweepy.Client(
                consumer_key=settings.X_API_KEY,
                consumer_secret=settings.X_API_SECRET,
                access_token=settings.X_ACCESS_TOKEN,
                access_token_secret=settings.X_ACCESS_TOKEN_SECRET,
            )
            logger.debug("Tweepy API v2 client initialized successfully.")
            return client
        except Exception as e:
            logger.error(f"Failed to initialize Tweepy API v2 client: {str(e)}")
            return None

    def test_connection(self):
        """API v1.1 と v2 の接続をテストする"""
        logger.info("Testing API connection...")
        if not self.api_v1 or not self.client_v2:
            error_msg = "API client(s) not initialized."
            logger.error(error_msg)
            return {"success": False, "error": error_msg}

        try:
            # v1 API test
            user = self.api_v1.verify_credentials()
            # v2 API test (結果は使わないが接続確認のために実行)
            self.client_v2.get_me()

            logger.info(
                f"API connection test successful: User @{user.screen_name}, ID: {user.id}"
            )
            return {"success": True, "error": ""}

        except tweepy.TweepyException as e:
            error_message = f"API connection test error (Tweepy): {str(e)}"
            logger.error(error_message)
            return {"success": False, "error": error_message}
        except Exception as e:
            error_message = f"API connection test error (Unknown): {str(e)}"
            logger.error(error_message)
            return {"success": False, "error": error_message}

    def post_tweet(self, content, filename=None, file=None):
        """指定された内容と画像でツイートを投稿する"""
        if not self.client_v2:
            logger.error("Tweet posting failed: API v2 client not initialized.")
            return {
                "success": False,
                "error": "API v2 client not initialized.",
                "is_rate_limit": False,
            }

        try:
            media_id = None
            if filename:
                # 画像アップロードには v1.1 API が必要
                if not self.api_v1:
                    logger.error(
                        "Tweet posting failed: API v1.1 client not initialized for media upload."
                    )
                    return {
                        "success": False,
                        "error": "API v1.1 client not initialized.",
                        "is_rate_limit": False,
                    }
                logger.info(f"Uploading media: {filename}")
                # filename と file オブジェクトを渡す
                media = self.api_v1.media_upload(filename=filename, file=file)
                media_id = media.media_id
                logger.info(f"Media uploaded successfully. Media ID: {media_id}")

            if media_id:
                # Post tweet with media (v2)
                response = self.client_v2.create_tweet(
                    text=content, media_ids=[media_id]
                )
                logger.info(f"Tweet with media posted successfully: {response.data}")
            else:
                # Post text-only tweet (v2)
                response = self.client_v2.create_tweet(text=content)
                logger.info(f"Text-only tweet posted successfully: {response.data}")

            return {"success": True, "error": ""}

        except tweepy.TweepyException as e:
            error_message = f"Tweet posting error (Tweepy): {str(e)}"
            is_rate_limit = False
            # hasattr で response 属性の存在を確認してからアクセス
            if hasattr(e, "response") and e.response and e.response.status_code == 429:
                error_message += " (Rate limit reached)"
                logger.warning(error_message)  # レートリミットは Warning とする
                is_rate_limit = True
            else:
                logger.error(error_message)
            return {
                "success": False,
                "error": error_message,
                "is_rate_limit": is_rate_limit,
            }
        except Exception as e:
            error_message = f"Tweet posting error (Unknown): {str(e)}"
            logger.error(error_message)
            return {"success": False, "error": error_message, "is_rate_limit": False}


# --- Standalone Functions ---
# (get_tweepy_api, get_tweepy_client, test_api_connection, post_tweet は削除)


def process_scheduled_tweets():
    """待機中の予定時刻を過ぎたツイートを処理する"""
    from .models import TweetSchedule  # 循環インポート回避

    # APIクライアントをインスタンス化
    api_client = TwitterAPIClient()
    # クライアント初期化失敗時は処理を中断
    if not api_client.api_v1 or not api_client.client_v2:
        logger.error(
            "Failed to process scheduled tweets: API client initialization failed."
        )
        return 0  # エラー時は処理せず終了 (処理件数0を返す)

    now = timezone.now()
    logger.info(f"Tweet processing started: Current time {now}")

    pending_tweets = TweetSchedule.objects.filter(
        status="pending", scheduled_time__lte=now
    )
    logger.info(f"Number of tweets to process: {pending_tweets.count()}")

    processed_count = 0
    for tweet in pending_tweets:
        logger.info(
            f"Processing tweet: ID={tweet.id}, Content={tweet.content[:20]}..., Scheduled={tweet.scheduled_time}"
        )

        image_file_object = None
        image_path_for_logging = None

        try:
            filename = None  # post_tweet に渡すファイル名
            if tweet.image:
                # 画像ファイルオブジェクトを開く
                logger.info(
                    f"Opening image file: {tweet.image.name} ({tweet.image.path})"
                )
                image_file_object = tweet.image.open("rb")
                image_path_for_logging = tweet.image.name
                filename = tweet.image.name  # 元のファイル名を filename として渡す

            # ツイート投稿 (APIクライアントのメソッドを使用)
            post_result = api_client.post_tweet(
                tweet.content,
                filename=filename,
                file=image_file_object,  # ファイルオブジェクトを渡す
            )

            if post_result["success"]:
                tweet.status = "posted"
                tweet.error_message = ""  # 成功時はエラーメッセージをクリア
                tweet.save()
                logger.info(f"Scheduled tweet posted successfully. ID: {tweet.id}")
                processed_count += 1
            else:
                tweet.status = "failed"
                tweet.error_message = post_result["error"]
                tweet.save()
                logger.error(
                    f"Failed to post scheduled tweet. ID: {tweet.id}, Error: {post_result['error']}"
                )
                # レートリミットの場合はループを中断することも検討できるが、
                # ここでは個々のツイートの失敗として記録し、処理を続ける

        except Exception as e:
            # 個々のツイート処理中の予期せぬエラー
            logger.error(
                f"Error during tweet processing loop for tweet ID {tweet.id}: {str(e)}",
                exc_info=True,
            )
            tweet.status = "failed"
            tweet.error_message = f"Unexpected error: {str(e)}"
            tweet.save()
        finally:
            # ファイルオブジェクトを確実に閉じる
            if image_file_object:
                try:
                    image_file_object.close()
                    logger.info(f"Closed image file object: {image_path_for_logging}")
                except Exception as e_close:
                    logger.error(
                        f"Error closing image file object for tweet ID {tweet.id}: {str(e_close)}"
                    )

    logger.info(f"Finished processing tweets. Processed count: {processed_count}")
    return processed_count
