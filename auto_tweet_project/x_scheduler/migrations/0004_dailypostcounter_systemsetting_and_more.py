# Generated by Django 5.1.6 on 2025-03-06 01:51

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('x_scheduler', '0003_recurringpattern_tweetschedule_recurring_pattern'),
    ]

    operations = [
        migrations.CreateModel(
            name='DailyPostCounter',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('date', models.DateField(unique=True, verbose_name='日付')),
                ('post_count', models.IntegerField(default=0, verbose_name='投稿回数')),
                ('max_daily_posts', models.IntegerField(default=15, verbose_name='1日の最大投稿数')),
                ('created_at', models.DateTimeField(auto_now_add=True, verbose_name='作成日時')),
                ('updated_at', models.DateTimeField(auto_now=True, verbose_name='更新日時')),
            ],
            options={
                'verbose_name': '日次投稿カウンター',
                'verbose_name_plural': '日次投稿カウンター',
                'ordering': ['-date'],
            },
        ),
        migrations.CreateModel(
            name='SystemSetting',
            fields=[
                ('id', models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name='ID')),
                ('key', models.CharField(max_length=100, unique=True, verbose_name='キー')),
                ('value', models.TextField(verbose_name='値')),
                ('description', models.TextField(blank=True, null=True, verbose_name='説明')),
                ('created_at', models.DateTimeField(auto_now_add=True, verbose_name='作成日時')),
                ('updated_at', models.DateTimeField(auto_now=True, verbose_name='更新日時')),
            ],
            options={
                'verbose_name': 'システム設定',
                'verbose_name_plural': 'システム設定一覧',
                'ordering': ['key'],
            },
        ),
        migrations.RemoveField(
            model_name='tweetschedule',
            name='recurring_pattern',
        ),
        migrations.DeleteModel(
            name='RecurringPattern',
        ),
    ]
