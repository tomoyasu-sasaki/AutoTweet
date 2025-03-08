#!/bin/bash

# スケジュールされたツイートを処理するスクリプト
cd "$(dirname "$0")"
SCRIPT_DIR=$(pwd)
LOG_FILE="${SCRIPT_DIR}/process_tweets.log"
WAKE_SCHEDULE_FILE="${SCRIPT_DIR}/process_wake_schedule.txt"
LOCK_FILE="${SCRIPT_DIR}/.process_tweets.lock"

# ロックファイルの確認
if [ -f "$LOCK_FILE" ]; then
    # ロックファイルが存在する場合、実行中のプロセスがあるか確認
    LOCK_PID=$(cat "$LOCK_FILE")
    
    if ps -p $LOCK_PID > /dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S'): 別のprocess_tweets.shが実行中（PID: $LOCK_PID）です。処理をスキップします。" >> "${LOG_FILE}"
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
    
    # 日付と時間を分解
    local next_date_part=$(echo "$next_time" | cut -d' ' -f1)
    local next_time_part=$(echo "$next_time" | cut -d' ' -f2)
    
    # 日付をMM/DD/YY形式に変換
    local month=$(echo "$next_date_part" | cut -d'-' -f2)
    local day=$(echo "$next_date_part" | cut -d'-' -f3)
    local year=$(echo "$next_date_part" | cut -d'-' -f1 | cut -c3-4)  # 下2桁のみ
    
    # pmsetコマンドの日付・時間形式に合わせる
    local formatted_datetime="${month}/${day}/${year} ${next_time_part}"
    
    log_message "次回処理時刻をスケジュールします: $next_time (${formatted_datetime})"
    
    # 既存のwakeスケジュールをクリア（エラー出力を抑制）
    sudo pmset schedule cancelall > /dev/null 2>&1
    
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

# 実行完了後に再びスリープ状態に戻す（夜間のみ）
sleep_after_execution() {
    log_message "処理が完了しました。3分後にスリープに戻ります..."
    
    # 3分後にスリープ
    sleep 180 && sudo pmset sleepnow > /dev/null 2>&1 &
    
    log_message "スリープのスケジュールを設定しました"
}

# 仮想環境をアクティベート
source .venv/bin/activate
log_message "仮想環境をアクティベートしました"

# 現在の時間を取得
CURRENT_TIME=$(date '+%Y-%m-%d %H:%M:%S')
CURRENT_HOUR=$(date +%H)
log_message "処理開始時刻: ${CURRENT_TIME}"

# auto_tweet_projectディレクトリに移動
cd auto_tweet_project
log_message "auto_tweet_projectディレクトリに移動しました"

# Pythonコードにすべての判断を委ねるためのオプション設定
# 現在の時間に応じたオプションの設定（ピーク時間帯の判定）
OPTIONS="--max-retries=3"
if [ "$CURRENT_HOUR" = "06" ] || [ "$CURRENT_HOUR" = "12" ] || [ "$CURRENT_HOUR" = "18" ]; then
    OPTIONS="$OPTIONS --peak-hour"
    log_message "ピーク時間帯での実行です。--peak-hourオプションを追加します。"
fi

# ツイート処理コマンドを実行
log_message "ツイート処理コマンドを実行します: python manage.py process_tweets ${OPTIONS}"
python manage.py process_tweets ${OPTIONS} 2>&1 | tee -a "${LOG_FILE}"
EXIT_CODE=${PIPESTATUS[0]}

if [ ${EXIT_CODE} -eq 0 ]; then
    log_message "ツイート処理が完了しました"
else
    log_message "エラー: ツイート処理に失敗しました (終了コード: ${EXIT_CODE})"
    
    # エラーが発生した場合、一定時間後に再実行（レート制限対策）
    if grep -q "Too Many Requests" "${LOG_FILE}"; then
        WAIT_TIME=300  # 5分待機
        log_message "レート制限エラーが検出されました。${WAIT_TIME}秒後に再実行します..."
        sleep ${WAIT_TIME}
        
        log_message "再実行中: python manage.py process_tweets --skip-api-test"
        python manage.py process_tweets --skip-api-test 2>&1 | tee -a "${LOG_FILE}"
        RETRY_EXIT_CODE=${PIPESTATUS[0]}
        
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