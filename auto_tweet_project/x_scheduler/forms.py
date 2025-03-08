from django import forms
from .models import TweetSchedule
from django.utils import timezone
from datetime import timedelta

class TweetScheduleForm(forms.ModelForm):
    """投稿スケジュール作成・編集用フォーム"""
    
    # デフォルトで現在から1時間後を設定
    scheduled_time = forms.DateTimeField(
        label='予定時刻',
        widget=forms.DateTimeInput(
            attrs={'type': 'datetime-local'},
            format='%Y-%m-%dT%H:%M'
        ),
        initial=timezone.now() + timedelta(hours=1)
    )
    
    class Meta:
        model = TweetSchedule
        fields = ['content', 'image', 'scheduled_time']
        widgets = {
            'content': forms.Textarea(attrs={
                'rows': 4,
                'placeholder': 'ここに投稿内容を入力してください（280文字まで）',
                'class': 'form-control',
                'maxlength': 280
            }),
            'image': forms.FileInput(attrs={
                'class': 'form-control',
                'accept': 'image/*'
            }),
        }
    
    def clean_scheduled_time(self):
        """予定時刻のバリデーション"""
        scheduled_time = self.cleaned_data.get('scheduled_time')
        
        # 過去の時間ではないことを確認
        if scheduled_time and scheduled_time < timezone.now():
            raise forms.ValidationError('過去の時間は設定できません。')
        
        return scheduled_time
        
    def clean_image(self):
        """画像のバリデーション"""
        image = self.cleaned_data.get('image')
        if image:
            # 画像サイズが5MB以下であることを確認
            if image.size > 5 * 1024 * 1024:
                raise forms.ValidationError('画像サイズは5MB以下にしてください。')
                
            # 拡張子の確認
            allowed_extensions = ['jpg', 'jpeg', 'png', 'gif']
            ext = image.name.split('.')[-1].lower()
            if ext not in allowed_extensions:
                raise forms.ValidationError('対応している画像形式は、jpg、jpeg、png、gifのみです。')
                
        return image 