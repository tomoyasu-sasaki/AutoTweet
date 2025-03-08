#!/bin/bash

# 仮想環境をアクティベート
source .venv/bin/activate

# auto_tweet_projectディレクトリに移動してサーバーを起動
cd auto_tweet_project && python manage.py runserver 