"""
X投稿スケジューラーアプリケーションの設定
"""

from django.apps import AppConfig


class XSchedulerConfig(AppConfig):
    """X投稿スケジューラーアプリケーションの設定クラス"""

    default_auto_field = "django.db.models.BigAutoField"
    name = "x_scheduler"
    verbose_name = "X投稿スケジューラー"
