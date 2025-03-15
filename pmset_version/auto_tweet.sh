#!/bin/bash

# Auto Tweetスクリプトの環境変数
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROCESS_ID=$$
LOG_DIR="${SCRIPT_DIR}/logs/auto_tweet"
LOG_FILE="${LOG_DIR}/auto_tweet.log"
TIMESTAMP_FILE="${SCRIPT_DIR}/auto_tweet_last_run.txt"
WAKE_SCHEDULE_FILE="${SCRIPT_DIR}/wake_schedule.txt"
LOCK_FILE="${SCRIPT_DIR}/.auto_tweet.lock"
PYTHON_BIN="${SCRIPT_DIR}/../.venv/bin/python"
PROJECT_DIR="${SCRIPT_DIR}/../auto_tweet_project"

# 共通の関数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp}: [PID:${PROCESS_ID}] [${level}] ${message}" | tee -a "${TEMP_LOG_FILE}"
}

log_temp() {
    local message=$1
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "${timestamp}: [PID:${PROCESS_ID}] ${message}" >> "${TEMP_LOG_FILE}"
}

cleanup() {
    rm -f "$LOCK_FILE"
    [[ -n "$CAFFEINATE_PID" ]] && kill $CAFFEINATE_PID 2>/dev/null
    
    # 一時ファイルの内容をメインログに追記してから削除
    if [[ -f "${TEMP_LOG_FILE}" ]]; then
        # 重複行を削除してからメインログに追記
        awk '!seen[$0]++' "${TEMP_LOG_FILE}" >> "${LOG_FILE}"
        rm -f "${TEMP_LOG_FILE}"
    fi
}

trap cleanup EXIT

setup_environment() {
    mkdir -p "${LOG_DIR}"
    TEMP_LOG_FILE="${LOG_DIR}/auto_tweet_${PROCESS_ID}.tmp"
    caffeinate -i -w $$ & CAFFEINATE_PID=$!
    log "INFO" "======= 新しいプロセス実行開始 ======="
    return 0
}

check_lock() {
    if [[ -f "$LOCK_FILE" ]] && ps -p $(cat "$LOCK_FILE") > /dev/null; then
        log "WARN" "別のauto_tweet.shが実行中（PID: $(cat $LOCK_FILE)）のため処理をスキップします。"
        return 1
    fi
    echo $PROCESS_ID > "$LOCK_FILE"
    return 0
}

schedule_next_wake() {
    # 90分後の2分前に設定
    local next_time=$(date -v+88M '+%Y-%m-%d %H:%M:%S')
    local formatted_time=$(date -j -f "%Y-%m-%d %H:%M:%S" "$next_time" "+%m/%d/%y %H:%M:%S")
    
    # 現在のスケジュールを確認
    local current_schedule=$(sudo pmset -g sched | grep "wake at" | awk -F"wake at " '{print $2}' | awk '{print $1, $2}')
    if [[ -n "$current_schedule" ]]; then
        local current_timestamp=$(date -j -f "%m/%d/%Y %H:%M:%S" "$current_schedule" "+%s" 2>/dev/null)
        local new_timestamp=$(date -j -f "%m/%d/%y %H:%M:%S" "$formatted_time" "+%s" 2>/dev/null)
        
        # 現在のスケジュールが新しいスケジュールより後の場合はスキップ
        if [[ $current_timestamp -gt $new_timestamp ]]; then
            log "INFO" "現在のスケジュール($current_schedule)が新しいスケジュール($formatted_time)より後のため、更新をスキップします"
            return 0
        fi
    fi
    
    echo "$next_time" > "$WAKE_SCHEDULE_FILE"
    sudo pmset schedule wake "$formatted_time" && \
        log "INFO" "次回の自動起動をスケジュールしました: $formatted_time" || \
        log "ERROR" "スケジュール設定失敗"
}

main() {
    setup_environment || { log "ERROR" "環境設定に失敗"; exit 1; }
    check_lock || exit 0

    if [[ "$1" == "--test" ]]; then
        log "INFO" "テストモードで実行"
    else
        CURRENT_TIME=$(date +%s)
        LAST_RUN=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo 0)
        (( CURRENT_TIME - LAST_RUN >= 5340 )) || { 
            log "INFO" "90分未経過のためスキップ"
            schedule_next_wake
            exit 0
        }
    fi

    TEXT="#AI画像 #AIグラビア #AI美女 #AIアイドル #AIphoto #AIphotograpy #AI女子 #AI彼女 #AIart #美女 #美人 #美少女 #aigirls"
    PEAK_HOUR_FLAG=""
    [[ $(date +%H) =~ ^(06|12|18)$ ]] && {
        PEAK_HOUR_FLAG="--peak-hour"
        log "INFO" "ピーク時間帯のため、peak-hourフラグを設定"
    }

    # 親プロセスのPIDを環境変数として渡す
    export SCRIPT_PID=$PROCESS_ID

    CMD="$PYTHON_BIN $PROJECT_DIR/manage.py auto_post --text \"$TEXT\" --interval=90 --post-now $PEAK_HOUR_FLAG"
    log "INFO" "自動投稿コマンド実行: $CMD"

    for retry in {1..3}; do
        if (cd "$PROJECT_DIR" && eval "$CMD") 2>&1 | while IFS= read -r line; do
            # Pythonからの出力を一時ファイルに記録（重複を防ぐため直接ログファイルには書き込まない）
            echo "$line" >> "${TEMP_LOG_FILE}"
        done; then
            log "INFO" "投稿成功"
            break
        else
            log "WARN" "投稿失敗 - 再試行($retry/3)"
            [[ $retry -lt 3 ]] && sleep 30
        fi
    done

    echo "$CURRENT_TIME" > "$TIMESTAMP_FILE"
    schedule_next_wake

    [[ $(date +%H) -ge 22 || $(date +%H) -lt 6 ]] && {
        log "INFO" "夜間スリープモードに移行"
        sleep 5
        pmset sleepnow
    }
}

main "$@" 