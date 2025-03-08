#!/usr/bin/env python
"""
スケジューラーセットアップスクリプト
定期的にツイートを処理するためのcronジョブを設定します
"""

import os
import sys
from crontab import CronTab
from pathlib import Path

def setup_cron():
    """cronジョブを設定する"""
    # プロジェクトのパスを取得
    project_path = Path(__file__).resolve().parent
    python_path = sys.executable
    
    print(f"プロジェクトパス: {project_path}")
    print(f"Pythonパス: {python_path}")
    
    # 現在のユーザーのcrontabを取得
    cron = CronTab(user=True)
    
    # 既存のジョブをクリア（同じコメントを持つもの）
    cron.remove_all(comment='auto_tweet_scheduler')
    
    # 1分ごとにジョブを実行するように設定
    job = cron.new(command=f'cd {project_path} && {python_path} manage.py process_tweets',
                   comment='auto_tweet_scheduler')
    job.minute.every(1)
    
    # crontabに書き込む
    cron.write()
    
    print("スケジューラーが正常に設定されました。")
    print("1分ごとに保留中のツイートをチェックして処理します。")

if __name__ == '__main__':
    setup_cron() 