# Generated by Django 5.1.6 on 2025-03-03 07:51

import uuid

import django.core.validators
import django.db.models.deletion
import x_scheduler.models
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("x_scheduler", "0002_tweetschedule_image"),
    ]

    operations = [
        migrations.CreateModel(
            name="RecurringPattern",
            fields=[
                (
                    "id",
                    models.UUIDField(
                        default=uuid.uuid4,
                        editable=False,
                        primary_key=True,
                        serialize=False,
                    ),
                ),
                ("name", models.CharField(max_length=100, verbose_name="パターン名")),
                (
                    "frequency",
                    models.CharField(
                        choices=[
                            ("daily", "毎日"),
                            ("weekly", "毎週"),
                            ("monthly", "毎月"),
                        ],
                        max_length=10,
                        verbose_name="頻度",
                    ),
                ),
                ("time", models.TimeField(verbose_name="時刻")),
                ("is_active", models.BooleanField(default=True, verbose_name="有効")),
                (
                    "weekday",
                    models.IntegerField(
                        blank=True,
                        choices=[
                            (0, "月曜日"),
                            (1, "火曜日"),
                            (2, "水曜日"),
                            (3, "木曜日"),
                            (4, "金曜日"),
                            (5, "土曜日"),
                            (6, "日曜日"),
                        ],
                        help_text="毎週の場合に指定",
                        null=True,
                        verbose_name="曜日",
                    ),
                ),
                (
                    "day_of_month",
                    models.IntegerField(
                        blank=True,
                        help_text="毎月の場合に指定（1-31）",
                        null=True,
                        validators=[
                            django.core.validators.MinValueValidator(1),
                            django.core.validators.MaxValueValidator(31),
                        ],
                        verbose_name="日付",
                    ),
                ),
                (
                    "content_template",
                    models.TextField(
                        help_text="投稿内容のテンプレート。{date}は日付、{time}は時刻に置換されます。",
                        max_length=280,
                        verbose_name="投稿内容テンプレート",
                    ),
                ),
                (
                    "image",
                    models.ImageField(
                        blank=True,
                        null=True,
                        upload_to=x_scheduler.models.get_image_path,
                        verbose_name="画像",
                    ),
                ),
                (
                    "last_generation_time",
                    models.DateTimeField(
                        blank=True, null=True, verbose_name="最終生成日時"
                    ),
                ),
                (
                    "created_at",
                    models.DateTimeField(auto_now_add=True, verbose_name="作成日時"),
                ),
                (
                    "updated_at",
                    models.DateTimeField(auto_now=True, verbose_name="更新日時"),
                ),
            ],
            options={
                "verbose_name": "繰り返しパターン",
                "verbose_name_plural": "繰り返しパターン一覧",
                "ordering": ["-created_at"],
            },
        ),
        migrations.AddField(
            model_name="tweetschedule",
            name="recurring_pattern",
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name="tweet_schedules",
                to="x_scheduler.recurringpattern",
                verbose_name="繰り返しパターン",
            ),
        ),
    ]
