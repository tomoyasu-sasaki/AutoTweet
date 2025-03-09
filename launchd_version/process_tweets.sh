#!/bin/bash

# スケジュールされたツイートを処理するスクリプト
# シンボリックリンクの実体を解決してディレクトリを取得
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROCESS_ID=$$
LOG_DIR="${SCRIPT_DIR}/logs/process_tweets"
LOG_FILE="${LOG_DIR}/process_tweets.log"
# WAKE_SCHEDULE_FILE="${SCRIPT_DIR}/process_wake_schedule.txt" # 不要なので削除
LOCK_FILE="${SCRIPT_DIR}/.process_tweets.lock"

# ロギング用一時ファイル (このプロセスだけの)
TEMP_LOG_FILE="${LOG_DIR}/process_tweets_${PROCESS_ID}.tmp"

# ログディレクトリが存在しない場合は作成
mkdir -p "${LOG_DIR}"

# 一時ログファイルを作成
echo "$(date '+%Y-%m-%d %H:%M:%S'): [PID:${PROCESS_ID}] ======= 新しいプロセス実行開始 =======" > "${TEMP_LOG_FILE}"

# ロックファイルの確認
if [ -f "$LOCK_FILE" ]; then
    # ロックファイルが存在する場合、実行中のプロセスがあるか確認
    LOCK_PID=$(cat "$LOCK_FILE")
    
    if ps -p $LOCK_PID > /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): [PID:${PROCESS_ID}] 別のprocess_tweets.shが実行中（PID: $LOCK_PID）です。処理をスキップします。" >> "${TEMP_LOG_FILE}"
        # ロックファイルを追記して終了
        cat "${TEMP_LOG_FILE}" >> "${LOG_FILE}"
        rm -f "${TEMP_LOG_FILE}"
        exit 0
    else
        # プロセスが存在しない場合は古いロックファイルなので削除
        echo "$(date '+%Y-%m-%d %H:%M:%S'): [PID:${PROCESS_ID}] 古いロックファイルを削除します。" >> "${TEMP_LOG_FILE}"
        rm -f "$LOCK_FILE"
    fi
fi

# 新しいロックファイルを作成
echo $PROCESS_ID > "$LOCK_FILE"

# スクリプト終了時にロックファイルを自動的に削除する関数
cleanup() {
    rm -f "$LOCK_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): [PID:${PROCESS_ID}] ロックファイルを削除しました。" >> "${TEMP_LOG_FILE}"
    
    # スクリプト終了時に一時ログをメインログに追記してから削除
    cat "${TEMP_LOG_FILE}" >> "${LOG_FILE}"
    rm -f "${TEMP_LOG_FILE}"
}

# スクリプト終了時またはエラー時にクリーンアップ関数を実行
trap cleanup EXIT

# ログ出力関数 - 一時ファイルのみに出力
log_temp() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): [PID:${PROCESS_ID}] $1" >> "${TEMP_LOG_FILE}"
}

# ログ出力関数 - 標準出力と一時ファイルの両方に出力
log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # 標準出力と一時ファイルに出力
    echo "${timestamp}: [PID:${PROCESS_ID}] $1" | tee -a "${TEMP_LOG_FILE}"
}

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
    # 不要なファイル書き込みをコメントアウト
    # echo "$next_time" > "$WAKE_SCHEDULE_FILE"
    log_message "次回処理時刻（launchdで管理）: $next_time"
    log_message "次回の自動起動はlaunchdが管理します"
}

# 実行完了後に再びスリープ状態に戻す（夜間のみ）
sleep_after_execution() {
    log_message "処理が完了しました"
}

# 仮想環境のPythonを使用
PYTHON_BIN="${SCRIPT_DIR}/../.venv/bin/python"
log_message "Pythonパスを設定: ${PYTHON_BIN}"

# 現在の時間を取得
CURRENT_TIME_STR=$(date '+%Y-%m-%d %H:%M:%S')
CURRENT_HOUR=$(date +%H)
log_message "処理開始時刻: ${CURRENT_TIME_STR}"

# auto_tweet_projectディレクトリに移動
cd ../auto_tweet_project
log_message "auto_tweet_projectディレクトリに移動しました"

# Pythonコードにすべての判断を委ねるためのオプション設定
# 現在の時間に応じたオプションの設定（ピーク時間帯の判定）
OPTIONS="--max-retries=3"
if [ "$CURRENT_HOUR" = "06" ] || [ "$CURRENT_HOUR" = "12" ] || [ "$CURRENT_HOUR" = "18" ]; then
    OPTIONS="$OPTIONS --peak-hour"
    log_message "ピーク時間帯での実行です。--peak-hourオプションを追加します。"
fi

# ツイート処理コマンドを実行
log_message "ツイート処理コマンドを実行します: ${PYTHON_BIN} manage.py process_tweets ${OPTIONS}"

# 標準出力と標準エラー出力をキャプチャし、ログファイルに追記
# 開始前にマーカーを追加
log_temp "===== Pythonコマンド出力開始 ====="

# コマンド実行（ファイルパスを一時ファイルに絶対パスで指定）
${PYTHON_BIN} manage.py process_tweets ${OPTIONS} > >(while read line; do log_temp "[STDOUT] $line"; done) 2> >(while read line; do log_temp "[STDERR] $line"; done)
EXIT_CODE=$?

# 終了後にマーカーを追加
log_temp "===== Pythonコマンド出力終了（終了コード: ${EXIT_CODE}） ====="

if [ ${EXIT_CODE} -eq 0 ]; then
    log_message "ツイート処理が完了しました"
else
    log_message "エラー: ツイート処理に失敗しました (終了コード: ${EXIT_CODE})"
    
    # エラーが発生した場合、一定時間後に再実行（レート制限対策）
    if grep -q "Too Many Requests" "${TEMP_LOG_FILE}"; then
        WAIT_TIME=300  # 5分待機
        log_message "レート制限エラーが検出されました。${WAIT_TIME}秒後に再実行します..."
        sleep ${WAIT_TIME}
        
        log_message "再実行中: ${PYTHON_BIN} manage.py process_tweets --skip-api-test"
        
        # 再試行時もログキャプチャ
        log_temp "===== 再試行コマンド出力開始 ====="
        ${PYTHON_BIN} manage.py process_tweets --skip-api-test > >(while read line; do log_temp "[RETRY-STDOUT] $line"; done) 2> >(while read line; do log_temp "[RETRY-STDERR] $line"; done)
        RETRY_EXIT_CODE=$?
        log_temp "===== 再試行コマンド出力終了（終了コード: ${RETRY_EXIT_CODE}） ====="
        
        if [ ${RETRY_EXIT_CODE} -eq 0 ]; then
            log_message "再実行が成功しました"
        else
            log_message "エラー: 再実行も失敗しました (終了コード: ${RETRY_EXIT_CODE})"
        fi
    fi
fi

# 次回の自動起動をスケジュール
schedule_next_wake

# 夜間の場合はスリープに戻す（22時〜6時の間）
CURRENT_HOUR=$(date +%H | sed 's/^0//')  # 先頭の0を削除
if [ $CURRENT_HOUR -ge 22 ] || [ $CURRENT_HOUR -lt 6 ]; then
    log_message "夜間実行のため、処理完了後にスリープに戻します"
    sleep_after_execution
fi

log_message "スクリプトの実行が完了しました" 