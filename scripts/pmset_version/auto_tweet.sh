#!/bin/bash

# --- エラーハンドリング設定 ---
set -euo pipefail
# ---

# Auto Tweetスクリプトの環境変数
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")

# --- 共通設定ファイルの読み込み ---
source "${SCRIPT_DIR}/../config/common_config.sh" || { echo "共通設定ファイルの読み込みに失敗しました"; exit 1; }
# ---
# --- 共通関数ファイルの読み込み ---
source "${SCRIPT_DIR}/../functions/common_functions.sh" || { echo "共通関数ファイルの読み込みに失敗しました"; exit 1; }
# ---

PROCESS_ID=$$
# LOG_DIR を修正: scripts/logs/pmset_version/auto_tweet/ になるように
LOG_DIR="${COMMON_LOG_BASE_DIR}/pmset_version/auto_tweet"
LOG_FILE="${LOG_DIR}/auto_tweet.log"
TIMESTAMP_FILE="${SCRIPT_DIR}/auto_tweet_last_run.txt"
WAKE_SCHEDULE_FILE="${SCRIPT_DIR}/wake_schedule.txt"
LOCK_FILE="${SCRIPT_DIR}/.auto_tweet.lock"
# 一時ログファイルの定義 (共通関数で使用)
TEMP_LOG_FILE="${LOG_DIR}/auto_tweet_${PROCESS_ID}.tmp"
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
    # TEMP_LOG_FILE の作成は不要 (log関数が自動で追記するため)
    # caffeinate の起動と PID 保存
    caffeinate -i -w $$ & CAFFEINATE_PID=$!
    log "INFO" "======= 新しいプロセス実行開始 ======="
    return 0
}

# check_lock 関数の定義は削除

schedule_next_wake() {
    # 90分後の1分前に設定（89分後）
    local next_time
    next_time=$(date -v+89M '+%Y-%m-%d %H:%M:%S')
    local formatted_time
    formatted_time=$(date -j -f "%Y-%m-%d %H:%M:%S" "$next_time" "+%m/%d/%y %H:%M:%S")

    echo "$next_time" > "$WAKE_SCHEDULE_FILE"
    if sudo pmset schedule wake "$formatted_time"; then
        log "INFO" "次回の自動起動をスケジュールしました: $formatted_time"
    else
        log "ERROR" "スケジュール設定失敗"
    fi
}

# --- 個別処理関数 ---

# 前回実行からの経過時間をチェックし、実行すべきか判断する (削除 -> 共通関数へ)
# check_execution_interval() { ... }

# 現在時刻に基づき、ピーク時間帯フラグオプションを決定する
# determine_peak_hour_flag() { ... }

# manage.py auto_post コマンドを実行し、必要に応じてリトライする (削除 -> 共通関数へ)
# execute_auto_post_command() { ... }

# --- メイン処理 ---
main() {
    # 環境設定
    setup_environment || { log "ERROR" "環境設定に失敗"; exit 1; }

    # 多重起動チェック
    check_lock "auto_tweet.sh(pmset)" || exit 0

    # 実行間隔チェック (共通関数呼び出しに変更)
    if ! check_execution_interval "$@"; then
        # スキップ時は次回のスケジュールを設定して終了
        log "INFO" "スキップのため次回のスケジュールを設定します。"
        schedule_next_wake
        exit 0
    fi

    # ピーク時間フラグ判定 (共通関数呼び出しに変更)
    local peak_hour_option=$(determine_peak_hour_flag_option)

    # 親プロセスのPID設定 (manage.pyから参照される場合)
    export SCRIPT_PID=$PROCESS_ID

    # 自動投稿コマンド実行 (共通関数呼び出しに変更)
    if execute_auto_post_command "$peak_hour_option"; then
        # 成功した場合のみ最終実行時刻を更新
        local current_time
        current_time=$(date +%s)
        echo "$current_time" > "$TIMESTAMP_FILE"
        log "INFO" "最終実行時刻を更新しました: $(date -r "$current_time" '+%Y-%m-%d %H:%M:%S')"
    else
        # 失敗した場合 (エラーログは関数内で出力済み)
        # 必要であればここで追加のエラー処理を行う
        log "ERROR" "自動投稿処理全体が失敗しました。"
    fi

    # 次回起動スケジュール設定 (成功・失敗に関わらず設定)
    schedule_next_wake

    log "INFO" "スクリプト実行完了"
}

main "$@" 