#!/bin/bash

# 自動投稿を実行するスクリプト
cd "$(dirname "$0")"
SCRIPT_DIR=$(pwd)
LOG_FILE="${SCRIPT_DIR}/auto_post.log"
TIMESTAMP_FILE="${SCRIPT_DIR}/auto_tweet_last_run.txt"
WAKE_SCHEDULE_FILE="${SCRIPT_DIR}/wake_schedule.txt"
LOCK_FILE="${SCRIPT_DIR}/.auto_tweet.lock"

# ロックファイルの確認
if [ -f "$LOCK_FILE" ]; then
    # ロックファイルが存在する場合、実行中のプロセスがあるか確認
    LOCK_PID=$(cat "$LOCK_FILE")
    
    if ps -p $LOCK_PID > /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): 別のauto_tweet.shが実行中（PID: $LOCK_PID）です。処理をスキップします。" >> "${LOG_FILE}"
        exit 0
    else
        # プロセスが存在しない場合は古いロックファイルなので削除
        echo "$(date '+%Y-%m-%d %H:%M:%S'): 古いロックファイルを削除します。" >> "${LOG_FILE}"
        rm -f "$LOCK_FILE"
    fi
fi

# 新しいロックファイルを作成
echo $$ > "$LOCK_FILE"

# スクリプト終了時にロックファイルを自動的に削除する関数
cleanup() {
    rm -f "$LOCK_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): ロックファイルを削除しました。" >> "${LOG_FILE}"
}

# スクリプト終了時またはエラー時にクリーンアップ関数を実行
trap cleanup EXIT

# ログ出力関数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1" >> "${LOG_FILE}"
    echo "$(date '+%Y-%m-%d %H:%M:%S'): $1"
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
    
    # 日付と時間を分解
    local next_date_part=$(echo "$next_time" | cut -d' ' -f1)
    local next_time_part=$(echo "$next_time" | cut -d' ' -f2)
    
    # 日付をMM/DD/YY形式に変換
    local month=$(echo "$next_date_part" | cut -d'-' -f2)
    local day=$(echo "$next_date_part" | cut -d'-' -f3)
    local year=$(echo "$next_date_part" | cut -d'-' -f1 | cut -c3-4)  # 下2桁のみ
    
    # pmsetコマンドの日付・時間形式に合わせる
    local formatted_datetime="${month}/${day}/${year} ${next_time_part}"
    
    log_message "次回実行時刻をスケジュールします: $next_time (${formatted_datetime})"
    
    # 既存のwakeスケジュールをクリア（エラー出力を抑制）
    sudo pmset schedule cancelall > /dev/null 2>&1 || log_message "スケジュールのクリアに失敗しました（無視して続行）"
    
    # 新しいwakeスケジュールを設定
    log_message "実行コマンド: sudo pmset schedule wake \"${formatted_datetime}\""
    sudo pmset schedule wake "${formatted_datetime}" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        log_message "次回の自動起動スケジュールを設定しました: ${formatted_datetime}"
        echo "$next_time" > "$WAKE_SCHEDULE_FILE"
    else
        log_message "警告: 自動起動スケジュールの設定に失敗しました。以下の点を確認してください:"
        log_message "1. sudoers設定: sudo visudo -f /etc/sudoers.d/pmset で確認"
        log_message "2. 権限設定: システム環境設定 > セキュリティとプライバシー > フルディスクアクセス"
        log_message "3. pmsetコマンド構文: pmsetコマンドの使い方は'man pmset'で確認できます"
        # スケジュール設定失敗のログを残すが処理は続行
    fi
}

# 実行完了後に再びスリープ状態に戻す
sleep_after_execution() {
    log_message "処理が完了しました。5分後にスリープに戻ります..."
    
    # 5分後にスリープ
    sleep 300 && sudo pmset sleepnow > /dev/null 2>&1 &
    
    log_message "スリープのスケジュールを設定しました"
}

# 現在の時間を取得
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
    # 仮想環境をアクティベート
    source .venv/bin/activate
    log_message "仮想環境をアクティベートしました"

    # 投稿テキスト
    TEXT="投稿テキスト"
    log_message "投稿テキスト: ${TEXT}"

    # 自動投稿コマンドを実行
    cd auto_tweet_project
    log_message "auto_tweet_projectディレクトリに移動しました"

    # ピーク時間帯のフラグを設定
    PEAK_HOUR_FLAG=""
    HOUR_NUM=$(date +%H | sed 's/^0//')  # 先頭の0を削除して数値として扱う
    if [ "$HOUR_NUM" -eq 6 ] || [ "$HOUR_NUM" -eq 12 ] || [ "$HOUR_NUM" -eq 18 ]; then
        PEAK_HOUR_FLAG="--peak-hour"
        log_message "現在はピーク時間帯（${HOUR_NUM}時）です。${PEAK_HOUR_FLAG} オプションを追加します。"
    fi

    # 自動投稿コマンドを実行
    log_message "自動投稿コマンドを実行します: python manage.py auto_post --text \"${TEXT}\" --interval=90 --post-now ${PEAK_HOUR_FLAG}"
    python manage.py auto_post --text "${TEXT}" --interval=90 --post-now ${PEAK_HOUR_FLAG} 2>&1 | tee -a "${LOG_FILE}"
    AUTO_POST_EXIT_CODE=${PIPESTATUS[0]}

    if [ ${AUTO_POST_EXIT_CODE} -eq 0 ]; then
        log_message "自動投稿が完了しました"
    else
        log_message "エラー: 自動投稿に失敗しました (終了コード: ${AUTO_POST_EXIT_CODE})"
        
        # レート制限エラーの場合は待機して再試行
        if grep -q "Too Many Requests" "${LOG_FILE}" || grep -q "Rate limit exceeded" "${LOG_FILE}"; then
            WAIT_TIME=300  # 5分待機
            log_message "レート制限エラーが検出されました。${WAIT_TIME}秒後に再実行します..."
            sleep ${WAIT_TIME}
            
            log_message "再実行中: python manage.py auto_post --text \"${TEXT}\" --interval=90 --post-now ${PEAK_HOUR_FLAG}"
            python manage.py auto_post --text "${TEXT}" --interval=90 --post-now ${PEAK_HOUR_FLAG} 2>&1 | tee -a "${LOG_FILE}"
            RETRY_EXIT_CODE=${PIPESTATUS[0]}
            
            if [ ${RETRY_EXIT_CODE} -eq 0 ]; then
                log_message "再実行が成功しました"
            else
                log_message "エラー: 再実行も失敗しました (終了コード: ${RETRY_EXIT_CODE})"
            fi
        else
            log_message "エラーの詳細: $(tail -n 20 "${LOG_FILE}" | grep -A 5 "Traceback")"
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