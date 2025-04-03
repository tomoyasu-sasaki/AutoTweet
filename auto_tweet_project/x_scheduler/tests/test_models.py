# auto_tweet_project/x_scheduler/tests/test_models.py

from django.test import TestCase
from django.utils import timezone
from django.conf import settings
from freezegun import freeze_time # 日時を固定するために freezegun を使用

from ..models import DailyPostCounter, SystemSetting

class DailyPostCounterModelTest(TestCase):

    def setUp(self):
        # テストごとに設定値をリセット（影響を与えないように）
        self.original_max_posts = settings.MAX_DAILY_POSTS_PER_USER
        settings.MAX_DAILY_POSTS_PER_USER = 5 # テスト用に上限を5に設定

    def tearDown(self):
        # 設定値を元に戻す
        settings.MAX_DAILY_POSTS_PER_USER = self.original_max_posts

    @freeze_time("2025-04-03 10:00:00") # テスト中の日時を固定
    def test_get_today_counter_creates_new_entry(self):
        """今日の日付のカウンターが存在しない場合、新しく作成されることをテスト"""
        self.assertEqual(DailyPostCounter.objects.count(), 0)
        counter = DailyPostCounter.get_today_counter()
        self.assertEqual(DailyPostCounter.objects.count(), 1)
        self.assertEqual(counter.date, timezone.now().date())
        self.assertEqual(counter.post_count, 0)

    @freeze_time("2025-04-03 11:00:00")
    def test_get_today_counter_returns_existing_entry(self):
        """今日の日付のカウンターが既に存在する場合、それが返されることをテスト"""
        # 事前に作成
        created_counter = DailyPostCounter.objects.create(date=timezone.now().date(), post_count=2)
        self.assertEqual(DailyPostCounter.objects.count(), 1)

        # get_today_counter を呼び出し
        returned_counter = DailyPostCounter.get_today_counter()
        self.assertEqual(DailyPostCounter.objects.count(), 1)
        self.assertEqual(returned_counter.id, created_counter.id)
        self.assertEqual(returned_counter.post_count, 2)

    @freeze_time("2025-04-04 12:00:00")
    def test_increment_count(self):
        """increment_count メソッドが正しくカウントを増やすことをテスト"""
        counter = DailyPostCounter.get_today_counter()
        self.assertEqual(counter.post_count, 0)
        counter.increment_count()
        # DBから再取得して確認
        updated_counter = DailyPostCounter.objects.get(pk=counter.pk)
        self.assertEqual(updated_counter.post_count, 1)
        counter.increment_count()
        updated_counter = DailyPostCounter.objects.get(pk=counter.pk)
        self.assertEqual(updated_counter.post_count, 2)

    @freeze_time("2025-04-05 13:00:00")
    def test_is_limit_reached(self):
        """is_limit_reached プロパティが上限に達したかどうかを正しく判定することをテスト"""
        settings.MAX_DAILY_POSTS_PER_USER = 3 # 上限を3に設定
        counter = DailyPostCounter.get_today_counter()

        self.assertFalse(counter.is_limit_reached)
        counter.increment_count() # count = 1
        self.assertFalse(counter.is_limit_reached)
        counter.increment_count() # count = 2
        self.assertFalse(counter.is_limit_reached)
        counter.increment_count() # count = 3
        # DBから再取得してプロパティを評価
        updated_counter = DailyPostCounter.objects.get(pk=counter.pk)
        self.assertTrue(updated_counter.is_limit_reached)

    @freeze_time("2025-04-06 14:00:00")
    def test_remaining_posts(self):
        """remaining_posts プロパティが残りの投稿数を正しく計算することをテスト"""
        settings.MAX_DAILY_POSTS_PER_USER = 4 # 上限を4に設定
        counter = DailyPostCounter.get_today_counter()

        self.assertEqual(counter.remaining_posts, 4)
        counter.increment_count() # count = 1
        self.assertEqual(counter.remaining_posts, 3)
        counter.increment_count() # count = 2
        self.assertEqual(counter.remaining_posts, 2)
        counter.increment_count() # count = 3
        self.assertEqual(counter.remaining_posts, 1)
        counter.increment_count() # count = 4
        self.assertEqual(counter.remaining_posts, 0)
        # 上限を超えても 0 のまま
        counter.increment_count() # count = 5 (DB上は増えるが...)
        # DBから再取得してプロパティを評価
        updated_counter = DailyPostCounter.objects.get(pk=counter.pk)
        self.assertEqual(updated_counter.remaining_posts, 0)

    @freeze_time("2025-04-07")
    def test_get_today_counter_on_different_days(self):
        """異なる日付で get_today_counter を呼び出すと、別々のエントリが作成されることをテスト"""
        counter_day1 = DailyPostCounter.get_today_counter()
        self.assertEqual(DailyPostCounter.objects.count(), 1)

        # 日付を進める
        with freeze_time("2025-04-08"):
            counter_day2 = DailyPostCounter.get_today_counter()
            self.assertEqual(DailyPostCounter.objects.count(), 2)
            self.assertNotEqual(counter_day1.date, counter_day2.date)
            self.assertEqual(counter_day2.date, timezone.now().date())

class SystemSettingModelTest(TestCase):

    def test_set_value_creates_new_entry(self):
        """set_value が新しいキーでエントリを作成することをテスト"""
        self.assertEqual(SystemSetting.objects.count(), 0)
        setting = SystemSetting.set_value("test_key", "test_value", "Test Description")
        self.assertEqual(SystemSetting.objects.count(), 1)
        self.assertEqual(setting.key, "test_key")
        self.assertEqual(setting.value, "test_value")
        self.assertEqual(setting.description, "Test Description")

    def test_set_value_updates_existing_entry(self):
        """set_value が既存のキーの値を更新することをテスト"""
        # 事前に作成
        SystemSetting.objects.create(key="existing_key", value="initial_value")
        self.assertEqual(SystemSetting.objects.count(), 1)

        # 値を更新
        setting = SystemSetting.set_value("existing_key", "updated_value")
        self.assertEqual(SystemSetting.objects.count(), 1) # エントリ数は変わらない
        self.assertEqual(setting.key, "existing_key")
        self.assertEqual(setting.value, "updated_value")
        # description を指定しない場合、元の値が保持されるか (update_or_create の挙動)
        # → defaults で指定しないフィールドは更新されない
        updated_setting = SystemSetting.objects.get(key="existing_key")
        self.assertIsNone(updated_setting.description) # 元が None なら None のまま

        # description も更新
        setting_with_desc = SystemSetting.set_value("existing_key", "updated_value_2", "New Desc")
        self.assertEqual(setting_with_desc.value, "updated_value_2")
        self.assertEqual(setting_with_desc.description, "New Desc")

    def test_get_value_returns_correct_value(self):
        """get_value が正しい値を返すことをテスト"""
        SystemSetting.objects.create(key="get_key", value="correct_value")
        value = SystemSetting.get_value("get_key")
        self.assertEqual(value, "correct_value")

    def test_get_value_returns_default_when_key_not_found(self):
        """get_value がキーが存在しない場合にデフォルト値を返すことをテスト"""
        # デフォルト値指定なし (Noneが返るはず)
        value_none = SystemSetting.get_value("non_existent_key")
        self.assertIsNone(value_none)

        # デフォルト値指定あり
        value_default = SystemSetting.get_value("non_existent_key_2", "default_val")
        self.assertEqual(value_default, "default_val")

    def test_get_value_returns_default_even_if_default_is_none(self):
        """get_value がキーが存在せず、デフォルト値がNoneの場合にNoneを返すことをテスト"""
        value = SystemSetting.get_value("another_non_existent_key", default=None)
        self.assertIsNone(value)