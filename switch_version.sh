#!/bin/bash

# 定期実行モード切り替えスクリプト (macOS用)

# --- 設定 --- 
PROJECT_DIR=$(cd "$(dirname "$0")" && pwd) # このスクリプトがあるディレクトリをプロジェクトルートとする
LAUNCHD_AUTO_TWEET_PLIST="${HOME}/Library/LaunchAgents/com.user.auto_tweet.plist"
LAUNCHD_PROCESS_TWEETS_PLIST="${HOME}/Library/LaunchAgents/com.user.process_tweets.plist"
LAUNCHD_AUTO_TWEET_LABEL="com.user.auto_tweet"       # plist内のLabelキーと一致させる
LAUNCHD_PROCESS_TWEETS_LABEL="com.user.process_tweets" # plist内のLabelキーと一致させる
CRON_PMSET_AUTO_TWEET_PATTERN="scripts/pmset_version/auto_tweet.sh"
CRON_PMSET_PROCESS_TWEETS_PATTERN="scripts/pmset_version/process_tweets.sh"

# --- 関数 --- 

# launchdジョブがロードされているか確認 (0: ロード済み, 1: 未ロード, 2: エラー)
is_launchd_job_loaded() {
    local label="$1"
    if launchctl list "$label" > /dev/null 2>&1; then
        return 0 # ロード済み
    elif launchctl list | grep -q "$label"; then
         # list <label> でエラーでも list 全体には含まれる場合がある (古い形式?)
         # この場合もロード済みとみなす
         return 0
    else
        # list <label> が失敗し、list全体にもなければ未ロード
        # $? を確認して launchctl 自体のエラーか判断
        local exit_code=$?
        if [[ $exit_code -ne 0 ]]; then
             # launchctl list <label> がエラー終了した場合 (ジョブが存在しないなど)
             return 1 # 未ロード
        else
             # launchctl list 自体が成功したがラベルが見つからない場合
             # (このケースは通常発生しないはずだが念のため)
             return 1 # 未ロード
        fi
         # launchctl list コマンド自体が失敗した場合
         # echo "Error: launchctl list failed." >&2
         # return 2 # launchctlエラー
    fi
}

# crontabにpmsetバージョン用の設定があるか確認 (0: あり, 1: なし, 2: エラー)
is_cron_pmset_configured() {
    if ! command -v crontab > /dev/null; then
        # echo "Error: crontab command not found." >&2
        return 2 # crontab コマンドなし
    fi
    # crontab -l がエラーになる場合 (crontab未設定など) も考慮
    if crontab -l 2>/dev/null | grep -q -E "(${CRON_PMSET_AUTO_TWEET_PATTERN}|${CRON_PMSET_PROCESS_TWEETS_PATTERN})"; then
        return 0 # 設定あり
    else
        # grep で見つからなかった場合、または crontab -l が失敗した場合
        local exit_code=$?
        if [[ $exit_code -eq 1 ]]; then
             return 1 # 設定なし (grep が何も見つけなかった)
        else
             # crontab -l 自体のエラー or grep のエラー
             # echo "Info: No crontab for user or error checking crontab." >&2
             return 1 # crontab未設定または確認エラーの場合も「設定なし」とみなす
        fi
    fi
}

# 現在のステータスを表示
show_status() {
    echo "--- 現在の定期実行モード状況 ---"
    local launchd_auto_status="不明"
    local launchd_proc_status="不明"
    local cron_status="不明"
    local current_mode="不明"

    is_launchd_job_loaded "$LAUNCHD_AUTO_TWEET_LABEL"
    case $? in
        0) launchd_auto_status="✅ 有効 (ロード済)";; 
        1) launchd_auto_status="❌ 無効 (未ロード)";; 
        *) launchd_auto_status="⚠️ 確認エラー";;
    esac
    is_launchd_job_loaded "$LAUNCHD_PROCESS_TWEETS_LABEL"
     case $? in
        0) launchd_proc_status="✅ 有効 (ロード済)";; 
        1) launchd_proc_status="❌ 無効 (未ロード)";; 
        *) launchd_proc_status="⚠️ 確認エラー";;
    esac

    is_cron_pmset_configured
    case $? in
        0) cron_status="✅ 有効 (設定有)";; 
        1) cron_status="❌ 無効 (設定無)";; 
        *) cron_status="⚠️ 確認エラー";;
    esac

    echo "[Launchd モード]"
    echo "  auto_tweet:     ${launchd_auto_status}"
    echo "  process_tweets: ${launchd_proc_status}"
    echo "[Cron (pmset) モード]"
    echo "  cron 設定:      ${cron_status}"

    # 推定される現在のモード
    if [[ "$launchd_auto_status" == "✅ 有効 (ロード済)" && "$launchd_proc_status" == "✅ 有効 (ロード済)" && "$cron_status" != "✅ 有効 (設定有)" ]]; then
        current_mode="Launchd"
    elif [[ "$launchd_auto_status" != "✅ 有効 (ロード済)" && "$launchd_proc_status" != "✅ 有効 (ロード済)" && "$cron_status" == "✅ 有効 (設定有)" ]]; then
        current_mode="Cron (pmset)"
    elif [[ "$launchd_auto_status" != "✅ 有効 (ロード済)" && "$launchd_proc_status" != "✅ 有効 (ロード済)" && "$cron_status" != "✅ 有効 (設定有)" ]]; then
         current_mode="どちらも無効"
    else
         current_mode="混在または不明 (手動確認推奨)"
    fi
     echo "----------------------------------"
     echo "現在の推奨モード: ${current_mode}"
     echo "----------------------------------"
}

# ヘルプ表示
show_help() {
    cat << EOF
使用方法: $0 [pmset|launchd|status|help]

macOS環境での定期実行モードを切り替えます。

オプション:
  pmset    : Cron + pmset_version スクリプトによる実行モードに設定します。
             (launchdジョブをアンロードし、cron設定を促します)
  launchd  : Launchd + launchd_version スクリプトによる実行モードに設定します。
             (cron設定解除を促し、pmsetスケジュールをクリア、launchdジョブをロードします)
  status   : 現在の定期実行設定の状況を表示します。
  help     : このヘルプを表示します。

注意:
- このスクリプトは crontab の内容を自動編集しません。
  モード変更後は 'crontab -e' で手動編集が必要です。
- pmset モードを使用するには、事前に sudoers 設定が必要です。
- launchd モードを使用するには、plist ファイルが適切に配置されている必要があります。
EOF
}

# --- メイン処理 ---

COMMAND="${1:-help}" # 引数がなければ help を表示

case "$COMMAND" in
    "pmset")
        echo "--- Cron (pmset) モードに切り替え --- "
        echo "[1/2] Launchd ジョブをアンロードします..."
        if [[ -f "$LAUNCHD_AUTO_TWEET_PLIST" ]]; then
            launchctl unload "$LAUNCHD_AUTO_TWEET_PLIST" 2>/dev/null
            echo "  ${LAUNCHD_AUTO_TWEET_LABEL} をアンロードしました (または既にアンロード済)。"
        else
            echo "  ${LAUNCHD_AUTO_TWEET_PLIST} が見つかりません。スキップします。"
        fi
        if [[ -f "$LAUNCHD_PROCESS_TWEETS_PLIST" ]]; then
            launchctl unload "$LAUNCHD_PROCESS_TWEETS_PLIST" 2>/dev/null
            echo "  ${LAUNCHD_PROCESS_TWEETS_LABEL} をアンロードしました (または既にアンロード済)。"
         else
            echo "  ${LAUNCHD_PROCESS_TWEETS_PLIST} が見つかりません。スキップします。"
        fi

        echo "[2/2] crontab の設定を確認・有効化してください。"
        echo "  'crontab -e' を実行し、以下の行が有効になっていることを確認してください:"
        echo "    # pmset_version/auto_tweet.sh を90分ごとに実行 ..."
        echo "    # pmset_version/process_tweets.sh を10分ごとに実行 ..."
        echo "  (もし launchd 用の設定があればコメントアウトしてください)"
        echo ""
        echo "重要: pmset モードを使用するには、事前に sudoers で NOPASSWD: /usr/bin/pmset の設定が必要です。"
        echo "---------------------------------------"
        show_status # 完了後のステータス表示
        ;;

    "launchd")
        echo "--- Launchd モードに切り替え --- "
        echo "[1/3] crontab の設定を確認・無効化してください。"
        echo "  'crontab -e' を実行し、以下の行がコメントアウトまたは削除されていることを確認してください:"
        echo "    # pmset_version/auto_tweet.sh を90分ごとに実行 ..."
        echo "    # pmset_version/process_tweets.sh を10分ごとに実行 ..."

        echo "[2/3] pmset による既存のスケジュールをクリアします..."
        if sudo pmset schedule cancelall 2>/dev/null; then
             echo "  pmset スケジュールをクリアしました。"
        else
             echo "  pmset スケジュールのクリアに失敗しました (sudo権限がないか、スケジュールが存在しない可能性があります)。"
        fi

        echo "[3/3] Launchd ジョブをロードします..."
         if [[ -f "$LAUNCHD_AUTO_TWEET_PLIST" ]]; then
            launchctl load "$LAUNCHD_AUTO_TWEET_PLIST" 2>/dev/null
             echo "  ${LAUNCHD_AUTO_TWEET_LABEL} をロードしました (または既にロード済)。"
        else
            echo "  警告: ${LAUNCHD_AUTO_TWEET_PLIST} が見つかりません。ロードできませんでした。"
            echo "       '${HOME}/Library/LaunchAgents/' に正しいplistファイルがあるか確認してください。"
        fi
         if [[ -f "$LAUNCHD_PROCESS_TWEETS_PLIST" ]]; then
            launchctl load "$LAUNCHD_PROCESS_TWEETS_PLIST" 2>/dev/null
            echo "  ${LAUNCHD_PROCESS_TWEETS_LABEL} をロードしました (または既にロード済)。"
         else
             echo "  警告: ${LAUNCHD_PROCESS_TWEETS_PLIST} が見つかりません。ロードできませんでした。"
             echo "       '${HOME}/Library/LaunchAgents/' に正しいplistファイルがあるか確認してください。"
        fi
        echo "-------------------------------------"
        show_status # 完了後のステータス表示
        ;;

    "status")
        show_status
        ;;

    "help"|*)
        show_help
        ;;
esac

exit 0 