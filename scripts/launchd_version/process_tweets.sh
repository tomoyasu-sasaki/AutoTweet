#!/bin/bash

# --- エラーハンドリング設定 ---
set -euo pipefail
# ---

# スケジュールされたツイートを処理するスクリプト
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
# LOG_DIR を修正: scripts/logs/launchd_version/process_tweets/ になるように
LOG_DIR="${COMMON_LOG_BASE_DIR}/launchd_version/process_tweets"
LOG_FILE="${LOG_DIR}/process_tweets.log"
LOCK_FILE="${SCRIPT_DIR}/.process_tweets.lock"

# ロギング用一時ファイル (このプロセスだけの) (共通関数で使用)
TEMP_LOG_FILE="${LOG_DIR}/process_tweets_${PROCESS_ID}.tmp"

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

# 次回のスケジュール時刻を計算（10分後）
calculate_next_schedule() {
    local current_hour=$(date +%H | sed 's/^0//')  # 先頭の0を削除
    local current_min=$(date +%M | sed 's/^0//')   # 先頭の0を削除
    local next_min=$((current_min + 10))
    local next_hour=$current_hour
    local next_date=$(date +%Y-%m-%d)
    
    # 次の分が60以上になる場合は時間を調整
    if [ $next_min -ge 60 ]; then
        next_min=$((next_min - 60))
        next_hour=$((next_hour + 1))
        
        # 次の時間が24以上になる場合は日付を調整
        if [ $next_hour -ge 24 ]; then
            next_hour=$((next_hour - 24))
            next_date=$(date -v+1d +%Y-%m-%d)
        fi
    fi
    
    # 分が1桁の場合は先頭に0を付ける
    if [ $next_min -lt 10 ]; then
        next_min="0$next_min"
    fi
    
    # 時間が1桁の場合は先頭に0を付ける
    if [ $next_hour -lt 10 ]; then
        next_hour="0$next_hour"
    fi
    
    echo "${next_date} ${next_hour}:${next_min}:00"
}

# 次回実行時のスリープからの自動起動をスケジュール
schedule_next_wake() {
    local next_time=$(calculate_next_schedule)
    log "INFO" "次回処理時刻（launchdで管理）: $next_time"
    log "INFO" "次回の自動起動はlaunchdが管理します"
}

# 実行完了後に再びスリープ状態に戻す（夜間のみ）
sleep_after_execution() {
    log "INFO" "処理が完了しました"
}

# --- 個別処理関数 ---

# 現在時刻に基づき、ピーク時間帯フラグを決定する (削除 -> 共通関数へ)
# determine_peak_hour_flag() { ... }

# manage.py process_tweets コマンドを実行し、レート制限時には再試行する (削除 -> 共通関数へ)
# execute_process_tweets_command() { ... }

# --- メイン処理 ---
main() {
    # 多重起動チェック
    check_lock "process_tweets.sh(launchd)" || exit 0

    # Pythonパスログ
    log "INFO" "Pythonパスを設定: ${PYTHON_BIN}"

    # 実行時刻ログ
    local current_time_str=$(date '+%Y-%m-%d %H:%M:%S')
    local current_hour=$(date +%H)
    log "INFO" "処理開始時刻: ${current_time_str}"

    # プロジェクトディレクトリへ移動
    cd "${PROJECT_DIR}" || { log "ERROR" "プロジェクトディレクトリに移動できません: ${PROJECT_DIR}"; exit 1; }
    log "INFO" "auto_tweet_projectディレクトリに移動しました"

    # 基本オプション設定 (リトライ回数)
    local base_options="--max-retries=${RETRY_COUNT}"

    # ピーク時間フラグ判定 & オプション追加 (共通関数呼び出しに変更)
    # local peak_hour_option=$(determine_peak_hour_flag)
    local peak_hour_option
    peak_hour_option=$(determine_peak_hour_flag_option)
    local final_options="${base_options}${peak_hour_option}"

    # ツイート処理コマンド実行 (共通関数呼び出しに変更)
    execute_process_tweets_command "$final_options"
    # 成功/失敗ログは関数内で出力される

    # 次回起動スケジュール設定
    schedule_next_wake

    log "INFO" "スクリプトの実行が完了しました"
}

main 