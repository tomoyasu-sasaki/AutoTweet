import tweepy
import logging
from django.conf import settings
from datetime import datetime
from django.utils import timezone
import os
import tempfile

# ロガーの設定
logger = logging.getLogger(__name__)

def get_tweepy_api():
    """認証済みTweepy APIクライアントを取得する"""
    try:
        auth = tweepy.OAuth1UserHandler(
            settings.X_API_KEY,
            settings.X_API_SECRET,
            settings.X_ACCESS_TOKEN,
            settings.X_ACCESS_TOKEN_SECRET
        )
        api = tweepy.API(auth)
        return api
    except Exception as e:
        logger.error(f"APIクライアント作成エラー: {str(e)}")
        return None

def get_tweepy_client():
    """認証済みTweepy Clientを取得する（v2 API用）"""
    try:
        client = tweepy.Client(
            consumer_key=settings.X_API_KEY,
            consumer_secret=settings.X_API_SECRET,
            access_token=settings.X_ACCESS_TOKEN,
            access_token_secret=settings.X_ACCESS_TOKEN_SECRET
        )
        return client
    except Exception as e:
        logger.error(f"APIクライアント作成エラー: {str(e)}")
        return None

def test_api_connection():
    """API接続のテストを実行する"""
    logger.info("API接続テストを実行します")
    
    try:
        # v1 APIの接続テスト
        api = get_tweepy_api()
        if not api:
            return {"success": False, "error": "APIクライアント(v1)の作成に失敗しました"}
        
        # API v1でアカウント情報を取得してテスト
        user = api.verify_credentials()
        
        # v2 APIの接続テスト
        client = get_tweepy_client()
        if not client:
            return {"success": False, "error": "APIクライアント(v2)の作成に失敗しました"}
        
        # API v2でユーザー情報を取得
        me = client.get_me()
        
        logger.info(f"API接続テスト成功: ユーザー名 @{user.screen_name}, ID: {user.id}")
        return {"success": True, "error": ""}
        
    except tweepy.TweepyException as e:
        error_message = f"API接続テストエラー (Tweepy): {str(e)}"
        logger.error(error_message)
        return {"success": False, "error": error_message}
    except Exception as e:
        error_message = f"API接続テストエラー: {str(e)}"
        logger.error(error_message)
        return {"success": False, "error": error_message}

def post_tweet(content, image_path=None):
    """指定された内容と画像でツイートを投稿する"""
    client = get_tweepy_client()
    if not client:
        logger.error("ツイートの投稿に失敗: APIクライアントが作成できませんでした。")
        return {"success": False, "error": "APIクライアントが作成できませんでした。"}
    
    media_id = None
    try:
        # APIキーとシークレットをログに出力（デバッグ目的、本番環境では削除すること）
        logger.info(f"使用するAPIキー: {settings.X_API_KEY[:5]}...")
        logger.info(f"使用するアクセストークン: {settings.X_ACCESS_TOKEN[:5]}...")
        
        # 画像があるかどうかで処理を分ける
        if image_path:
            logger.info(f"画像を含むツイートを投稿します: {image_path}")
            
            # v1.1 APIを使用して画像をアップロード
            api = get_tweepy_api()
            if not api:
                return {"success": False, "error": "APIクライアントv1が作成できませんでした。"}
            
            try:
                # 画像をアップロード
                media = api.media_upload(filename=image_path)
                media_id = media.media_id
                logger.info(f"画像のアップロードに成功しました: media_id={media_id}")
            except tweepy.TweepyException as e:
                if "Rate limit exceeded" in str(e):
                    logger.error(f"画像アップロードでレートリミットに達しました: {str(e)}")
                    return {"success": False, "error": "レートリミットに達しました", "rate_limited": True}
                raise
            
            try:
                # v2 APIで画像を含むツイートを投稿
                response = client.create_tweet(text=content, media_ids=[media_id])
                logger.info(f"画像付きツイート投稿成功: {response.data}")
            except Exception as e:
                logger.error(f"画像付きツイート投稿に失敗しました: {str(e)}")
                raise
        else:
            # 画像なしのツイート
            try:
                response = client.create_tweet(text=content)
                logger.info(f"テキストのみのツイート投稿成功: {response.data}")
            except tweepy.TweepyException as e:
                if "Rate limit exceeded" in str(e):
                    logger.error(f"ツイート投稿でレートリミットに達しました: {str(e)}")
                    return {"success": False, "error": "レートリミットに達しました", "rate_limited": True}
                raise
            
        return {"success": True, "error": ""}
    except Exception as e:
        error_message = f"ツイート投稿エラー: {str(e)}"
        logger.error(error_message)
        return {"success": False, "error": error_message}

def process_scheduled_tweets():
    """待機中の予定時刻を過ぎたツイートを処理する"""
    from .models import TweetSchedule  # 循環インポートを避けるためにここでインポート
    
    # 予定時刻を過ぎて待機中の投稿を取得
    now = timezone.now()
    logger.info(f"ツイート処理開始: 現在時刻 {now}")
    
    pending_tweets = TweetSchedule.objects.filter(
        status='pending',
        scheduled_time__lte=now
    )
    
    logger.info(f"処理対象のツイート数: {pending_tweets.count()}")
    
    for tweet in pending_tweets:
        logger.info(f"ツイート処理中: ID={tweet.id}, 内容={tweet.content[:20]}..., 予定時刻={tweet.scheduled_time}")
        
        # 画像の処理
        image_path = None
        temp_file = None
        
        try:
            if tweet.image:
                # 一時ファイルを作成
                logger.info(f"画像ファイルが添付されています: {tweet.image.path}")
                _, temp_file = tempfile.mkstemp(suffix=os.path.splitext(tweet.image.name)[1])
                
                # 画像を一時ファイルにコピー
                with open(temp_file, 'wb') as dest, tweet.image.open('rb') as src:
                    dest.write(src.read())
                
                image_path = temp_file
                logger.info(f"一時ファイルを作成しました: {image_path}")
            
            # ツイート投稿
            post_result = post_tweet(tweet.content, image_path)
            
            if post_result["success"]:
                tweet.status = 'posted'
                tweet.save()
                logger.info(f"スケジュールされたツイートを投稿しました。ID: {tweet.id}")
            else:
                tweet.status = 'failed'
                tweet.error_message = post_result["error"]
                tweet.save()
                logger.error(f"スケジュールされたツイートの投稿に失敗しました。ID: {tweet.id}, エラー: {post_result['error']}")
                
        except Exception as e:
            logger.error(f"ツイート処理中にエラーが発生しました: {str(e)}")
            tweet.status = 'failed'
            tweet.error_message = str(e)
            tweet.save()
        finally:
            # 一時ファイルを削除
            if temp_file and os.path.exists(temp_file):
                os.remove(temp_file)
                logger.info(f"一時ファイルを削除しました: {temp_file}")
    
    return pending_tweets.count() 