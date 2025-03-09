#!/bin/bash

# 自動投稿を実行するスクリプト
# シンボリックリンクの実体を解決してディレクトリを取得
SCRIPT_PATH=$(readlink -f "$0")
SCRIPT_DIR=$(dirname "$SCRIPT_PATH")
PROCESS_ID=$$
LOG_DIR="${SCRIPT_DIR}/logs/auto_tweet"
LOG_FILE="${LOG_DIR}/auto_tweet.log"
TIMESTAMP_FILE="${SCRIPT_DIR}/auto_tweet_last_run.txt"
WAKE_SCHEDULE_FILE="${SCRIPT_DIR}/wake_schedule.txt"
LOCK_FILE="${SCRIPT_DIR}/.auto_tweet.lock"

# ロギング用一時ファイル (このプロセスだけの)
TEMP_LOG_FILE="${LOG_DIR}/auto_tweet_${PROCESS_ID}.tmp"

# ログディレクトリが存在しない場合は作成
mkdir -p "${LOG_DIR}"

# 一時ログファイルを作成
echo "$(date '+%Y-%m-%d %H:%M:%S'): [PID:${PROCESS_ID}] ======= 新しいプロセス実行開始 =======" > "${TEMP_LOG_FILE}"

# ロックファイルの確認
if [ -f "$LOCK_FILE" ]; then
    # ロックファイルが存在する場合、実行中のプロセスがあるか確認
    LOCK_PID=$(cat "$LOCK_FILE")
    
    if ps -p $LOCK_PID > /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): [PID:${PROCESS_ID}] 別のauto_tweet.shが実行中（PID: $LOCK_PID）です。処理をスキップします。" >> "${TEMP_LOG_FILE}"
        # ログファイルを追記して終了
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
    # ファイルに直接記録
    echo "$next_time" > "$WAKE_SCHEDULE_FILE"
    log_message "次回実行時刻（pmsetで管理）: $next_time"
    
    # 次の実行時刻をパースして日付と時間に分ける
    local next_date=$(echo "$next_time" | awk '{print $1}')
    local next_time_only=$(echo "$next_time" | awk '{print $2}' | sed 's/:..$//') # 秒を取り除く
    
    # 日付をMM/DD/YY形式に変換（pmsetコマンド用）
    local month=$(date -j -f "%Y-%m-%d" "$next_date" "+%m")
    local day=$(date -j -f "%Y-%m-%d" "$next_date" "+%d")
    local year=$(date -j -f "%Y-%m-%d" "$next_date" "+%y")
    local formatted_date="${month}/${day}/${year}"
    
    log_message "次回の自動起動をスケジュール: $formatted_date $next_time_only"
    
    # 既存のスケジュールをキャンセル（エラー出力は抑制）
    sudo pmset schedule cancelall 2>/dev/null
    
    # 新しいスケジュールを設定
    local pmset_cmd="sudo pmset schedule wake \"$formatted_date $next_time_only\""
    log_message "実行コマンド: $pmset_cmd"
    eval "$pmset_cmd"
    
    # スケジュール設定の成功/失敗をチェック
    if [ $? -eq 0 ]; then
        log_message "次回の自動起動スケジュールが設定されました"
    else
        log_message "エラー: 自動起動スケジュールの設定に失敗しました"
        log_message "解決方法: sudoers設定、パスワード不要設定、pmsetコマンドの構文を確認してください"
    fi
}

# 実行完了後に再びスリープ状態に戻す
sleep_after_execution() {
    log_message "処理が完了しました。システムをスリープに戻します"
    
    # スリープまで少し待機（ログが確実に書き込まれるように）
    log_message "5秒後にスリープします..."
    sleep 5
    
    # システムをスリープ状態に戻す
    pmset sleepnow
}

# 時間を取得
CURRENT_TIME=$(date +%s)
HOUR=$(date +%H)
MINUTE=$(date +%M)
TZ=$(date +%Z)
log_message "実行時刻: ${HOUR}時${MINUTE}分 (タイムゾーン: ${TZ})"

# 前回実行からの時間をチェック
MIN_INTERVAL=5340  # 90分 = 5400秒、ただし1分の余裕を持たせる
SHOULD_RUN=true

if [ -f "$TIMESTAMP_FILE" ]; then
    LAST_RUN=$(cat "$TIMESTAMP_FILE")
    TIME_DIFF=$((CURRENT_TIME - LAST_RUN))
    log_message "前回の実行から${TIME_DIFF}秒経過しています"
    
    if [ $TIME_DIFF -lt $MIN_INTERVAL ]; then
        log_message "前回の実行から90分（余裕を持たせて${MIN_INTERVAL}秒）経過していないため、実行をスキップします"
        SHOULD_RUN=false
    fi
else
    log_message "初回実行または前回実行の記録がありません"
fi

# 実行条件を満たす場合のみ処理を実行
if [ "$SHOULD_RUN" = true ]; then
    # 投稿テキスト
    TEXT="#AI画像 #AIグラビア #AI美女 #AIアイドル #AIphoto #AIphotograpy #AI女子 #AI彼女 #AIart #美女 #美人 #美少女 #aigirls"
    log_message "投稿テキスト: ${TEXT}"

    # 自動投稿コマンドを実行
    cd ../auto_tweet_project
    log_message "auto_tweet_projectディレクトリに移動しました"

    # ピーク時間帯のフラグを設定
    PEAK_HOUR_FLAG=""
    HOUR_NUM=$(date +%H | sed 's/^0//')  # 先頭の0を削除して数値として扱う
    if [ "$HOUR_NUM" -eq 6 ] || [ "$HOUR_NUM" -eq 12 ] || [ "$HOUR_NUM" -eq 18 ]; then
        PEAK_HOUR_FLAG="--peak-hour"
        log_message "現在はピーク時間帯（${HOUR_NUM}時）です。${PEAK_HOUR_FLAG} オプションを追加します。"
    fi

    # 仮想環境のPythonを使用
    PYTHON_BIN="${SCRIPT_DIR}/../.venv/bin/python"
    log_message "Pythonパスを設定: ${PYTHON_BIN}"

    # 自動投稿コマンドを実行
    log_message "自動投稿コマンドを実行します: ${PYTHON_BIN} manage.py auto_post --text \"${TEXT}\" --interval=90 --post-now ${PEAK_HOUR_FLAG}"
    
    # 標準出力と標準エラー出力をキャプチャし、ログファイルに追記
    # 開始前にマーカーを追加
    log_temp "===== Pythonコマンド出力開始 ====="
    
    # コマンド実行（teeを使わず直接ファイルに出力）
    ${PYTHON_BIN} manage.py auto_post --text "${TEXT}" --interval=90 --post-now ${PEAK_HOUR_FLAG} > >(while read line; do log_temp "[STDOUT] $line"; done) 2> >(while read line; do log_temp "[STDERR] $line"; done)
    AUTO_POST_EXIT_CODE=$?
    
    # 終了後にマーカーを追加
    log_temp "===== Pythonコマンド出力終了（終了コード: ${AUTO_POST_EXIT_CODE}） ====="

    if [ ${AUTO_POST_EXIT_CODE} -eq 0 ]; then
        log_message "自動投稿が完了しました"
    else
        log_message "エラー: 自動投稿に失敗しました (終了コード: ${AUTO_POST_EXIT_CODE})"
        
        # レート制限エラーの場合は待機して再試行
        if grep -q "Too Many Requests" "${TEMP_LOG_FILE}" || grep -q "Rate limit exceeded" "${TEMP_LOG_FILE}"; then
            WAIT_TIME=300  # 5分待機
            log_message "レート制限エラーが検出されました。${WAIT_TIME}秒後に再実行します..."
            sleep ${WAIT_TIME}
            
            log_message "再実行中: ${PYTHON_BIN} manage.py auto_post --text \"${TEXT}\" --interval=90 --post-now ${PEAK_HOUR_FLAG}"
            
            # 再試行時もログキャプチャ
            log_temp "===== 再試行コマンド出力開始 ====="
            ${PYTHON_BIN} manage.py auto_post --text "${TEXT}" --interval=90 --post-now ${PEAK_HOUR_FLAG} > >(while read line; do log_temp "[RETRY-STDOUT] $line"; done) 2> >(while read line; do log_temp "[RETRY-STDERR] $line"; done)
            RETRY_EXIT_CODE=$?
            log_temp "===== 再試行コマンド出力終了（終了コード: ${RETRY_EXIT_CODE}） ====="
            
            if [ ${RETRY_EXIT_CODE} -eq 0 ]; then
                log_message "再実行が成功しました"
            else
                log_message "エラー: 再実行も失敗しました (終了コード: ${RETRY_EXIT_CODE})"
            fi
        else
            log_message "エラーの詳細: $(tail -n 20 "${TEMP_LOG_FILE}" | grep -A 5 "Traceback")"
        fi
    fi

    # 最後の実行時刻を更新
    echo "$CURRENT_TIME" > "$TIMESTAMP_FILE"
    log_message "最終実行時刻を更新しました"

    # 次回の自動起動をスケジュール
    schedule_next_wake

    # 夜間の場合はスリープに戻す（22時〜6時の間）
    HOUR_NUM=$(date +%H | sed 's/^0//')  # 先頭の0を削除して数値として扱う
    if [ $HOUR_NUM -ge 22 ] || [ $HOUR_NUM -lt 6 ]; then
        log_message "夜間実行のため、処理完了後にスリープに戻します"
        sleep_after_execution
    fi

else
    # 実行をスキップした場合でも、次回のスケジュールは設定
    log_message "実行をスキップしましたが、次回のスケジュールを設定します"
    schedule_next_wake
fi

log_message "スクリプトの実行が完了しました" 