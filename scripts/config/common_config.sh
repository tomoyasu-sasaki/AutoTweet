#!/bin/bash

# === シェルスクリプト共通設定 ===

# --- パス設定 ---
# この設定ファイルがあるディレクトリ
CONFIG_DIR=$(dirname "$(readlink -f "$0")")
# scripts ディレクトリ
SCRIPTS_DIR=$(dirname "$CONFIG_DIR")
# プロジェクトルートディレクトリ (scripts ディレクトリの親)
PROJECT_ROOT_DIR=$(dirname "$SCRIPTS_DIR")

# ログディレクトリ (プロジェクトルートからの相対パス)
# 各スクリプトで固有のサブディレクトリを使う場合は、このパスをベースに組み立てる
COMMON_LOG_BASE_DIR_RELATIVE="scripts/logs"
COMMON_LOG_BASE_DIR="${PROJECT_ROOT_DIR}/${COMMON_LOG_BASE_DIR_RELATIVE}"

# Python 仮想環境のパス (プロジェクトルートからの相対パス)
PYTHON_VENV_RELATIVE=".venv"
PYTHON_BIN="${PROJECT_ROOT_DIR}/${PYTHON_VENV_RELATIVE}/bin/python"

# Django プロジェクトディレクトリ (プロジェクトルートからの相対パス)
DJANGO_PROJECT_RELATIVE="auto_tweet_project"
PROJECT_DIR="${PROJECT_ROOT_DIR}/${DJANGO_PROJECT_RELATIVE}"

# --- 実行設定 ---
# デフォルトのツイートテキスト
DEFAULT_TWEET_TEXT="投稿テキスト"

# 投稿間隔（分）
POST_INTERVAL_MINUTES=90
# 投稿間隔（秒） - launchd版での比較用 (マージン考慮)
POST_INTERVAL_SECONDS=$((POST_INTERVAL_MINUTES * 60 - 60)) # 90分 = 5400秒 -> 5340秒

# ピーク時間帯（カンマ区切り）- 判定は各スクリプトで行う
PEAK_HOURS="06,12,18"

# 夜間スリープ開始時間 (0-23)
SLEEP_START_HOUR=22
# 夜間スリープ終了時間 (0-23)
SLEEP_END_HOUR=6

# --- リトライ設定 (pmset版で主に使用) ---
# コマンド実行リトライ回数
RETRY_COUNT=3
# リトライ間隔（秒）
RETRY_INTERVAL_SECONDS=30

# --- レート制限リトライ設定 (launchd版で使用) ---
RATE_LIMIT_RETRY_WAIT_SECONDS=300 # 5分

# --- その他 ---
# 必要に応じて他の共通設定を追加

# 設定読み込み確認用 (デバッグ時にコメント解除)
# echo "Common config loaded from: ${CONFIG_DIR}"
# echo "Project root: ${PROJECT_ROOT_DIR}"
# echo "Log base dir: ${COMMON_LOG_BASE_DIR}"
# echo "Python bin: ${PYTHON_BIN}"
# echo "Django project dir: ${PROJECT_DIR}" 