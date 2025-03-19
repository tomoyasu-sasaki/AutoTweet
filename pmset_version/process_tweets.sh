#!/bin/bash

# スケジュールされたツイートを処理するスクリプト
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROCESS_ID=$$
LOG_DIR="${SCRIPT_DIR}/logs/process_tweets"
LOG_FILE="${LOG_DIR}/process_tweets.log"
WAKE_SCHEDULE_FILE="${SCRIPT_DIR}/process_wake_schedule.txt"
LOCK_FILE="${SCRIPT_DIR}/.process_tweets.lock"
PYTHON_BIN="${SCRIPT_DIR}/../.venv/bin/python"
PROJECT_DIR="${SCRIPT_DIR}/../auto_tweet_project"

# クリーンアップフラグ（二重実行防止用）
CLEANUP_DONE=0

# ログレベルの定義
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
    # クリーンアップが既に実行済みの場合はスキップ
    if [[ $CLEANUP_DONE -eq 1 ]]; then
        return 0
    fi
    CLEANUP_DONE=1
    
    local exit_code=$?
    log "DEBUG" "クリーンアップ処理開始 (PID:$$, 終了コード:$exit_code)"
    
    # caffeinateプロセスの終了
    if [[ -n "$CAFFEINATE_PID" ]]; then
        kill $CAFFEINATE_PID 2>/dev/null
        log "DEBUG" "caffeinateプロセス(PID:$CAFFEINATE_PID)終了"
    fi
    
    # 一時ログファイルの処理
    process_temp_log_file() {
        local temp_file="$1"
        log "DEBUG" "一時ファイル処理開始: $temp_file"
        if [[ -f "$temp_file" ]]; then
            # ファイルの権限を確認
            local file_perms=$(stat -f "%Sp" "$temp_file")
            log "DEBUG" "ファイル権限: $file_perms ($temp_file)"
            
            if [[ -s "$temp_file" ]]; then
                log "DEBUG" "一時ログファイルをメインログに統合: $temp_file"
                # 一時ファイルの内容をフィルタリングして統合
                while IFS= read -r line; do
                    # 日付形式のみの行をスキップ
                    if ! [[ "$line" =~ ^[0-9]{2}/[0-9]{2}/[0-9]{4}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
                        echo "$line" >> "${LOG_FILE}"
                    fi
                done < "$temp_file"
                log "DEBUG" "ログ統合完了: $temp_file"
            else
                log "DEBUG" "一時ログファイルが空のためスキップ: $temp_file"
            fi
            
            # 統合後に一時ファイルを削除（複数の方法を試行）
            log "DEBUG" "一時ファイル削除試行: $temp_file"
            
            # ファイルディスクリプタをクローズ
            exec 3>&- 2>/dev/null
            
            # 通常の削除を試行
            rm -f "$temp_file" 2>/dev/null
            sync
            
            if [[ -f "$temp_file" ]]; then
                # 権限を変更して削除を試行
                chmod 666 "$temp_file" 2>/dev/null
                rm -f "$temp_file" 2>/dev/null
                sync
            fi
            
            if [[ -f "$temp_file" ]]; then
                # sudoで削除を試行
                log "DEBUG" "sudoで削除を試行: $temp_file"
                sudo rm -f "$temp_file" 2>/dev/null
                sync
            fi
            
            if [[ ! -f "$temp_file" ]]; then
                log "DEBUG" "一時ログファイル削除完了: $temp_file"
            else
                log "ERROR" "一時ログファイルの削除に失敗: $temp_file"
                ls -l "$temp_file" 2>&1 | while IFS= read -r line; do
                    log "ERROR" "ファイル情報: $line"
                done
            fi
        else
            log "DEBUG" "一時ファイルが存在しません: $temp_file"
        fi
    }
    
    # 現在のプロセスの一時ファイルを処理
    if [[ -n "${TEMP_LOG_FILE}" ]]; then
        log "DEBUG" "現在のプロセスの一時ファイル処理開始: ${TEMP_LOG_FILE}"
        process_temp_log_file "${TEMP_LOG_FILE}"
    else
        log "DEBUG" "TEMP_LOG_FILE が設定されていません"
    fi
    
    # 古い一時ファイルの処理（60分以上前のファイル）
    local old_files
    old_files=$(find "${LOG_DIR}" -name "process_tweets_*.tmp" -mmin +60 2>/dev/null)
    if [[ -n "$old_files" ]]; then
        log "DEBUG" "古い一時ファイルの処理を開始"
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            process_temp_log_file "$file"
        done <<< "$old_files"
    fi
    
    # 最終確認：残っている一時ファイルがないかチェック
    local remaining_files
    remaining_files=$(find "${LOG_DIR}" -name "process_tweets_*.tmp" 2>/dev/null)
    if [[ -n "$remaining_files" ]]; then
        log "WARN" "以下の一時ファイルが残っています："
        while IFS= read -r file; do
            [[ -z "$file" ]] && continue
            log "WARN" "- $file"
            process_temp_log_file "$file"
        done <<< "$remaining_files"
    fi
    
    # ロックファイルの削除（最後に行う）
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log "DEBUG" "ロックファイル削除完了"
    fi
    
    log "INFO" "プロセス終了 (終了コード: $exit_code)"
    log "INFO" "======= プロセス実行終了 ======="
}

# cleanup関数がトラップされていることを確認するログを追加
log "DEBUG" "EXIT trapにcleanup関数を設定"
trap cleanup EXIT

setup_environment() {
    # ログディレクトリの作成
    if ! mkdir -p "${LOG_DIR}"; then
        echo "ERROR: ログディレクトリの作成に失敗: ${LOG_DIR}"
        return 1
    fi
    
    # 一時ログファイルの設定
    TEMP_LOG_FILE="${LOG_DIR}/process_tweets_${PROCESS_ID}.tmp"
    touch "${TEMP_LOG_FILE}" || {
        echo "ERROR: 一時ログファイルの作成に失敗: ${TEMP_LOG_FILE}"
        return 1
    }
    
    # 一時ファイルの権限を設定
    chmod 666 "${TEMP_LOG_FILE}" 2>/dev/null
    
    log "DEBUG" "環境設定開始"
    log "DEBUG" "一時ログファイル作成: ${TEMP_LOG_FILE}"
    
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

calculate_next_schedule() {
    local current_hour=$(date +%H | sed 's/^0//')
    local current_min=$(date +%M | sed 's/^0//')
    local next_min=$((current_min + 10))
    local next_hour=$current_hour
    local next_date=$(date +%Y-%m-%d)
    
    log "DEBUG" "次回スケジュール計算開始 (現在時刻: ${current_hour}:${current_min})"
    
    if [ $next_min -ge 60 ]; then
        next_min=$((next_min - 60))
        next_hour=$((next_hour + 1))
        
        if [ $next_hour -ge 24 ]; then
            next_hour=$((next_hour - 24))
            next_date=$(date -v+1d +%Y-%m-%d)
            log "DEBUG" "日付繰り越し: $next_date"
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
    
    local next_schedule="${next_date} ${next_hour}:${next_min}:00"
    log "DEBUG" "計算された次回スケジュール: $next_schedule"
    echo "$next_schedule"
}

schedule_next_wake() {
    log "DEBUG" "次回起動スケジュール設定開始"
    
    local next_time=$(calculate_next_schedule)
    local next_date=$(echo "$next_time" | awk '{print $1}')
    local next_time_only=$(echo "$next_time" | awk '{print $2}')
    
    local month=$(date -j -f "%Y-%m-%d" "$next_date" "+%m")
    local day=$(date -j -f "%Y-%m-%d" "$next_date" "+%d")
    local year=$(date -j -f "%Y-%m-%d" "$next_date" "+%y")
    local formatted_date="${month}/${day}/${year}"
    local formatted_time="${formatted_date} ${next_time_only}"
    
    log "DEBUG" "フォーマット済み次回時刻: $formatted_time"
    
    # 現在のスケジュールを確認（複数行の出力を適切に処理）
    local latest_schedule=""
    local latest_timestamp=0
    
    while IFS= read -r schedule; do
        [[ -z "$schedule" ]] && continue
        local timestamp=$(date -j -f "%m/%d/%Y %H:%M:%S" "$schedule" "+%s" 2>/dev/null)
        if [[ -n "$timestamp" && "$timestamp" -gt "$latest_timestamp" ]]; then
            latest_timestamp=$timestamp
            latest_schedule=$schedule
            log "DEBUG" "新しい最新スケジュール検出: $schedule"
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
    
    # 親プロセスのPIDを環境変数として渡す
    export SCRIPT_PID=$PROCESS_ID
    
    log "INFO" "Pythonパスを設定: ${PYTHON_BIN}"
    log "INFO" "処理開始時刻: $(date '+%Y-%m-%d %H:%M:%S')"
    
    cd $(dirname "${SCRIPT_DIR}")
    CURRENT_DIR=$(pwd)
    PROJECT_DIR="${CURRENT_DIR}/auto_tweet_project"
    log "INFO" "auto_tweet_projectディレクトリに移動しました: ${CURRENT_DIR}"
    
    OPTIONS="--max-retries=3"
    if [[ $(date +%H) =~ ^(06|12|18)$ ]]; then
        OPTIONS="$OPTIONS --peak-hour"
        log "INFO" "ピーク時間帯での実行です。--peak-hourオプションを追加します。"
    fi
    
    CMD="${PYTHON_BIN} ${PROJECT_DIR}/manage.py process_tweets ${OPTIONS}"
    log "INFO" "ツイート処理コマンドを実行します: ${CMD}"
    
    # Pythonコマンドを実行し、出力を処理
    cd "${PROJECT_DIR}" && eval "$CMD" 2>&1 | while IFS= read -r line; do
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
                EXIT_CODE=0
            else
                log "ERROR" "再実行も失敗しました (終了コード: ${RETRY_EXIT_CODE})"
            fi
        fi
    fi
    
    schedule_next_wake
    log "INFO" "スクリプトの実行が完了しました"
    
    # 終了前に一時ファイルをクローズ
    exec 3>&- 2>/dev/null
    
    return ${EXIT_CODE}
}

# メイン処理の実行
main "$@"
exit $? 