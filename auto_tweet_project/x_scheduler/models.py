import logging
import uuid
from pathlib import Path

from django.conf import settings
from django.db import models
from django.utils import timezone
from django.core.files import File
import re

# ロガーの設定
logger = logging.getLogger(__name__)


def get_image_path(instance, filename):
    """画像ファイルの保存パスを生成 (pathlibを使用)"""
    file_path = Path(filename)
    ext = file_path.suffix  # 拡張子を取得 (.png など)
    new_filename = f"{uuid.uuid4()}{ext}"
    # settings.MEDIA_ROOT が Path オブジェクトであることを想定
    path = settings.MEDIA_ROOT / "tweet_images" / new_filename
    logger.debug(f"画像保存パスを生成: {path}")
    # ImageField の upload_to は文字列を返す必要がある場合があるため、str() で変換
    return str(path.relative_to(settings.MEDIA_ROOT))  # MEDIA_ROOT からの相対パスを返す


class TweetSchedule(models.Model):
    """予約投稿のスケジュールを管理するモデル"""

    STATUS_CHOICES = (
        ("pending", "待機中"),
        ("posted", "投稿済み"),
        ("failed", "失敗"),
    )

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    content = models.TextField("投稿内容", max_length=280)  # Xの文字制限
    image = models.ImageField("画像", upload_to=get_image_path, blank=True, null=True)
    scheduled_time = models.DateTimeField("予定時刻")
    status = models.CharField(
        "ステータス", max_length=10, choices=STATUS_CHOICES, default="pending"
    )
    error_message = models.TextField("エラーメッセージ", blank=True, null=True)
    created_at = models.DateTimeField("作成日時", auto_now_add=True)
    updated_at = models.DateTimeField("更新日時", auto_now=True)

    class Meta:
        verbose_name = "ツイート予約"
        verbose_name_plural = "ツイート予約一覧"
        ordering = ["-scheduled_time"]

    def __str__(self):
        return f"{self.content[:30]}... ({self.get_status_display()}) - {self.scheduled_time.strftime('%Y-%m-%d %H:%M')}"

    @property
    def is_due(self):
        """投稿時刻が現在時刻を過ぎているかどうかを確認"""
        return timezone.now() >= self.scheduled_time

    @property
    def is_pending(self):
        """投稿待ちかどうかを確認"""
        return self.status == "pending"

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

    date = models.DateField("日付", unique=True)
    post_count = models.IntegerField("投稿回数", default=0)
    created_at = models.DateTimeField("作成日時", auto_now_add=True)
    updated_at = models.DateTimeField("更新日時", auto_now=True)

    class Meta:
        verbose_name = "日次投稿カウンター"
        verbose_name_plural = "日次投稿カウンター"
        ordering = ["-date"]

    def __str__(self):
        return f"{self.date.strftime('%Y-%m-%d')}: {self.post_count}/{settings.MAX_DAILY_POSTS_PER_USER}"

    @classmethod
    def get_today_counter(cls):
        """本日のカウンターを取得または作成"""
        today = timezone.localdate()
        counter, created = cls.objects.get_or_create(
            date=today, defaults={"post_count": 0}
        )
        return counter

    def increment_count(self):
        """このインスタンスの投稿カウントを1増やす"""
        self.post_count += 1
        self.save(update_fields=['post_count', 'updated_at'])

    @property
    def remaining_posts(self):
        """残りの投稿可能数を返す"""
        return max(0, settings.MAX_DAILY_POSTS_PER_USER - self.post_count)

    @property
    def is_limit_reached(self):
        """投稿上限に達したかどうかを返す"""
        return self.post_count >= settings.MAX_DAILY_POSTS_PER_USER


class SystemSetting(models.Model):
    """システム設定を管理するモデル"""

    key = models.CharField("キー", max_length=100, unique=True)
    value = models.TextField("値")
    description = models.TextField("説明", blank=True, null=True)
    created_at = models.DateTimeField("作成日時", auto_now_add=True)
    updated_at = models.DateTimeField("更新日時", auto_now=True)

    class Meta:
        verbose_name = "システム設定"
        verbose_name_plural = "システム設定一覧"
        ordering = ["key"]

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
            key=key, defaults={"value": value, "description": description}
        )
        return obj
