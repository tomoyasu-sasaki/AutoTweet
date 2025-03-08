from django.contrib import admin
from .models import TweetSchedule, DailyPostCounter, SystemSetting

@admin.register(TweetSchedule)
class TweetScheduleAdmin(admin.ModelAdmin):
    list_display = ('content_preview', 'scheduled_time', 'status', 'created_at')
    list_filter = ('status', 'scheduled_time')
    search_fields = ('content',)
    readonly_fields = ('created_at', 'updated_at')
    fieldsets = (
        ('投稿内容', {
            'fields': ('content', 'scheduled_time')
        }),
        ('ステータス', {
            'fields': ('status', 'error_message')
        }),
        ('メタデータ', {
            'fields': ('created_at', 'updated_at')
        }),
    )

    def content_preview(self, obj):
        """投稿内容のプレビュー（30文字まで表示）"""
        return obj.content[:30] + ('...' if len(obj.content) > 30 else '')
    content_preview.short_description = '投稿内容'

@admin.register(DailyPostCounter)
class DailyPostCounterAdmin(admin.ModelAdmin):
    list_display = ('date', 'post_count', 'max_daily_posts', 'remaining_posts', 'updated_at')
    list_filter = ('date',)
    readonly_fields = ('created_at', 'updated_at')
    fieldsets = (
        ('投稿カウント', {
            'fields': ('date', 'post_count', 'max_daily_posts')
        }),
        ('メタデータ', {
            'fields': ('created_at', 'updated_at')
        }),
    )
    
    def remaining_posts(self, obj):
        """残りの投稿可能数"""
        return obj.remaining_posts
    remaining_posts.short_description = '残り投稿可能数'

@admin.register(SystemSetting)
class SystemSettingAdmin(admin.ModelAdmin):
    list_display = ('key', 'value', 'description', 'updated_at')
    search_fields = ('key', 'value', 'description')
    readonly_fields = ('created_at', 'updated_at')
    fieldsets = (
        ('設定', {
            'fields': ('key', 'value', 'description')
        }),
        ('メタデータ', {
            'fields': ('created_at', 'updated_at')
        }),
    )
