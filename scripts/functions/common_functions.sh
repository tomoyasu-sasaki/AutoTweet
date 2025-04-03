#!/bin/bash

# === シェルスクリプト共通関数 ===

# --- ログ出力関数 ---
# Usage: log <LEVEL> "<message>"
# LEVEL: INFO, WARN, ERROR など任意の文字列
# message: ログに出力するメッセージ
log() {
    local level="${1:-INFO}" # デフォルトレベルをINFOに
    local message="${2}"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S') # SC2155 修正: 宣言と代入を分離

    # 引数が不足している場合の警告
    if [[ -z "$message" ]]; then
        message="$level" # メッセージがない場合はレベルをメッセージとする
        level="WARN"   # レベルをWARNにする
        echo "${timestamp}: [PID:${PROCESS_ID:-$$}] [${level}] log関数にメッセージが指定されていません。" | tee -a "${TEMP_LOG_FILE:-/dev/null}"
    fi

    # 想定される一時ログファイルに変数が設定されているか確認
    if [[ -z "${TEMP_LOG_FILE}" ]]; then
        echo "${timestamp}: [PID:${PROCESS_ID:-$$}] [ERROR] TEMP_LOG_FILE変数が設定されていません。ログ出力に失敗しました。" >&2
        return 1
    fi

    # ログメッセージを標準出力と一時ログファイルに出力
    echo "${timestamp}: [PID:${PROCESS_ID:-$$}] [${level}] ${message}" | tee -a "${TEMP_LOG_FILE}"
}

# --- クリーンアップ関数 ---
# スクリプト終了時に呼び出される想定 (trap)
# - ロックファイルの削除
# - caffeinate プロセスの終了 (pmset版)
# - 一時ログファイルの内容をメインログファイルに追記・削除
common_cleanup() {
    # ロックファイルが存在すれば削除
    if [[ -n "${LOCK_FILE}" && -f "${LOCK_FILE}" ]]; then
        rm -f "${LOCK_FILE}"
        log "DEBUG" "ロックファイルを削除しました: ${LOCK_FILE}" # クリーンアップ時のログは DEBUG レベルに
    fi

    # caffeinate プロセスIDがあれば終了 (pmset版)
    # 変数がセットされていて、かつ空でない場合
    if [[ -n "${CAFFEINATE_PID:-}" ]]; then # 変数が未定義の場合も考慮
        kill "${CAFFEINATE_PID}" 2>/dev/null
        log "DEBUG" "caffeinateプロセス (PID: ${CAFFEINATE_PID}) を終了しました。"
    fi

    # 一時ログファイルが存在すればメインログに追記して削除
    if [[ -n "${TEMP_LOG_FILE:-}" && -f "${TEMP_LOG_FILE}" ]]; then # 変数が未定義の場合も考慮
        if [[ -n "${LOG_FILE:-}" ]]; then # 変数が未定義の場合も考慮
            # SC2015 修正: if/then/else を使用
            if awk '!seen[$0]++' "${TEMP_LOG_FILE}" >> "${LOG_FILE}"; then
                log "DEBUG" "一時ログをメインログに追記しました: ${LOG_FILE}"
            else
                log "ERROR" "一時ログのメインログへの追記に失敗しました: ${LOG_FILE}"
            fi
        else
            log "WARN" "LOG_FILE変数が設定されていないため、一時ログは追記されずに削除されます。"
        fi
        rm -f "${TEMP_LOG_FILE}"
    fi
}

# --- ロックファイルチェック関数 ---
# Usage: check_lock "スクリプト名"
# スクリプト名: ログ出力用
check_lock() {
    # SC2086 修正: $0 をダブルクォートで囲む
    local script_name="${1:-$(basename "$0")}" # スクリプト名がなければ実行ファイル名

    # LOCK_FILE 変数が設定されているか確認
    if [[ -z "${LOCK_FILE:-}" ]]; then # 変数が未定義の場合も考慮
        log "ERROR" "LOCK_FILE変数が設定されていません。ロックチェックを実行できません。"
        return 1 # エラーとして返す
    fi

    if [[ -f "${LOCK_FILE}" ]]; then
        local lock_pid
        lock_pid=$(cat "${LOCK_FILE}") # SC2155 修正: 宣言と代入を分離
        # PIDが数字であるか基本的なチェック
        if [[ "$lock_pid" =~ ^[0-9]+$ ]] && ps -p "${lock_pid}" > /dev/null; then
            log "WARN" "別の${script_name}が実行中（PID: ${lock_pid}）のため処理をスキップします。"
            # trap で cleanup が呼ばれるように exit 0 で正常終了させる
            exit 0
        else
            log "WARN" "古いロックファイルを削除します: ${LOCK_FILE}"
            rm -f "${LOCK_FILE}"
        fi
    fi

    # 新しいロックファイルを作成
    # PROCESS_ID 変数が設定されているか確認
    if [[ -z "${PROCESS_ID:-}" ]]; then # 変数が未定義の場合も考慮
        log "ERROR" "PROCESS_ID変数が設定されていません。ロックファイルを作成できません。"
        return 1
    fi
    echo "${PROCESS_ID}" > "${LOCK_FILE}"
    log "DEBUG" "ロックファイルを作成しました: ${LOCK_FILE} (PID: ${PROCESS_ID})"
    return 0 # 正常にロック獲得
}

# --- その他の共通関数 --- 
# 必要に応じて追加

# 現在時刻に基づき、ピーク時間帯フラグオプションを決定する
# Usage: local peak_option=$(determine_peak_hour_flag_option)
# Returns: " --peak-hour" or ""
determine_peak_hour_flag_option() {
    # PEAK_HOURS が設定されていなければ空を返す
    if [[ -z "${PEAK_HOURS:-}" ]]; then
        echo ""
        return
    fi

    local current_hour
    current_hour=$(date +%H) # SC2155: declare and assign separately
    local peak_flag_option=""

    # カンマ区切りの PEAK_HOURS をチェック (例: "06,12,18")
    # 前後にカンマを追加して完全一致を確認 (例: ",06,12,18,")
    if [[ ",${PEAK_HOURS}," == *",${current_hour},"* ]]; then
        peak_flag_option=" --peak-hour" # 先頭にスペースを含める
        log "INFO" "ピーク時間帯(${current_hour}時)のため、'${peak_flag_option}' オプションを追加します。"
    fi
    echo "$peak_flag_option"
}

# manage.py process_tweets コマンドを実行し、レート制限時には再試行する
# Usage: execute_process_tweets_command "<options>"
# Returns: 0 on success, non-zero on failure
execute_process_tweets_command() {
    local options="$1"
    local cmd="${PYTHON_BIN} manage.py process_tweets ${options}"
    local success=false
    local exit_code

    log "INFO" "ツイート処理コマンドを実行します: ${cmd}"
    log "DEBUG" "===== Pythonコマンド(process_tweets)出力開始 ====="

    # 初回実行
    if output=$(cd "${PROJECT_DIR}" && eval "$cmd" 2>&1); then
        exit_code=0
        log "INFO" "ツイート処理が完了しました"
        while IFS= read -r line; do log "DEBUG" "[Python Output] $line"; done <<< "$output"
        success=true
    else
        exit_code=$?
        log "ERROR" "エラー: ツイート処理に失敗しました (終了コード: ${exit_code})"
        while IFS= read -r line; do log "DEBUG" "[Python Output/Error] $line"; done <<< "$output"

        # レート制限エラーの場合のみ再試行
        if grep -qi "Too Many Requests" <<< "$output" || grep -qi "Rate limit exceeded" <<< "$output"; then
            log "WARN" "レート制限エラーが検出されました。${RATE_LIMIT_RETRY_WAIT_SECONDS}秒後に再実行します..."
            sleep "${RATE_LIMIT_RETRY_WAIT_SECONDS}"

            # 再試行時は --skip-api-test オプションを追加
            # 元のオプションに既に含まれている可能性も考慮
            local retry_options="${options}"
            if ! grep -q -- '--skip-api-test' <<< "${options}"; then
                 retry_options="${options} --skip-api-test"
            fi
            local retry_cmd="${PYTHON_BIN} manage.py process_tweets ${retry_options}"
            log "INFO" "再実行中: ${retry_cmd}"
            log "DEBUG" "===== 再試行コマンド出力開始 ====="

            if retry_output=$(cd "${PROJECT_DIR}" && eval "$retry_cmd" 2>&1); then
                local retry_exit_code=0
                log "INFO" "再実行が成功しました"
                while IFS= read -r line; do log "DEBUG" "[Python Retry Output] $line"; done <<< "$retry_output"
                success=true # 再試行成功
            else
                local retry_exit_code=$?
                log "ERROR" "エラー: 再実行も失敗しました (終了コード: ${retry_exit_code})"
                while IFS= read -r line; do log "DEBUG" "[Python Retry Output/Error] $line"; done <<< "$retry_output"
            fi
            log "DEBUG" "===== 再試行コマンド出力終了（終了コード: ${retry_exit_code:-$exit_code}） ====="
        else
             log "WARN" "レート制限以外のエラーのため再試行しません。"
        fi
    fi
    log "DEBUG" "===== Pythonコマンド(process_tweets)出力終了（初回終了コード: ${exit_code}） ====="

    if $success; then
        return 0
    else
        return 1
    fi
}

# manage.py auto_post コマンドを実行し、レート制限時には再試行する
# Usage: execute_auto_post_command "<peak_hour_option>"
# Returns: 0 on success, non-zero on failure
execute_auto_post_command() {
    local peak_hour_option="$1" # " --peak-hour" or ""
    local success=false
    local exit_code

    # コマンドと引数を配列で準備
    local cmd_array=(
        "${PYTHON_BIN}" \
        manage.py \
        auto_post \
        --text \
        "${DEFAULT_TWEET_TEXT}" \
        --interval="${POST_INTERVAL_MINUTES}" \
        --post-now
    )
    # ピーク時間オプションを追加 (スペースは不要)
    if [[ -n "$peak_hour_option" ]]; then
        cmd_array+=(--peak-hour)
    fi

    log "INFO" "自動投稿コマンドを実行します: ${cmd_array[*]}" # 配列の内容を表示
    log "DEBUG" "===== Pythonコマンド(auto_post)出力開始 ====="

    # 初回実行 (eval を使わず直接実行)
    if output=$(cd "${PROJECT_DIR}" && "${cmd_array[@]}" 2>&1); then
        exit_code=0
        log "INFO" "自動投稿が完了しました"
        while IFS= read -r line; do log "DEBUG" "[Python Output] $line"; done <<< "$output"
        success=true
    else
        exit_code=$?
        log "ERROR" "エラー: 自動投稿に失敗しました (終了コード: ${exit_code})"
        while IFS= read -r line; do log "DEBUG" "[Python Output/Error] $line"; done <<< "$output"

        # レート制限エラーの場合のみ再試行
        if grep -qi "Too Many Requests" <<< "$output" || grep -qi "Rate limit exceeded" <<< "$output"; then
            log "WARN" "レート制限エラーが検出されました。${RATE_LIMIT_RETRY_WAIT_SECONDS}秒後に再実行します..."
            sleep "${RATE_LIMIT_RETRY_WAIT_SECONDS}"

            log "INFO" "再実行中: ${cmd_array[*]}"
            log "DEBUG" "===== 再試行コマンド出力開始 ====="

            if retry_output=$(cd "${PROJECT_DIR}" && "${cmd_array[@]}" 2>&1); then
                local retry_exit_code=0
                log "INFO" "再実行が成功しました"
                while IFS= read -r line; do log "DEBUG" "[Python Retry Output] $line"; done <<< "$retry_output"
                success=true # 再試行成功
            else
                local retry_exit_code=$?
                log "ERROR" "エラー: 再実行も失敗しました (終了コード: ${retry_exit_code})"
                while IFS= read -r line; do log "DEBUG" "[Python Retry Output/Error] $line"; done <<< "$retry_output"
            fi
            log "DEBUG" "===== 再試行コマンド出力終了（終了コード: ${retry_exit_code:-$exit_code}） ====="
        else
            # pmset版にあった単純リトライは削除し、レート制限以外は再試行しない
            log "WARN" "レート制限以外のエラーのため再試行しません。"
        fi
    fi
    log "DEBUG" "===== Pythonコマンド(auto_post)出力終了（初回終了コード: ${exit_code}） ====="

    if $success; then
        return 0
    else
        return 1
    fi
}

# 前回実行からの経過時間をチェックし、実行すべきか判断する
# Usage: check_execution_interval "$@" # スクリプト引数を渡す
# Returns: 0 if execution should proceed, 1 otherwise (skip)
check_execution_interval() {
    # テストモードのチェック
    if [[ "${1:-}" == "--test" ]]; then # 変数未定義を考慮
        log "INFO" "テストモードのため実行間隔チェックをスキップ"
        return 0 # 実行する
    fi

    local current_time
    current_time=$(date +%s)
    local last_run
    # 最終実行時刻ファイルが存在しないか読めない場合は0とする
    if ! last_run=$(cat "${TIMESTAMP_FILE:-/dev/null}" 2>/dev/null); then
        log "INFO" "最終実行時刻ファイルが見つからないか、空です。初回実行とみなします。"
        last_run=0
    fi

    # 最終実行時刻が数字でない場合は警告して0とする
    if ! [[ "$last_run" =~ ^[0-9]+$ ]]; then
        log "WARN" "最終実行時刻ファイルの内容が不正です: $last_run。初回実行とみなします。"
        last_run=0
    fi

    local time_diff=$((current_time - last_run))

    # 経過時間チェック
    if (( time_diff < POST_INTERVAL_SECONDS )); then
        log "INFO" "${POST_INTERVAL_MINUTES}分未経過のためスキップ (前回実行: $(date -r "${last_run}" '+%Y-%m-%d %H:%M:%S'), 経過: ${time_diff}秒)"
        # schedule_next_wake # スキップ時もスケジュールするかは呼び出し元で判断
        return 1 # スキップ
    else
        log "INFO" "実行間隔 (${POST_INTERVAL_MINUTES}分) クリア (前回実行からの経過時間: ${time_diff}秒)"
        return 0 # 実行する
    fi
} 