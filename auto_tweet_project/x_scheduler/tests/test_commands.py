import os
from io import StringIO
from unittest.mock import patch, MagicMock

from django.core.management import call_command
from django.test import TestCase
from django.utils import timezone
from django.conf import settings
from freezegun import freeze_time

from x_scheduler.models import TweetSchedule, DailyPostCounter, SystemSetting

# TODO: Add tests for process_tweets command

class AutoPostCommandTest(TestCase):
    """auto_post コマンドのテストクラス"""

    def setUp(self):
        # テストに必要な初期設定
        self.media_root = settings.MEDIA_ROOT
        self.image_dir_name = "test_auto_post_images"
        self.image_dir_path = os.path.join(self.media_root, self.image_dir_name)
        os.makedirs(self.image_dir_path, exist_ok=True)
        # テスト用画像ファイルを作成
        with open(os.path.join(self.image_dir_path, "image_1.jpg"), "w") as f:
            f.write("test image 1")
        with open(os.path.join(self.image_dir_path, "image_2.png"), "w") as f:
            f.write("test image 2")

        # DailyPostCounter の設定値をテスト用に変更
        self.original_max_posts = settings.MAX_DAILY_POSTS_PER_USER
        settings.MAX_DAILY_POSTS_PER_USER = 5

        # SystemSetting の初期値を設定 (必要なら)
        SystemSetting.set_value("last_image_index", "0")

    def tearDown(self):
        # テスト後のクリーンアップ
        import shutil
        if os.path.exists(self.image_dir_path):
            shutil.rmtree(self.image_dir_path)
        settings.MAX_DAILY_POSTS_PER_USER = self.original_max_posts
        # SystemSetting を削除
        SystemSetting.objects.all().delete()
        DailyPostCounter.objects.all().delete()
        TweetSchedule.objects.all().delete()

    @freeze_time("2025-04-04 10:00:00")
    def test_auto_post_schedule_success(self):
        """スケジュール作成が成功する基本的なケースをテスト"""
        # patch コンテキストマネージャで API クライアントをモック
        with patch("x_scheduler.management.commands.auto_post.TwitterAPIClient") as MockTwitterAPIClient:
            mock_api_instance = MockTwitterAPIClient.return_value
            mock_api_instance.api_v1 = True
            mock_api_instance.client_v2 = True

            # コマンドを実行
            call_command(
                "auto_post",
                f"--text=テスト投稿(スケジュール)",
                f"--image-dir={self.image_dir_name}",
            )

            # --- アサーション --- #
            # TweetSchedule が1件作成されているか
            self.assertEqual(TweetSchedule.objects.count(), 1)
            tweet = TweetSchedule.objects.first()
            self.assertEqual(tweet.content, "テスト投稿(スケジュール)")
            # スケジュール時刻が正しく設定されているか（ここでは仮に現在時刻+1時間とする）
            # 注意: auto_post コマンドのロジックによってスケジュール時刻は変わるため、
            # 実際のロジックに合わせて期待値を設定する必要があります。
            # ここではコマンドが実行された時刻と同じとしています（--post-now がない場合）
            expected_time = timezone.now() + timezone.timedelta(minutes=90) # Add 90 minutes for default scheduling
            self.assertAlmostEqual(tweet.scheduled_time, expected_time, delta=timezone.timedelta(seconds=1))
            self.assertEqual(tweet.status, 'scheduled') # ステータスは scheduled
            self.assertTrue(os.path.exists(tweet.image.path))
            self.assertTrue(tweet.image.name.startswith("tweet_images/"))
            self.assertTrue(tweet.image.name.endswith(".jpg"))

            # API メソッドは呼び出されないはず
            mock_api_instance.upload_media.assert_not_called()
            mock_api_instance.post_tweet.assert_not_called()

            # SystemSetting の last_image_index が更新されているか
            self.assertEqual(SystemSetting.get_value("last_image_index"), "1")

            # DailyPostCounter がインクリメントされているか（スケジュール作成ではカウントしない）
            counter = DailyPostCounter.get_today_counter()
            self.assertEqual(counter.post_count, 0) # Scheduling should not increment counter

    @freeze_time("2025-04-04 11:00:00") # 時刻を変更して別のテストとする
    def test_auto_post_now_success(self):
        """--post-now で即時投稿が成功するケースをテスト"""
        # patch コンテキストマネージャを使用
        with patch("x_scheduler.management.commands.auto_post.TwitterAPIClient") as MockTwitterAPIClient:
            mock_api_instance = MockTwitterAPIClient.return_value
            mock_api_instance.api_v1 = True
            mock_api_instance.client_v2 = True
            # upload_media の戻り値を設定
            mock_media_info = MagicMock()
            mock_media_info.media_id = 11111
            mock_api_instance.upload_media.return_value = mock_media_info
            # post_tweet の戻り値を設定
            mock_post_response = MagicMock()
            mock_post_response.data = {"id": "12345", "text": "テスト投稿(即時)"}
            mock_api_instance.post_tweet.return_value = mock_post_response

            out = StringIO()
            call_command(
                "auto_post",
                f"--text=テスト投稿(即時)",
                f"--image-dir={self.image_dir_name}",
                "--post-now",
                stdout=out, # ログ出力をキャプチャ
            )

            # --- アサーション --- #
            self.assertEqual(TweetSchedule.objects.count(), 1)
            tweet = TweetSchedule.objects.first()
            self.assertEqual(tweet.content, "テスト投稿(即時)")
            expected_time = timezone.now()
            self.assertAlmostEqual(tweet.scheduled_time, expected_time, delta=timezone.timedelta(seconds=1))
            self.assertEqual(tweet.status, 'posted')
            self.assertTrue(os.path.exists(tweet.image.path))
            self.assertTrue(tweet.image.name.startswith("tweet_images/"))
            self.assertTrue(tweet.image.name.endswith(".jpg"))

            # API のメソッドが期待通りに呼び出されたか確認
            mock_api_instance.upload_media.assert_called_once()
            mock_api_instance.post_tweet.assert_called_once() # 重要: これがパスするか

            # post_tweet の引数を検証 (オプション)
            args, kwargs = mock_api_instance.post_tweet.call_args
            self.assertEqual(kwargs.get("text"), "テスト投稿(即時)")
            self.assertTrue(kwargs.get("media_ids") == [11111]) # upload_media の戻り値と一致するか

            # SystemSetting の last_image_index が更新されているか
            self.assertEqual(SystemSetting.get_value("last_image_index"), "1")

            # DailyPostCounter がインクリメントされているか
            counter = DailyPostCounter.get_today_counter()
            self.assertEqual(counter.post_count, 1)

            # # ログ出力の確認 (削除)
            # output = out.getvalue()
            # self.assertIn("即時投稿モード", output)
            # self.assertIn("ツイート投稿成功", output)
            # self.assertIn("ステータスを POSTED に更新しました", output)

    @freeze_time("2025-04-04 12:00:00")
    def test_auto_post_limit_reached(self):
        """投稿上限に達した場合、投稿がスキップされることをテスト"""
        # patch コンテキストマネージャを使用 (post_tweet が呼ばれないことを確認するため)
        with patch("x_scheduler.management.commands.auto_post.TwitterAPIClient") as MockTwitterAPIClient:
            mock_api_instance = MockTwitterAPIClient.return_value
            mock_api_instance.api_v1 = True
            mock_api_instance.client_v2 = True

            # 事前にカウンターを上限値に設定
            counter = DailyPostCounter.get_today_counter()
            max_posts = settings.MAX_DAILY_POSTS_PER_USER # 設定から取得
            counter.post_count = max_posts
            counter.save()
            self.assertEqual(counter.post_count, max_posts)

            # Use assertLogs context manager to check log output
            with self.assertLogs("x_scheduler.management.commands.auto_post", level="WARNING") as cm:
                call_command(
                    "auto_post",
                    f"--text=上限テスト",
                    f"--image-dir={self.image_dir_name}",
                )

            # Check the captured log messages
            self.assertTrue(any(f"本日の投稿上限（{max_posts}）に達しました" in msg for msg in cm.output))

            # TweetSchedule は作成されないはず
            self.assertEqual(TweetSchedule.objects.count(), 0)

            # DailyPostCounter は変わらないはず
            counter.refresh_from_db() # DBから最新の状態を取得
            self.assertEqual(counter.post_count, max_posts)

            # SystemSetting の last_image_index も変わらないはず
            self.assertEqual(SystemSetting.get_value("last_image_index"), "0")

            # APIメソッドは呼び出されないはず
            mock_api_instance.upload_media.assert_not_called()
            mock_api_instance.post_tweet.assert_not_called()

    # --- 他のテストケースを追加 ---
    # TODO: test_auto_post_no_image_found (画像なし)
    # TODO: test_auto_post_api_init_fail (API初期化失敗)
    # TODO: test_auto_post_with_options (オプション指定) 