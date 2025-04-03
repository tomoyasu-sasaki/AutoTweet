import os
from django.conf import settings
from django.shortcuts import get_object_or_404, render, redirect
from django.contrib.auth.decorators import login_required
from django.contrib import messages
from django.urls import reverse
from django.http import HttpResponse, HttpResponseRedirect
import logging
import tweepy

from .models import TweetSchedule  # 相対インポートに変更

# from .models import TweetSchedule, SystemSetting # 現在未使用
from .forms import TweetScheduleForm
# from .utils import get_tweepy_api, get_tweepy_client, post_tweet # 未使用のため削除

# ロガーの設定
logger = logging.getLogger(__name__)


def schedule_list(request):
    """投稿スケジュール一覧ページ"""
    schedules = TweetSchedule.objects.all()
    return render(
        request,
        "x_scheduler/schedule_list.html",
        {
            "schedules": schedules,
        },
    )


def schedule_create(request):
    """投稿スケジュール作成ページ"""
    if request.method == "POST":
        logger.debug(f"POSTデータ: {request.POST}")
        logger.debug(f"FILESデータ: {request.FILES}")

        form = TweetScheduleForm(request.POST, request.FILES)
        if form.is_valid():
            logger.debug("フォームが有効です")
            tweet = form.save(commit=False)

            if "image" in request.FILES:
                logger.debug(f"画像ファイル名: {request.FILES['image'].name}")
                logger.debug(f"画像サイズ: {request.FILES['image'].size} バイト")

                # 保存先ディレクトリの確認
                media_root = settings.MEDIA_ROOT
                tweet_images_dir = os.path.join(media_root, "tweet_images")

                logger.debug(f"MEDIA_ROOT: {media_root}")
                logger.debug(f"画像保存先ディレクトリ: {tweet_images_dir}")

                if not os.path.exists(tweet_images_dir):
                    logger.debug(
                        f"ディレクトリが存在しないため作成します: {tweet_images_dir}"
                    )
                    os.makedirs(tweet_images_dir, exist_ok=True)

            # 保存
            tweet.save()

            if tweet.image:
                logger.debug(f"保存された画像パス: {tweet.image.path}")
                logger.debug(f"保存された画像URL: {tweet.image.url}")

            messages.success(request, "投稿スケジュールが作成されました。")
            return redirect("x_scheduler:schedule_list")
        else:
            logger.debug(f"フォームエラー: {form.errors}")
    else:
        form = TweetScheduleForm()

    return render(
        request,
        "x_scheduler/schedule_form.html",
        {
            "form": form,
            "title": "新規投稿スケジュール作成",
        },
    )


def schedule_edit(request, pk):
    """投稿スケジュール編集ページ"""
    tweet = get_object_or_404(TweetSchedule, pk=pk)

    if request.method == "POST":
        logger.debug(f"編集POSTデータ: {request.POST}")
        logger.debug(f"編集FILESデータ: {request.FILES}")

        form = TweetScheduleForm(request.POST, request.FILES, instance=tweet)
        if form.is_valid():
            logger.debug("編集フォームが有効です")
            updated_tweet = form.save(commit=False)

            if "image" in request.FILES:
                logger.debug(f"新しい画像ファイル名: {request.FILES['image'].name}")
                logger.debug(f"新しい画像サイズ: {request.FILES['image'].size} バイト")

                # 既存の画像がある場合は削除
                if tweet.image:
                    old_image_path = tweet.image.path
                    if os.path.exists(old_image_path):
                        logger.debug(f"既存の画像を削除します: {old_image_path}")
                        os.remove(old_image_path)

            # 保存
            updated_tweet.save()

            if updated_tweet.image:
                logger.debug(f"更新された画像パス: {updated_tweet.image.path}")
                logger.debug(f"更新された画像URL: {updated_tweet.image.url}")

            messages.success(request, "投稿スケジュールが更新されました。")
            return redirect("x_scheduler:schedule_list")
        else:
            logger.debug(f"編集フォームエラー: {form.errors}")
    else:
        form = TweetScheduleForm(instance=tweet)

    return render(
        request,
        "x_scheduler/schedule_form.html",
        {
            "form": form,
            "tweet": tweet,
            "title": "投稿スケジュール編集",
        },
    )


def schedule_delete(request, pk):
    """投稿スケジュール削除"""
    tweet = get_object_or_404(TweetSchedule, pk=pk)

    if request.method == "POST":
        # 画像があれば削除
        if tweet.image:
            image_path = tweet.image.path
            if os.path.exists(image_path):
                logger.debug(f"削除時に画像も削除します: {image_path}")
                os.remove(image_path)

        tweet.delete()
        messages.success(request, "投稿スケジュールが削除されました。")
        return redirect("x_scheduler:schedule_list")

    return render(
        request,
        "x_scheduler/schedule_confirm_delete.html",
        {
            "tweet": tweet,
        },
    )


def x_auth_callback(request):
    """X API OAuth認証コールバック"""
    oauth_verifier = request.GET.get("oauth_verifier")
    oauth_token = request.GET.get("oauth_token")

    if not oauth_verifier or not oauth_token:
        messages.error(request, "認証情報が不足しています。")
        return redirect("x_scheduler:schedule_list")

    try:
        # この部分は通常はセッションから取得した認証情報を使用します
        # ローカルでの使用なので簡易的に実装しています
        auth = tweepy.OAuth1UserHandler(settings.X_API_KEY, settings.X_API_SECRET)
        auth.request_token = {"oauth_token": oauth_token, "oauth_token_secret": ""}

        # アクセストークンを取得
        auth.get_access_token(oauth_verifier)

        # 成功メッセージを表示
        messages.success(request, "X APIの認証に成功しました。")
    except Exception as e:
        logger.error(f"X API認証エラー: {str(e)}")
        messages.error(request, f"認証エラー: {str(e)}")

    return redirect("x_scheduler:schedule_list")
