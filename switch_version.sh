#!/bin/bash

# バージョン切り替えスクリプト
SCRIPT_DIR=$(dirname "$0")
cd "$SCRIPT_DIR"

# 現在の設定を確認
CURRENT_VERSION="不明"
if [ -h "auto_tweet.sh" ] && [ "$(readlink auto_tweet.sh)" == "launchd_version/auto_tweet.sh" ]; then
  CURRENT_VERSION="launchd"
elif [ -h "auto_tweet.sh" ] && [ "$(readlink auto_tweet.sh)" == "pmset_version/auto_tweet.sh" ]; then
  CURRENT_VERSION="pmset"
fi

# バージョン表示
show_version() {
  echo "現在のバージョン: $CURRENT_VERSION"
  echo "利用可能なバージョン: pmset, launchd"
}

# ヘルプ表示
show_help() {
  echo "使用方法: $0 [pmset|launchd|status]"
  echo ""
  echo "オプション:"
  echo "  pmset    - pmsetベースのシステムに切り替え（スリープからの自動起動対応）"
  echo "  launchd  - launchdベースのシステムに切り替え（起動中のみ実行）"
  echo "  status   - 現在のバージョンを表示"
  echo "  help     - このヘルプを表示"
  echo ""
  show_version
}

# launchdのロード状態を確認
check_launchd_status() {
  if launchctl list | grep -q "com.user.auto_tweet"; then
    return 0  # ロード済み
  else
    return 1  # ロードされていない
  fi
}

# 引数チェック
if [ $# -eq 0 ]; then
  show_help
  exit 0
fi

case "$1" in
  "pmset")
    # 既存のスクリプトがシンボリックリンクなら削除
    if [ -h "auto_tweet.sh" ]; then
      rm auto_tweet.sh
    fi
    if [ -h "process_tweets.sh" ]; then
      rm process_tweets.sh
    fi
    
    # データファイルのシンボリックリンクを削除
    if [ -h "auto_tweet_last_run.txt" ]; then
      rm auto_tweet_last_run.txt
    elif [ -f "auto_tweet_last_run.txt" ]; then
      # ファイルが存在する場合はバックアップしてから移動
      cp auto_tweet_last_run.txt pmset_version/
      rm auto_tweet_last_run.txt
    fi
    
    if [ -h "process_tweets_last_run.txt" ]; then
      rm process_tweets_last_run.txt
    elif [ -f "process_tweets_last_run.txt" ]; then
      cp process_tweets_last_run.txt pmset_version/
      rm process_tweets_last_run.txt
    fi
    
    # ログディレクトリのシンボリックリンクを削除
    if [ -h "logs" ]; then
      rm logs
    fi
    
    # launchdジョブがロードされていたらアンロード
    if check_launchd_status; then
      echo "launchdジョブをアンロード中..."
      launchctl unload ~/Library/LaunchAgents/com.user.auto_tweet.plist 2>/dev/null
      launchctl unload ~/Library/LaunchAgents/com.user.process_tweets.plist 2>/dev/null
    fi
    
    # pmsetバージョンのシンボリックリンクを作成
    ln -sf pmset_version/auto_tweet.sh auto_tweet.sh
    ln -sf pmset_version/process_tweets.sh process_tweets.sh
    ln -sf pmset_version/auto_tweet_last_run.txt auto_tweet_last_run.txt
    ln -sf pmset_version/process_tweets_last_run.txt process_tweets_last_run.txt
    ln -sf pmset_version/logs logs
    ln -sf pmset_version/wake_schedule.txt wake_schedule.txt
    ln -sf pmset_version/process_wake_schedule.txt process_wake_schedule.txt
    
    echo "pmsetバージョン（スリープからの自動起動対応）に切り替えました"
    echo "注意: このバージョンでは sudo pmset コマンドを使用します。パスワード入力が必要になる場合があります。"
    ;;
    
  "launchd")
    # 既存のスクリプトがシンボリックリンクなら削除
    if [ -h "auto_tweet.sh" ]; then
      rm auto_tweet.sh
    fi
    if [ -h "process_tweets.sh" ]; then
      rm process_tweets.sh
    fi
    
    # データファイルのシンボリックリンクを削除
    if [ -h "auto_tweet_last_run.txt" ]; then
      rm auto_tweet_last_run.txt
    elif [ -f "auto_tweet_last_run.txt" ]; then
      # ファイルが存在する場合はバックアップしてから移動
      cp auto_tweet_last_run.txt launchd_version/
      rm auto_tweet_last_run.txt
    fi
    
    if [ -h "process_tweets_last_run.txt" ]; then
      rm process_tweets_last_run.txt
    elif [ -f "process_tweets_last_run.txt" ]; then
      cp process_tweets_last_run.txt launchd_version/
      rm process_tweets_last_run.txt
    fi
    
    # ログディレクトリのシンボリックリンクを削除
    if [ -h "logs" ]; then
      rm logs
    fi
    
    # 既存のスケジュールをキャンセル
    sudo pmset schedule cancelall 2>/dev/null
    
    # launchdバージョンのシンボリックリンクを作成
    ln -sf launchd_version/auto_tweet.sh auto_tweet.sh
    ln -sf launchd_version/process_tweets.sh process_tweets.sh
    ln -sf launchd_version/auto_tweet_last_run.txt auto_tweet_last_run.txt
    ln -sf launchd_version/process_tweets_last_run.txt process_tweets_last_run.txt
    ln -sf launchd_version/logs logs
    
    # スケジュールファイルの削除
    if [ -f "wake_schedule.txt" ] || [ -h "wake_schedule.txt" ]; then
      rm wake_schedule.txt
    fi
    if [ -f "process_wake_schedule.txt" ] || [ -h "process_wake_schedule.txt" ]; then
      rm process_wake_schedule.txt
    fi
    
    # launchdジョブのロード
    echo "launchdジョブをロード中..."
    launchctl load ~/Library/LaunchAgents/launchd_version/com.user.auto_tweet.plist 2>/dev/null
    launchctl load ~/Library/LaunchAgents/launchd_version/com.user.process_tweets.plist 2>/dev/null
    
    echo "launchdバージョン（起動中のみ実行）に切り替えました"
    echo "注意: このバージョンはMacが起動している間のみ実行されます。スリープ中は実行されません。"
    ;;
    
  "status")
    show_version
    ;;
    
  "help"|*)
    show_help
    ;;
esac 