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
# LOG_DIR を修正: scripts/logs/pmset_version/process_tweets/ になるように
LOG_DIR="${COMMON_LOG_BASE_DIR}/pmset_version/process_tweets"
LOG_FILE="${LOG_DIR}/process_tweets.log"
WAKE_SCHEDULE_FILE="${SCRIPT_DIR}/process_wake_schedule.txt"
LOCK_FILE="${SCRIPT_DIR}/.process_tweets.lock"
# 一時ログファイルの定義 (共通関数で使用)
TEMP_LOG_FILE="${LOG_DIR}/process_tweets_${PROCESS_ID}.tmp"
# Caffeinate プロセスID (共通cleanup関数で使用)
CAFFEINATE_PID=""

# 共通の関数 (削除)
# log() { ... }
# log_temp() { ... }
# cleanup() { ... }
# check_lock() { ... }

# 共通クリーンアップ関数をトラップ
trap common_cleanup EXIT

setup_environment() {
    mkdir -p "${LOG_DIR}"
    # TEMP_LOG_FILE の作成は不要
    # caffeinate の起動と PID 保存
    caffeinate -i -w $$ & CAFFEINATE_PID=$!
    log "INFO" "======= 新しいプロセス実行開始 ======="
    return 0
}

# check_lock 関数の定義は削除

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

schedule_next_wake() {
    local next_time=$(calculate_next_schedule)
    local next_date=$(echo "$next_time" | awk '{print $1}')
    local next_time_only=$(echo "$next_time" | awk '{print $2}')
    
    local month=$(date -j -f "%Y-%m-%d" "$next_date" "+%m")
    local day=$(date -j -f "%Y-%m-%d" "$next_date" "+%d")
    local year=$(date -j -f "%Y-%m-%d" "$next_date" "+%y")
    local formatted_date="${month}/${day}/${year}"
    local formatted_time="${formatted_date} ${next_time_only}"

    echo "$next_time" > "$WAKE_SCHEDULE_FILE"
    log "INFO" "次回処理時刻（pmsetで管理）: $next_time"
    log "INFO" "次回の自動起動をスケジュール: $formatted_time"
    
    local pmset_cmd="sudo pmset schedule wake \"$formatted_time\""
    log "INFO" "実行コマンド: $pmset_cmd"
    eval "$pmset_cmd"
    
    if [ $? -eq 0 ]; then
        log "INFO" "次回の自動起動スケジュールが設定されました"
    else
        log "ERROR" "スケジュール設定失敗"
    fi
}

# --- メイン処理 ---
main() {
    # 環境設定
    setup_environment || { log "ERROR" "環境設定に失敗"; exit 1; }

    # 多重起動チェック
    check_lock "process_tweets.sh(pmset)" || exit 0

    # 親プロセスPID設定
    export SCRIPT_PID=$PROCESS_ID

    log "INFO" "Pythonパスを設定: ${PYTHON_BIN}"
    log "INFO" "処理開始時刻: $(date '+%Y-%m-%d %H:%M:%S')"

    # プロジェクトディレクトリへ移動
    cd "${PROJECT_DIR}" || { log "ERROR" "プロジェクトディレクトリに移動できません: ${PROJECT_DIR}"; exit 1; }
    log "INFO" "auto_tweet_projectディレクトリに移動しました: ${PROJECT_DIR}"

    # 基本オプション設定 (リトライ回数)
    local base_options="--max-retries=${RETRY_COUNT}"

    # ピーク時間フラグ判定 & オプション追加 (共通関数呼び出しに変更)
    local peak_hour_option
    peak_hour_option=$(determine_peak_hour_flag_option)
    local final_options="${base_options}${peak_hour_option}"

    # ツイート処理コマンド実行 (共通関数呼び出しに変更)
    execute_process_tweets_command "$final_options"
    # execute_~ の中で成功/失敗ログは出力される

    # 次回起動スケジュール設定 (成功・失敗に関わらず設定)
    schedule_next_wake

    log "INFO" "スクリプト実行完了"
}

main "$@" 