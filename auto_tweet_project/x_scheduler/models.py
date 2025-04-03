from django.db import models
from django.utils import timezone
import uuid
import os
import logging

# ロガーの設定
logger = logging.getLogger(__name__)

def get_image_path(instance, filename):
    """画像ファイルの保存パスを生成"""
    ext = filename.split('.')[-1]
    new_filename = f"{uuid.uuid4()}.{ext}"
    path = os.path.join('tweet_images', new_filename)
    logger.debug(f"画像保存パスを生成: {path}")
    return path

class TweetSchedule(models.Model):
    """予約投稿のスケジュールを管理するモデル"""
    
    STATUS_CHOICES = (
        ('pending', '待機中'),
        ('posted', '投稿済み'),
        ('failed', '失敗'),
    )
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    content = models.TextField('投稿内容', max_length=280)  # Xの文字制限
    image = models.ImageField('画像', upload_to=get_image_path, blank=True, null=True)
    scheduled_time = models.DateTimeField('予定時刻')
    status = models.CharField('ステータス', max_length=10, choices=STATUS_CHOICES, default='pending')
    error_message = models.TextField('エラーメッセージ', blank=True, null=True)
    created_at = models.DateTimeField('作成日時', auto_now_add=True)
    updated_at = models.DateTimeField('更新日時', auto_now=True)
    
    class Meta:
        verbose_name = 'ツイート予約'
        verbose_name_plural = 'ツイート予約一覧'
        ordering = ['-scheduled_time']
    
    def __str__(self):
        return f"{self.content[:30]}... ({self.get_status_display()}) - {self.scheduled_time.strftime('%Y-%m-%d %H:%M')}"
    
    @property
    def is_due(self):
        """投稿時刻が現在時刻を過ぎているかどうかを確認"""
        return timezone.now() >= self.scheduled_time
    
    @property
    def is_pending(self):
        """投稿待ちかどうかを確認"""
        return self.status == 'pending'
        
    @property
    def has_image(self):
        """画像が添付されているかどうかを確認"""
        return bool(self.image)
        
    def save(self, *args, **kwargs):
        """保存時の処理をオーバーライド"""
        if self.image:
            logger.debug(f"画像付きでモデルを保存します: {self.image.name}")
        super().save(*args, **kwargs)


class DailyPostCounter(models.Model):
    """日次の投稿カウントを管理するモデル"""
    
    date = models.DateField('日付', unique=True)
    post_count = models.IntegerField('投稿回数', default=0)
    max_daily_posts = models.IntegerField('1日の最大投稿数', default=16)
    created_at = models.DateTimeField('作成日時', auto_now_add=True)
    updated_at = models.DateTimeField('更新日時', auto_now=True)
    
    class Meta:
        verbose_name = '日次投稿カウンター'
        verbose_name_plural = '日次投稿カウンター'
        ordering = ['-date']
    
    def __str__(self):
        return f"{self.date.strftime('%Y-%m-%d')}: {self.post_count}/{self.max_daily_posts}"
    
    @classmethod
    def get_today_counter(cls):
        """本日のカウンターを取得または作成"""
        today = timezone.now().date()
        counter, created = cls.objects.get_or_create(
            date=today,
            defaults={'post_count': 0, 'max_daily_posts': 16}
        )
        return counter
    
    @classmethod
    def increment_count(cls):
        """本日の投稿カウントを1増やす"""
        counter = cls.get_today_counter()
        counter.post_count += 1
        counter.save()
        return counter
    
    @classmethod
    def get_or_create_today(cls):
        """get_today_counterの別名（互換性のため）"""
        return cls.get_today_counter()
    
    @property
    def remaining_posts(self):
        """残りの投稿可能数を返す"""
        return max(0, self.max_daily_posts - self.post_count)
    
    @property
    def is_limit_reached(self):
        """投稿上限に達したかどうかを返す"""
        return self.post_count >= self.max_daily_posts
    
    @property
    def limit_reached(self):
        """is_limit_reachedの別名（互換性のため）"""
        return self.is_limit_reached


class SystemSetting(models.Model):
    """システム設定を管理するモデル"""
    
    key = models.CharField('キー', max_length=100, unique=True)
    value = models.TextField('値')
    description = models.TextField('説明', blank=True, null=True)
    created_at = models.DateTimeField('作成日時', auto_now_add=True)
    updated_at = models.DateTimeField('更新日時', auto_now=True)
    
    class Meta:
        verbose_name = 'システム設定'
        verbose_name_plural = 'システム設定一覧'
        ordering = ['key']
    
    def __str__(self):
        return f"{self.key}: {self.value}"
    
    @classmethod
    def get_value(cls, key, default=None):
        """指定したキーの値を取得"""
        try:
            return cls.objects.get(key=key).value
        except cls.DoesNotExist:
            return default
    
    @classmethod
    def set_value(cls, key, value, description=None):
        """指定したキーの値を設定"""
        obj, created = cls.objects.update_or_create(
            key=key,
            defaults={'value': value, 'description': description}
        )
        return obj
    
    @classmethod
    def is_api_test_done_today(cls):
        """本日のAPI接続テストが完了しているかを確認"""
        today = timezone.now().date().isoformat()
        last_test_date = cls.get_value('api_test_last_date')
        return last_test_date == today
    
    @classmethod
    def mark_api_test_done(cls, peak=False):
        """API接続テストを実行済みとしてマーク"""
        today = timezone.now().date().isoformat()
        # 現在の時間帯も記録（朝/昼/夜）
        hour = timezone.now().hour
        time_of_day = "morning" if 5 <= hour < 12 else "afternoon" if 12 <= hour < 18 else "evening"
        cls.set_value('api_test_last_date', today)
        cls.set_value('api_test_last_time_of_day', time_of_day)
        logger.info(f"API接続テスト実行済みとしてマーク: {today} ({time_of_day})")
        return True
    
    @classmethod
    def is_peak_hour_tested_today(cls):
        """本日のピーク時間帯（朝/昼/夜）ですでにテスト済みかどうかを確認"""
        if not cls.is_api_test_done_today():
            return False
            
        # 現在の時間帯を判定
        hour = timezone.now().hour
        current_time_of_day = "morning" if 5 <= hour < 12 else "afternoon" if 12 <= hour < 18 else "evening"
        
        # 最後にテストした時間帯を取得
        last_time_of_day = cls.get_value('api_test_last_time_of_day', '')
        
        # 同じ時間帯ですでにテスト済みかどうか
        return current_time_of_day == last_time_of_day
    
    @classmethod
    def get_last_image_index(cls):
        """最後に使用した画像のインデックスを取得"""
        return int(cls.get_value('last_image_index', '84'))
    
    @classmethod
    def update_last_image_index(cls, index):
        """最後に使用した画像のインデックスを更新"""
        return cls.set_value(
            'last_image_index', 
            str(index), 
            '最後に使用した画像のインデックス'
        )
        
    @classmethod
    def get_next_image_index(cls, total_images):
        """次に使用する画像のインデックスを取得（ローテーション）"""
        last_index = cls.get_last_image_index()
        next_index = (last_index + 1) % total_images
        cls.update_last_image_index(next_index)
        return next_index
