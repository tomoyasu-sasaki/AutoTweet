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

# ログレベルの定義（配列の代わりに関数を使用）
get_log_level() {
    case "$1" in
        "DEBUG") echo 0 ;;
        "INFO")  echo 1 ;;
        "WARN")  echo 2 ;;
        "ERROR") echo 3 ;;
        *)       echo 1 ;;
    esac
}

CURRENT_LOG_LEVEL="INFO"

# 共通の関数
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # ログレベルチェック
    [[ $(get_log_level "$level") -ge $(get_log_level "$CURRENT_LOG_LEVEL") ]] || return 0
    
    # プロセス情報を含むログメッセージの作成
    local log_message="${timestamp}: [PID:${PROCESS_ID}] [${level}] ${message}"
    
    # 一時ログファイルが設定されていない場合は直接メインログに出力
    if [[ -n "${TEMP_LOG_FILE}" ]]; then
        echo "$log_message" | tee -a "${TEMP_LOG_FILE}"
    else
        echo "$log_message" | tee -a "${LOG_FILE}"
    fi
    
    # エラーレベルの場合は標準エラーにも出力
    [[ "$level" == "ERROR" ]] && echo "$log_message" >&2
}

cleanup() {
    local exit_code=$?
    log "DEBUG" "クリーンアップ処理開始"
    
    # ロックファイルの削除
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log "DEBUG" "ロックファイル削除完了"
    fi
    
    # caffeinateプロセスの終了
    if [[ -n "$CAFFEINATE_PID" ]]; then
        kill $CAFFEINATE_PID 2>/dev/null
        log "DEBUG" "caffeinateプロセス(PID:$CAFFEINATE_PID)終了"
    fi
    
    # 一時ログファイルの処理
    if [[ -f "${TEMP_LOG_FILE}" ]]; then
        # 一時ログファイルの内容を確認
        if [[ -s "${TEMP_LOG_FILE}" ]]; then
            log "DEBUG" "一時ログファイルをメインログに統合"
            # 一時ファイルの内容をフィルタリングして統合
            cat "${TEMP_LOG_FILE}" | while IFS= read -r line; do
                # 日付形式のみの行をスキップ
                if ! [[ "$line" =~ ^[0-9]{2}/[0-9]{2}/[0-9]{4}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
                    echo "$line" >> "${LOG_FILE}"
                fi
            done
            log "DEBUG" "ログ統合完了"
        else
            log "DEBUG" "一時ログファイルが空のためスキップ"
        fi
        
        # 一時ファイルの削除
        rm -f "${TEMP_LOG_FILE}"
        log "DEBUG" "一時ログファイル削除完了: ${TEMP_LOG_FILE}"
    fi
    
    # その他の古い一時ファイルの削除
    local old_files=$(find "${LOG_DIR}" -name "auto_tweet_*.tmp" -mmin +60 2>/dev/null)
    if [[ -n "$old_files" ]]; then
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            rm -f "$file"
            log "DEBUG" "古い一時ファイルを削除: $file"
        done <<< "$old_files"
    fi
    
    log "INFO" "プロセス終了 (終了コード: $exit_code)"
    log "INFO" "======= プロセス実行終了 ======="
}

trap cleanup EXIT

setup_environment() {
    # ログディレクトリの作成
    if ! mkdir -p "${LOG_DIR}"; then
        echo "ERROR: ログディレクトリの作成に失敗: ${LOG_DIR}"
        return 1
    fi
    
    # 一時ログファイルの設定
    TEMP_LOG_FILE="${LOG_DIR}/auto_tweet_${PROCESS_ID}.tmp"
    touch "${TEMP_LOG_FILE}" || {
        echo "ERROR: 一時ログファイルの作成に失敗: ${TEMP_LOG_FILE}"
        return 1
    }
    
    log "DEBUG" "環境設定開始"
    
    # caffeinateプロセスの開始
    caffeinate -i -w $$ & CAFFEINATE_PID=$!
    log "DEBUG" "caffeinate開始 (PID:$CAFFEINATE_PID)"
    
    log "INFO" "======= 新しいプロセス実行開始 ======="
    return 0
}

check_lock() {
    log "DEBUG" "ロックチェック開始"
    
    if [[ -f "$LOCK_FILE" ]]; then
        local locked_pid=$(cat "$LOCK_FILE")
        if ps -p $locked_pid > /dev/null; then
            log "WARN" "別のプロセスが実行中 (PID:$locked_pid) - 処理をスキップ"
            return 1
        else
            log "INFO" "古いロックファイルを削除 (PID:$locked_pid)"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $PROCESS_ID > "$LOCK_FILE"
    log "DEBUG" "ロックファイル作成 (PID:$PROCESS_ID)"
    return 0
}

format_date() {
    local input_date="$1"
    local format="$2"
    local input_format="$3"
    date -j -f "$input_format" "$input_date" "$format" 2>/dev/null
}

schedule_next_wake() {
    log "DEBUG" "次回起動スケジュール設定開始"
    
    # 85分後の時刻を計算
    local next_time=$(date -v+85M '+%Y-%m-%d %H:%M:%S')
    local formatted_time=$(date -j -f "%Y-%m-%d %H:%M:%S" "$next_time" "+%m/%d/%Y %H:%M:%S" 2>/dev/null)
    
    if [[ -z "$formatted_time" ]]; then
        log "ERROR" "日付フォーマットの変換に失敗: $next_time"
        return 1
    fi
    
    # 現在のスケジュールを確認（複数行の出力を適切に処理）
    local latest_schedule=""
    local latest_timestamp=0
    
    while IFS= read -r schedule; do
        [[ -z "$schedule" ]] && continue
        local timestamp=$(date -j -f "%m/%d/%Y %H:%M:%S" "$schedule" "+%s" 2>/dev/null)
        if [[ -n "$timestamp" && "$timestamp" -gt "$latest_timestamp" ]]; then
            latest_timestamp=$timestamp
            latest_schedule=$schedule
        fi
    done < <(sudo pmset -g sched | grep "wake at" | sed 's/.*wake at //')
    
    if [[ -n "$latest_schedule" ]]; then
        log "DEBUG" "現在の最新スケジュール: $latest_schedule"
        local new_timestamp=$(date -j -f "%m/%d/%Y %H:%M:%S" "$formatted_time" "+%s" 2>/dev/null)
        
        if [[ $latest_timestamp -gt $new_timestamp ]]; then
            local current_formatted=$(date -j -f "%m/%d/%Y %H:%M:%S" "$latest_schedule" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            local new_formatted=$(date -j -f "%m/%d/%Y %H:%M:%S" "$formatted_time" "+%Y-%m-%d %H:%M:%S" 2>/dev/null)
            log "INFO" "スケジュール更新スキップ (現在: $current_formatted > 新規: $new_formatted)"
            return 0
        fi
    fi
    
    echo "$next_time" > "$WAKE_SCHEDULE_FILE"
    if sudo pmset schedule wake "$formatted_time"; then
        log "INFO" "次回起動スケジュール設定完了: $(date -j -f "%m/%d/%Y %H:%M:%S" "$formatted_time" "+%Y-%m-%d %H:%M:%S")"
    else
        log "ERROR" "スケジュール設定失敗: $formatted_time"
    fi
}

main() {
    setup_environment || { log "ERROR" "環境設定失敗"; exit 1; }
    check_lock || exit 0
    
    # テストモードの確認
    if [[ "$1" == "--test" ]]; then
        log "INFO" "テストモードで実行"
        CURRENT_LOG_LEVEL="DEBUG"
    else
        # 実行間隔チェック
        CURRENT_TIME=$(date +%s)
        LAST_RUN=$(cat "$TIMESTAMP_FILE" 2>/dev/null || echo 0)
        
        if (( CURRENT_TIME - LAST_RUN < 5340 )); then
            log "INFO" "前回実行から90分未経過のためスキップ"
            schedule_next_wake
            exit 0
        fi
    fi
    
    # 投稿テキストとフラグの設定
    TEXT="#投稿テキスト"
    PEAK_HOUR_FLAG=""
    
    # ピーク時間判定
    CURRENT_HOUR=$(date +%H)
    CURRENT_MIN=$(date +%M)
    if [[ ($CURRENT_HOUR =~ ^(05|11|17)$ && $CURRENT_MIN -ge 55) || ($CURRENT_HOUR =~ ^(06|12|18)$ && $CURRENT_MIN -le 05) ]]; then
        PEAK_HOUR_FLAG="--peak-hour"
        log "INFO" "ピーク時間帯フラグ設定"
    fi
    
    # 親プロセスのPID設定
    export SCRIPT_PID=$PROCESS_ID
    
    # 投稿コマンドの構築と実行
    CMD="$PYTHON_BIN $PROJECT_DIR/manage.py auto_post --text \"$TEXT\" --interval=90 --post-now $PEAK_HOUR_FLAG"
    log "INFO" "投稿コマンド: ${CMD//$'\n'/}"
    
    local retry_count=0
    local max_retries=3
    
    while (( retry_count < max_retries )); do
        ((retry_count++))
        log "DEBUG" "投稿試行 ($retry_count/$max_retries)"
        
        if (cd "$PROJECT_DIR" && eval "$CMD") 2>&1 | while IFS= read -r line; do
            echo "$line" >> "${TEMP_LOG_FILE}"
        done; then
            log "INFO" "投稿成功"
            break
        else
            if (( retry_count < max_retries )); then
                log "WARN" "投稿失敗 - 30秒後に再試行"
                sleep 30
            else
                log "ERROR" "投稿失敗 - 最大試行回数到達"
            fi
        fi
    done
    
    # タイムスタンプの更新
    echo "$CURRENT_TIME" > "$TIMESTAMP_FILE"
    local current_date=$(date "+%Y-%m-%d %H:%M:%S")
    log "DEBUG" "最終実行時刻を更新: $current_date"
    
    # 次回スケジュールの設定
    schedule_next_wake
    
    # 夜間モード処理
    if [[ $CURRENT_HOUR -ge 22 || $CURRENT_HOUR -lt 6 ]]; then
        log "INFO" "夜間スリープモードに移行"
        sleep 5
        pmset sleepnow
    fi
}

main "$@" 