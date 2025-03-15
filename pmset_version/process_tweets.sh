#!/bin/bash

# スケジュールされたツイートを処理するスクリプト
# シンボリックリンクの実体を解決してディレクトリを取得
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROCESS_ID=$$
LOG_DIR="${SCRIPT_DIR}/logs/process_tweets"
LOG_FILE="${LOG_DIR}/process_tweets.log"
WAKE_SCHEDULE_FILE="${SCRIPT_DIR}/process_wake_schedule.txt"
LOCK_FILE="${SCRIPT_DIR}/.process_tweets.lock"
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
    TEMP_LOG_FILE="${LOG_DIR}/process_tweets_${PROCESS_ID}.tmp"
    caffeinate -i -w $$ & CAFFEINATE_PID=$!
    log "INFO" "======= 新しいプロセス実行開始 ======="
    return 0
}

check_lock() {
    if [[ -f "$LOCK_FILE" ]] && ps -p $(cat "$LOCK_FILE") > /dev/null; then
        log "WARN" "別のprocess_tweets.shが実行中（PID: $(cat $LOCK_FILE)）のため処理をスキップします。"
        return 1
    fi
    echo $PROCESS_ID > "$LOCK_FILE"
    return 0
}

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

main() {
    setup_environment || { log "ERROR" "環境設定に失敗"; exit 1; }
    check_lock || exit 0

    # 親プロセスのPIDを環境変数として渡す
    export SCRIPT_PID=$PROCESS_ID

    log "INFO" "Pythonパスを設定: ${PYTHON_BIN}"
    log "INFO" "処理開始時刻: $(date '+%Y-%m-%d %H:%M:%S')"

    cd $(dirname "${SCRIPT_DIR}")
    CURRENT_DIR=$(pwd)
    PROJECT_DIR="${CURRENT_DIR}/auto_tweet_project"
    log "INFO" "auto_tweet_projectディレクトリに移動しました: ${CURRENT_DIR}"

    OPTIONS="--max-retries=3"
    [[ $(date +%H) =~ ^(06|12|18)$ ]] && {
        OPTIONS="$OPTIONS --peak-hour"
        log "INFO" "ピーク時間帯での実行です。--peak-hourオプションを追加します。"
    }

    CMD="${PYTHON_BIN} ${PROJECT_DIR}/manage.py process_tweets ${OPTIONS}"
    log "INFO" "ツイート処理コマンドを実行します: ${CMD}"

    # Pythonコマンドを実行し、出力を処理
    cd "${PROJECT_DIR}" && eval "$CMD" 2>&1 | while IFS= read -r line; do
        # Pythonからの出力を一時ファイルに記録（重複を防ぐため直接ログファイルには書き込まない）
        echo "$line" >> "${TEMP_LOG_FILE}"
    done
    EXIT_CODE=${PIPESTATUS[1]}

    if [ ${EXIT_CODE} -eq 0 ]; then
        log "INFO" "ツイート処理が完了しました"
    else
        log "ERROR" "ツイート処理に失敗しました (終了コード: ${EXIT_CODE})"
        
        if grep -q "Too Many Requests" "${TEMP_LOG_FILE}"; then
            WAIT_TIME=300
            log "WARN" "レート制限エラーが検出されました。${WAIT_TIME}秒後に再実行します..."
            sleep ${WAIT_TIME}
            
            RETRY_CMD="${PYTHON_BIN} ${PROJECT_DIR}/manage.py process_tweets --skip-api-test"
            log "INFO" "再実行中: ${RETRY_CMD}"
            
            cd "${PROJECT_DIR}" && eval "$RETRY_CMD" 2>&1 | while IFS= read -r line; do
                echo "$line" >> "${TEMP_LOG_FILE}"
            done
            RETRY_EXIT_CODE=${PIPESTATUS[1]}
            
            if [ ${RETRY_EXIT_CODE} -eq 0 ]; then
                log "INFO" "再実行が成功しました"
            else
                log "ERROR" "再実行も失敗しました (終了コード: ${RETRY_EXIT_CODE})"
            fi
        fi
    fi

    schedule_next_wake
    log "INFO" "スクリプトの実行が完了しました"
}

main "$@" 