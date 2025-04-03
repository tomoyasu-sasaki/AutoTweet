from django.test import TestCase
from django.conf import settings
from unittest.mock import patch, MagicMock # モックを使用
import tweepy

from ..utils import TwitterAPIClient, process_scheduled_tweets
from ..models import TweetSchedule # process_scheduled_tweets のテストで使用

# テスト用の設定値 (APIキーなどはダミー)
TEST_X_API_KEY = "test_api_key"
TEST_X_API_SECRET = "test_api_secret"
TEST_X_ACCESS_TOKEN = "test_access_token"
TEST_X_ACCESS_TOKEN_SECRET = "test_access_token_secret"

class TwitterAPIClientTest(TestCase):

    @patch('tweepy.Client')
    @patch('tweepy.API')
    @patch('django.conf.settings.X_API_KEY', TEST_X_API_KEY)
    @patch('django.conf.settings.X_API_SECRET', TEST_X_API_SECRET)
    @patch('django.conf.settings.X_ACCESS_TOKEN', TEST_X_ACCESS_TOKEN)
    @patch('django.conf.settings.X_ACCESS_TOKEN_SECRET', TEST_X_ACCESS_TOKEN_SECRET)
    def test_init_successful(self, mock_api_constructor, mock_client_constructor):
        """API/Client の初期化が成功することをテスト"""
        mock_api_instance = MagicMock()
        mock_client_instance = MagicMock()
        mock_api_constructor.return_value = mock_api_instance
        mock_client_constructor.return_value = mock_client_instance

        client = TwitterAPIClient()

        # コンストラクタが正しい引数で呼び出されたか確認
        mock_api_constructor.assert_called_once()
        # API v1 (OAuth1UserHandler経由) の引数チェックは少し複雑なので省略可
        mock_client_constructor.assert_called_once_with(
            consumer_key=TEST_X_API_KEY,
            consumer_secret=TEST_X_API_SECRET,
            access_token=TEST_X_ACCESS_TOKEN,
            access_token_secret=TEST_X_ACCESS_TOKEN_SECRET
        )
        self.assertEqual(client.api_v1, mock_api_instance)
        self.assertEqual(client.client_v2, mock_client_instance)

    @patch('tweepy.Client', side_effect=Exception("V2 Init Error"))
    @patch('tweepy.API', side_effect=Exception("V1 Init Error"))
    def test_init_failure(self, mock_api_constructor, mock_client_constructor):
        """API/Client の初期化が失敗した場合をテスト"""
        client = TwitterAPIClient()
        self.assertIsNone(client.api_v1)
        self.assertIsNone(client.client_v2)
        # エラーログが出力されることも確認できるとなお良い (ロギングテスト)

    @patch.object(TwitterAPIClient, '_initialize_client_v2')
    @patch.object(TwitterAPIClient, '_initialize_api_v1')
    def test_test_connection_successful(self, mock_init_api, mock_init_client):
        """test_connection が成功する場合をテスト"""
        mock_api = MagicMock(spec=tweepy.API)
        mock_client = MagicMock(spec=tweepy.Client)
        mock_init_api.return_value = mock_api
        mock_init_client.return_value = mock_client

        # verify_credentials と get_me の戻り値を設定
        mock_user_v1 = MagicMock()
        mock_user_v1.screen_name = "testuser"
        mock_user_v1.id = "12345"
        mock_api.verify_credentials.return_value = mock_user_v1
        # mock_client.get_me.return_value = MagicMock() # 戻り値の中身はここでは重要でない
        # ↑ get_me は呼び出すだけにしたので return_value は不要

        client = TwitterAPIClient()
        result = client.test_connection()

        mock_api.verify_credentials.assert_called_once()
        mock_client.get_me.assert_called_once()
        self.assertTrue(result["success"])
        self.assertEqual(result["error"], "")

    @patch.object(TwitterAPIClient, '_initialize_client_v2')
    @patch.object(TwitterAPIClient, '_initialize_api_v1')
    def test_test_connection_v1_fails(self, mock_init_api, mock_init_client):
        """test_connection で v1 API 呼び出しが失敗する場合をテスト"""
        mock_api = MagicMock(spec=tweepy.API)
        mock_client = MagicMock(spec=tweepy.Client)
        mock_init_api.return_value = mock_api
        mock_init_client.return_value = mock_client

        # verify_credentials が例外を発生させるように設定
        mock_api.verify_credentials.side_effect = tweepy.errors.TweepyException("V1 Auth Error")

        client = TwitterAPIClient()
        result = client.test_connection()

        mock_api.verify_credentials.assert_called_once()
        mock_client.get_me.assert_not_called() # v1 で失敗したら v2 は呼ばれないはず
        self.assertFalse(result["success"])
        self.assertIn("V1 Auth Error", result["error"])

    @patch.object(TwitterAPIClient, '_initialize_client_v2')
    @patch.object(TwitterAPIClient, '_initialize_api_v1')
    def test_post_tweet_text_only_successful(self, mock_init_api, mock_init_client):
        """テキストのみのツイート投稿が成功する場合をテスト"""
        mock_api = MagicMock(spec=tweepy.API)
        mock_client = MagicMock(spec=tweepy.Client)
        mock_init_api.return_value = mock_api
        mock_init_client.return_value = mock_client

        # create_tweet の戻り値を設定
        mock_response_data = MagicMock()
        mock_response_data.id = "98765"
        mock_client.create_tweet.return_value = MagicMock(data=mock_response_data)

        client = TwitterAPIClient()
        result = client.post_tweet("Test tweet content")

        mock_client.create_tweet.assert_called_once_with(text="Test tweet content")
        mock_api.media_upload.assert_not_called() # 画像なしなので呼ばれない
        self.assertTrue(result["success"])
        self.assertEqual(result["error"], "")

    @patch.object(TwitterAPIClient, '_initialize_client_v2')
    @patch.object(TwitterAPIClient, '_initialize_api_v1')
    def test_post_tweet_with_media_successful(self, mock_init_api, mock_init_client):
        """画像付きツイート投稿が成功する場合をテスト"""
        mock_api = MagicMock(spec=tweepy.API)
        mock_client = MagicMock(spec=tweepy.Client)
        mock_init_api.return_value = mock_api
        mock_init_client.return_value = mock_client

        # media_upload と create_tweet の戻り値を設定
        mock_media = MagicMock()
        mock_media.media_id = "media123"
        mock_api.media_upload.return_value = mock_media

        mock_response_data = MagicMock()
        mock_response_data.id = "54321"
        mock_client.create_tweet.return_value = MagicMock(data=mock_response_data)

        # モックのファイルオブジェクトを作成
        mock_file = MagicMock()

        client = TwitterAPIClient()
        result = client.post_tweet("Tweet with image", filename="image.jpg", file=mock_file)

        mock_api.media_upload.assert_called_once_with(filename="image.jpg", file=mock_file)
        mock_client.create_tweet.assert_called_once_with(text="Tweet with image", media_ids=["media123"])
        self.assertTrue(result["success"])
        self.assertEqual(result["error"], "")

    @patch.object(TwitterAPIClient, '_initialize_client_v2')
    @patch.object(TwitterAPIClient, '_initialize_api_v1')
    def test_post_tweet_rate_limit_error(self, mock_init_api, mock_init_client):
        """ツイート投稿でレートリミットエラーが発生する場合をテスト"""
        mock_api = MagicMock(spec=tweepy.API)
        mock_client = MagicMock(spec=tweepy.Client)
        mock_init_api.return_value = mock_api
        mock_init_client.return_value = mock_client

        # create_tweet がレートリミットエラー (429) を発生させるように設定
        # 修正: response をキーワード引数で渡せないため、関数で例外を生成・設定する
        def raise_rate_limit(*args, **kwargs):
            mock_response = MagicMock()
            mock_response.status_code = 429
            exc = tweepy.errors.TweepyException("Rate limit exceeded")
            exc.response = mock_response # response 属性を後から設定
            raise exc

        mock_client.create_tweet.side_effect = raise_rate_limit
        # mock_client.create_tweet.side_effect = tweepy.errors.TweepyException("Rate limit exceeded", response=mock_response)

        client = TwitterAPIClient()
        result = client.post_tweet("Rate limit test")

        mock_client.create_tweet.assert_called_once_with(text="Rate limit test")
        self.assertFalse(result["success"])
        self.assertIn("Rate limit exceeded", result["error"])
        self.assertTrue(result["is_rate_limit"])

# TODO: process_scheduled_tweets のテストを追加する
# - DB操作 (TweetSchedule.objects.filter など) のモック
# - TwitterAPIClient.post_tweet のモック
# - ファイル操作 (image.open, close) のモック (必要なら)
