#!/bin/bash

# --- エラーハンドリング設定 ---
set -euo pipefail
# ---

# 自動投稿を実行するスクリプト
# シンボリックリンクの実体を解決してディレクトリを取得
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# --- 共通設定ファイルの読み込み ---
source "${SCRIPT_DIR}/../config/common_config.sh" || { echo "共通設定ファイルの読み込みに失敗しました"; exit 1; }
# ---
# --- 共通関数ファイルの読み込み ---
source "${SCRIPT_DIR}/../functions/common_functions.sh" || { echo "共通関数ファイルの読み込みに失敗しました"; exit 1; }
# ---

PROCESS_ID=$$
# LOG_DIR を修正: scripts/logs/launchd_version/auto_tweet/ になるように
LOG_DIR="${COMMON_LOG_BASE_DIR}/launchd_version/auto_tweet"
LOG_FILE="${LOG_DIR}/auto_tweet.log"
TIMESTAMP_FILE="${SCRIPT_DIR}/auto_tweet_last_run.txt"
LOCK_FILE="${SCRIPT_DIR}/.auto_tweet.lock"

# ロギング用一時ファイル (このプロセスだけの) (共通関数で使用)
TEMP_LOG_FILE="${LOG_DIR}/auto_tweet_${PROCESS_ID}.tmp"

# ログディレクトリが存在しない場合は作成
mkdir -p "${LOG_DIR}"

# 一時ログファイルを作成 (log関数で代替)
# echo "$(date '+%Y-%m-%d %H:%M:%S'): [PID:${PROCESS_ID}] ======= 新しいプロセス実行開始 =======" > "${TEMP_LOG_FILE}"
log "INFO" "======= 新しいプロセス実行開始 ======="

# ロックファイルの確認 (check_lock 関数で代替)
# if [ -f "$LOCK_FILE" ]; then ... fi

# 新しいロックファイルを作成 (check_lock 関数で代替)
# echo $PROCESS_ID > "$LOCK_FILE"

# スクリプト終了時にロックファイルを自動的に削除する関数 (common_cleanup で代替)
# cleanup() { ... }

# スクリプト終了時またはエラー時にクリーンアップ関数を実行
trap common_cleanup EXIT

# ログ出力関数 (common_functions.sh の log 関数で代替)
# log_temp() { ... }
# log_message() { ... }

# 次回のスケジュール時刻を計算（90分後）
calculate_next_schedule() {
    local current_hour=$(date +%H | sed 's/^0//')  # 先頭の0を削除
    local current_min=$(date +%M | sed 's/^0//')   # 先頭の0を削除
    
    # 90分後の時間と分を計算
    local added_minutes=90
    local total_minutes=$((current_hour * 60 + current_min + added_minutes))
    local next_hour=$((total_minutes / 60))
    local next_min=$((total_minutes % 60))
    local next_date
    
    # 翌日になる場合
    if [ $next_hour -ge 24 ]; then
        next_hour=$((next_hour % 24))
        next_date=$(date -v+1d +%Y-%m-%d)
    else
        next_date=$(date +%Y-%m-%d)
    fi
    
    # 分が1桁の場合は先頭に0を付ける
    if [ $next_min -lt 10 ]; then
        next_min="0$next_min"
    fi
    
    echo "${next_date} ${next_hour}:${next_min}:00"
}

# 次回実行時のスリープからの自動起動をスケジュール
schedule_next_wake() {
    local next_time=$(calculate_next_schedule)
    log "INFO" "次回実行時刻（launchdで管理）: $next_time"
    log "INFO" "次回の自動起動はlaunchdが管理します"
}

# 実行完了後に再びスリープ状態に戻す
sleep_after_execution() {
    log "INFO" "処理が完了しました"
}

# --- 個別処理関数 ---

# 前回実行からの経過時間をチェックし、実行すべきか判断する (削除 -> 共通関数へ)
# check_execution_interval() { ... }

# 現在時刻に基づき、ピーク時間帯フラグオプションを決定する
# determine_peak_hour_flag() { ... }

# manage.py auto_post コマンドを実行し、レート制限時には再試行する (削除 -> 共通関数へ)
# execute_auto_post_command() { ... }

# --- メイン処理 ---
main() {
    # 多重起動チェック
    check_lock "auto_tweet.sh(launchd)" || exit 0

    # 実行時刻ログ
    local current_time=$(date +%s)
    local current_hour=$(date +%H)
    local current_minute=$(date +%M)
    local current_tz=$(date +%Z)
    log "INFO" "実行時刻: ${current_hour}時${current_minute}分 (タイムゾーン: ${current_tz})"

    # 実行間隔チェック (共通関数呼び出しに変更)
    if ! check_execution_interval "$@"; then
        # スキップ時は次回のスケジュールを設定して終了 (launchd版でも同様)
        log "INFO" "スキップのため次回のスケジュールを設定します。"
        schedule_next_wake
        exit 0
    fi

    # 投稿テキストログ
    log "INFO" "投稿テキスト: ${DEFAULT_TWEET_TEXT}"

    # プロジェクトディレクトリへ移動
    cd "${PROJECT_DIR}" || { log "ERROR" "プロジェクトディレクトリに移動できません: ${PROJECT_DIR}"; exit 1; }
    log "INFO" "auto_tweet_projectディレクトリに移動しました"

    # ピーク時間フラグ判定 (共通関数呼び出しに変更)
    local peak_hour_option=$(determine_peak_hour_flag_option)

    # Pythonパスログ
    log "INFO" "Pythonパスを設定: ${PYTHON_BIN}"

    # 自動投稿コマンド実行 (共通関数呼び出しに変更)
    if execute_auto_post_command "$peak_hour_option"; then
        # 成功した場合のみ最終実行時刻を更新
        echo "$current_time" > "$TIMESTAMP_FILE"
        log "INFO" "最終実行時刻を更新しました: $(date -r $current_time '+%Y-%m-%d %H:%M:%S')"
    else
        # 失敗した場合 (エラーログは関数内で出力済み)
        log "ERROR" "自動投稿処理全体が失敗しました。"
    fi

    # 次回起動スケジュール設定 (成功・失敗に関わらず設定)
    schedule_next_wake

    log "INFO" "スクリプトの実行が完了しました"
}

main "$@" # スクリプト引数を main 関数に渡す