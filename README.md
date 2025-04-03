# X API 自動投稿システム

<!-- 目次 (Table of Contents) -->
## 📚 目次

- [概要](#-概要)
- [主な機能](#-主な機能)
- [使用技術](#-使用技術)
- [ファイル構造](#-ファイル構造)
- [コンポーネント説明](#-コンポーネント説明)
- [インストールと設定](#-インストールと設定)
  - [X Developer Portalでの設定](#1-x-developer-portalでの設定)
  - [システムのインストール](#2-システムのインストール)
- [macOSでの自動実行設定](#-macosでの自動実行設定)
  - [実行モードについて (launchd vs cron+pmset)](#実行モードについて-launchd-vs-cronpmset)
  - [モードの切り替え方法 (`switch_version.sh`)](#モードの切り替え方法-switch_versionsh)
  - [Launchd モード設定手順](#launchd-モード設定手順)
  - [Cron + PMSet モード設定手順](#cron--pmset-モード設定手順)
- [Linux環境での自動実行設定 (参考)](#linux環境での自動実行設定-参考)
- [使用方法](#-使用方法)
- [設定パラメータ](#️-設定パラメータ)
- [トラブルシューティング](#-トラブルシューティング)
- [開発者向け情報](#-開発者向け情報)
- [セキュリティ考慮事項](#-セキュリティ考慮事項)
- [バージョン履歴](#-バージョン履歴)
- [ライセンス](#-ライセンス)
- [連絡先・サポート](#-連絡先サポート)

---

## 📋 概要

本システムは、指定されたテキストを定期的にX（旧Twitter）へ自動投稿するためのツールです。DjangoフレームワークとTweepy（X API SDK）を使用し、安定した投稿スケジュール管理とAPIレート制限の管理を行います。

特にmacOS環境向けに、2つの自動実行モードを提供します:
1.  **Launchd モード**: Macが起動中（スリープしていない状態）にのみ実行されます。
2.  **Cron + PMSet モード**: Cronで定期実行をトリガーし、スクリプト内で `pmset` を使用してMacのスリープからの自動起動をスケジュールします。

`switch_version.sh` スクリプトにより、これらのモードの有効/無効を簡単に切り替えることができます。

> **X API**: X（旧Twitter）が提供する公式API。
> **launchd**: macOS標準のサービス管理・ジョブスケジューリングシステム。
> **cron**: UNIX系OSで標準的なジョブスケジューラ。
> **pmset**: macOSで電源管理設定（スリープ解除スケジュール等）を行うコマンド。

---

## ✨ 主な機能

- **X APIを使用した自動投稿**: 定期的に自動投稿を実行 (デフォルト90分間隔)
- **ツイート処理**: スケジュールされたツイートなどを処理 (デフォルト10分間隔)
- **実行間隔制御**: 各スクリプトで前回実行からの経過時間を確認し、短すぎる場合はスキップ
- **APIレート制限考慮**: X APIの制限を考慮した実行制御、レート制限エラー時の自動再試行
- **ピーク時間帯処理**: 特定の時間帯（デフォルト6, 12, 18時）でAPI接続テストなどの処理を実行
- **並行実行防止**: ロックファイルによるスクリプトの多重起動防止
- **ログ出力**: 実行状況やエラーをバージョンごとにファイルに記録
- **macOS実行モード切替**: `launchd` モードと `cron+pmset` モードを `switch_version.sh` で管理
- **共通化**: 設定値や共通関数を外部ファイル化し、保守性を向上

---

## 🔧 使用技術

- **言語**: Python 3.12, Bash (Shell Script)
- **フレームワーク**: Django 5.0+
- **API連携**: Tweepy 4.14.0+ (X API v2対応)
- **データベース**: SQLite (Django ORM)
- **スケジューリング (macOS)**: launchd または cron + pmset
- **環境変数管理**: python-dotenv, .envファイル

---

## 📁 ファイル構造

```
.
├── auto_tweet_project/         # Djangoプロジェクトディレクトリ
│   ├── core/                   # コアアプリケーション
│   ├── x_scheduler/            # X API投稿スケジューラアプリケーション
│   │   ├── management/commands/ # Djangoカスタムコマンド (auto_post.py, process_tweets.py)
│   │   └── ...                 # models.py, utils.py など
│   ├── auto_tweet_project/     # プロジェクト設定 (settings.py, urls.py)
│   ├── db.sqlite3
│   └── manage.py
├── scripts/                    # シェルスクリプト関連ディレクトリ
│   ├── config/
│   │   └── common_config.sh    # 共通設定変数ファイル
│   ├── functions/
│   │   └── common_functions.sh # 共通関数ファイル
│   ├── launchd_version/        # Launchdモード用スクリプト等
│   │   ├── auto_tweet.sh
│   │   ├── process_tweets.sh
│   │   ├── auto_tweet_last_run.txt     # 最終実行時刻記録
│   │   ├── process_tweets_last_run.txt # 最終実行時刻記録
│   │   ├── com.user.auto_tweet.plist.template    # launchd設定テンプレート
│   │   └── com.user.process_tweets.plist.template # launchd設定テンプレート
│   ├── pmset_version/          # Cron+PMSetモード用スクリプト等
│   │   ├── auto_tweet.sh
│   │   ├── process_tweets.sh
│   │   ├── auto_tweet_last_run.txt     # 最終実行時刻記録
│   │   ├── process_tweets_last_run.txt # 最終実行時刻記録
│   │   ├── wake_schedule.txt           # pmsetスケジュール記録 (auto_tweet)
│   │   └── process_wake_schedule.txt   # pmsetスケジュール記録 (process_tweets)
│   └── logs/                     # ログディレクトリ (バージョン別に格納)
│       ├── launchd_version/
│       │   ├── auto_tweet/
│       │   └── process_tweets/
│       └── pmset_version/
│           ├── auto_tweet/
│           └── process_tweets/
├── .env                        # 環境変数設定ファイル (gitignore対象)
├── .env.example                # 環境変数の例
├── .gitignore
├── .venv/                      # Python仮想環境 (gitignore対象)
├── requirements.txt
├── switch_version.sh           # macOS用 実行モード切り替えスクリプト
├── .auto_tweet.lock            # 多重起動防止用ロックファイル (auto_tweet)
├── .process_tweets.lock        # 多重起動防止用ロックファイル (process_tweets)
└── README.md                   # このファイル
```

---

## 🧩 コンポーネント説明

### 主要スクリプト (`scripts/` ディレクトリ内)

#### 1. バージョン別スクリプト (`pmset_version`, `launchd_version`)
- **`auto_tweet.sh`**: 自動投稿のメインスクリプト。実行間隔チェック、Djangoの `auto_post` コマンド呼び出し、ログ出力、(pmset版のみ)次回 `pmset` スケジュール設定などを行う。
- **`process_tweets.sh`**: ツイート処理のメインスクリプト。実行間隔チェック、Djangoの `process_tweets` コマンド呼び出し、ログ出力、(pmset版のみ)次回 `pmset` スケジュール設定などを行う。
- **各バージョン**: `pmset_version` はスリープからの復帰を `pmset` で管理するロジックを含み、`launchd_version` はそれを含まない。

#### 2. 共通設定・関数
- **`config/common_config.sh`**: ログディレクトリのベースパス、Python実行パス、投稿間隔、ピーク時間などの共通設定変数を定義。各スクリプトから `source` される。
- **`functions/common_functions.sh`**: ログ出力(`log`)、ロックファイルチェック(`check_lock`)、終了処理(`common_cleanup`)、実行間隔チェック(`check_execution_interval`)、Djangoコマンド実行(`execute_auto_post_command`等)などの共通関数を定義。各スクリプトから `source` される。

#### 3. ログ (`logs/`)
- 各スクリプトの標準出力と標準エラー出力が、バージョン別・スクリプト別に格納される。

### モード切り替えスクリプト (ルートディレクトリ)

- **`switch_version.sh`**: macOS環境で `Launchd モード` と `Cron + PMSet モード` の有効/無効を切り替えるためのユーティリティ。`launchctl` コマンドの実行や `pmset schedule cancelall` を行い、ユーザーに `crontab` の手動編集を促す。

### Django アプリケーション (`auto_tweet_project/`)

- **`manage.py`**: Django管理スクリプト。
- **`x_scheduler/management/commands/`**: シェルスクリプトから呼び出されるカスタムDjangoコマンド。
    - `auto_post.py`: 実際の投稿ロジック、画像選択など。
    - `process_tweets.py`: スケジュールされたツイートの処理、API接続テストなど。
- **`x_scheduler/models.py`**: `TweetSchedule`, `DailyPostCounter`, `SystemSetting` などのデータモデル。
- **`core/settings.py`**: Django プロジェクト固有の設定。

### その他 (ルートディレクトリ)

- **`.env`**: X APIキー, Django `SECRET_KEY`, `DEBUG` フラグなど。
- **`.auto_tweet.lock`, `.process_tweets.lock`**: スクリプトの多重起動を防止するためのロックファイル。

---

## 🚀 インストールと設定

### 1. X Developer Portalでの設定

#### 1.1 アプリケーションの作成
1. [X Developer Portal](https://developer.twitter.com/en/portal/dashboard)にアクセス
2. 「Create Project」をクリック
3. プロジェクト名を入力（例：「Auto Tweet App」）
4. 「Use Case」で「Automated/Bot Account」を選択
5. プロジェクトの説明を入力

#### 1.2 User Authentication Settingsの設定
1. プロジェクトの「User authentication settings」タブに移動
2. 「Edit」をクリック
3. 「Type of App」で「Web App」を選択
4. 「Callback URL」に以下を追加：
   ```
   http://127.0.0.1:8000/scheduler/x_auth/callback/
   ```
5. 「Website URL」にあなたのウェブサイトURLを入力（必須）
6. 設定を保存

#### 1.3 APIキーの取得
1. 「Keys and Tokens」タブに移動
2. 以下の情報を取得し、安全な場所に保存：
   - API Key
   - API Key Secret
   - Access Token
   - Access Token Secret

### 2. システムのインストール

#### 2.1 リポジトリのクローンと初期設定
```bash
# リポジトリのクローン
git clone <repository-url>
cd auto_tweet

# 仮想環境の作成と有効化
python -m venv .venv
source .venv/bin/activate

# 依存パッケージのインストール
pip install -r requirements.txt
```

#### 2.2 環境変数の設定
```bash
# .env.exampleをコピーして.envファイルを作成
cp .env.example .env

# .envファイルを編集 (vim や他のエディタを使用)
vim .env
```
`.env`ファイルに **1.3** で取得したAPIキー等を設定:
```dotenv
X_API_KEY=your_api_key_here
X_API_SECRET=your_api_secret_here
X_ACCESS_TOKEN=your_access_token_here
X_ACCESS_TOKEN_SECRET=your_access_token_secret_here
SECRET_KEY=django_secret_key_here # Djangoの秘密鍵 (python -c 'import secrets; print(secrets.token_hex(50))' などで生成可能)
DEBUG=False
ALLOWED_HOSTS=localhost,127.0.0.1
```

#### 2.3 データベースの初期化
```bash
cd auto_tweet_project
python manage.py migrate
python manage.py createsuperuser # (任意) 管理画面を使いたい場合
cd .. # ルートディレクトリに戻る
```

#### 2.4 実行権限の設定
```bash
chmod +x scripts/pmset_version/*.sh
chmod +x scripts/launchd_version/*.sh
chmod +x switch_version.sh
```

#### 2.5 画像ディレクトリの設定 (任意)
Django側で画像投稿機能を使用する場合:
```bash
mkdir -p auto_tweet_project/media/auto_post_images
```

---

## 💻 macOSでの自動実行設定

macOSでは、以下の2つのモードから自動実行方法を選択できます。`switch_version.sh` を使って設定を管理します。

### 実行モードについて (launchd vs cron+pmset)

1.  **Launchd モード**: (推奨: シンプル)
    *   **スケジューラ**: macOS標準の `launchd`。
    *   **使用スクリプト**: `scripts/launchd_version/*.sh`。
    *   **動作**: Macが起動中（スリープしていない状態）に、`.plist` ファイルで指定された間隔でスクリプトを実行します。
    *   **利点**: macOS標準の方法で安定性が高い。`sudoers` 設定が不要。
    *   **欠点**: Macがスリープしていると実行されません。

2.  **Cron + PMSet モード**: (スリープ中も実行したい場合)
    *   **スケジューラ**: 標準の `cron` + スクリプト内の `pmset` コマンド。
    *   **使用スクリプト**: `scripts/pmset_version/*.sh`。
    *   **動作**: `cron` が指定された時刻にスクリプトを起動します。スクリプトは実行後、次回の実行時刻を計算し、`sudo pmset schedule wake ...` コマンドでMacのスリープ解除を予約します。
    *   **利点**: Macがスリープしていても、指定時刻に自動で復帰してスクリプトを実行できます。
    *   **欠点**: `cron` と `pmset` の両方を管理する必要がある。`sudo pmset` をパスワードなしで実行するための **`sudoers` 設定が必須**。

### モードの切り替え方法 (`switch_version.sh`)

付属の切り替えスクリプトで、これらのモードの有効/無効を管理します。

```bash
# 現在のモード状況を確認
./switch_version.sh status

# Launchd モードを有効化 (Cron+PMSetモードを無効化する)
./switch_version.sh launchd

# Cron + PMSet モードを有効化 (Launchdモードを無効化する)
./switch_version.sh pmset

# ヘルプ表示
./switch_version.sh help
```

**注意:** このスクリプトは `launchd` のジョブは直接ロード/アンロードしますが、`crontab` の編集は行いません。`pmset` モードと `launchd` モードを切り替える際は、スクリプトの指示に従って `crontab -e` で手動編集が必要です。

### Launchd モード設定手順

1.  **テンプレートの準備と編集:**
    *   テンプレートファイル (`.plist.template`) をコピーし、リネームします。
        ```bash
        cp scripts/launchd_version/com.user.auto_tweet.plist.template scripts/launchd_version/com.user.auto_tweet.plist
        cp scripts/launchd_version/com.user.process_tweets.plist.template scripts/launchd_version/com.user.process_tweets.plist
        ```
    *   コピーした `.plist` ファイルを開き、以下のプレースホルダーを**あなたの環境に合わせて**編集します。
        *   `${PROJECT_DIR}`: `auto_tweet` プロジェクトの**フルパス** (例: `/Users/yourname/Projects/auto_tweet`)。
        *   `${VENV_BIN_PATH}`: プロジェクトのPython仮想環境 (`.venv`) の `bin` ディレクトリの**フルパス** (例: `/Users/yourname/Projects/auto_tweet/.venv/bin`)。
        *   `${SYSTEM_PATH}`: システムの基本 `PATH` (通常は `/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` でOK)。
    *   **編集例 (`sed` を使う場合):**
        ```bash
        cd scripts/launchd_version/ # plistファイルがあるディレクトリへ移動
        PROJECT_PATH_ESC=$(echo "$PWD/../.." | sed 's/\//\\\//g') # エスケープ処理
        VENV_PATH_ESC=$(echo "$PWD/../../.venv/bin" | sed 's/\//\\\//g')
        SYS_PATH="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" # 必要なら変更

        sed -i '' \
          -e "s/\${PROJECT_DIR}/${PROJECT_PATH_ESC}/g" \
          -e "s/\${VENV_BIN_PATH}/${VENV_PATH_ESC}/g" \
          -e "s/\${SYSTEM_PATH}/${SYS_PATH}/g" \
          com.user.auto_tweet.plist com.user.process_tweets.plist
        cd ../.. # ルートディレクトリに戻る
        ```

2.  **LaunchAgents への配置:**
    *   編集した `.plist` ファイルをユーザーの `LaunchAgents` ディレクトリに移動します。
        ```bash
        mv scripts/launchd_version/com.user.auto_tweet.plist ~/Library/LaunchAgents/
        mv scripts/launchd_version/com.user.process_tweets.plist ~/Library/LaunchAgents/
        ```

3.  **モードの有効化:**
    *   `switch_version.sh` を使って `launchd` モードを有効にします。これにより、`launchd` ジョブがロードされます。
        ```bash
        ./switch_version.sh launchd
        ```
    *   もし `cron` に `pmset_version` の設定が残っている場合は、`crontab -e` でコメントアウトまたは削除してください。

4.  **動作確認:**
    ```bash
    # ジョブがロードされているか確認
    launchctl list | grep com.user
    # 手動で実行してみる
    launchctl start com.user.auto_tweet
    # ログを確認
    tail -f scripts/logs/launchd_version/auto_tweet/auto_tweet.log
    ```

### Cron + PMSet モード設定手順

1.  **`sudoers` 設定 (必須):**
    *   `pmset_version/*.sh` スクリプトは内部で `sudo pmset schedule wake` を実行します。`cron` ジョブからパスワードなしで `sudo` を実行できるように設定します。
    *   `sudo visudo -f /etc/sudoers.d/pmset` コマンドでファイルを作成・編集し、以下を記述（`your_username` は実際のユーザー名に置き換え）。
        ```
        your_username ALL=(ALL) NOPASSWD: /usr/bin/pmset
        ```
    *   ファイルの権限を設定します。
        ```bash
        sudo chmod 440 /etc/sudoers.d/pmset
        ```

2.  **`crontab` の設定:**
    *   `crontab -e` コマンドで crontab を編集し、以下の内容を追加または有効化します（パスは実際の環境に合わせてください）。
        ```crontab
        # crontab for auto_tweet project (using pmset_version scripts)

        # 環境変数 (Python仮想環境のパスなど)
        PATH=/Users/yourname/Projects/auto_tweet/.venv/bin:/usr/local/bin:/usr/bin:/bin

        # プロジェクトルートディレクトリ
        PROJECT_DIR="/Users/yourname/Projects/auto_tweet"
        # pmset_version 用のログディレクトリベースパス
        LOG_BASE_DIR="${PROJECT_DIR}/scripts/logs/pmset_version"

        # pmset_version/auto_tweet.sh を90分ごとに実行
        0 0,3,6,9,12,15,18,21 * * * cd "${PROJECT_DIR}" && ./scripts/pmset_version/auto_tweet.sh >> "${LOG_BASE_DIR}/auto_tweet/auto_tweet.log" 2>> "${LOG_BASE_DIR}/auto_tweet/error.log"
        30 1,4,7,10,13,16,19,22 * * * cd "${PROJECT_DIR}" && ./scripts/pmset_version/auto_tweet.sh >> "${LOG_BASE_DIR}/auto_tweet/auto_tweet.log" 2>> "${LOG_BASE_DIR}/auto_tweet/error.log"

        # pmset_version/process_tweets.sh を10分ごとに実行 (5分開始)
        5,15,25,35,45,55 * * * * cd "${PROJECT_DIR}" && ./scripts/pmset_version/process_tweets.sh >> "${LOG_BASE_DIR}/process_tweets/process_tweets.log" 2>> "${LOG_BASE_DIR}/process_tweets/error.log"
        ```

3.  **モードの有効化:**
    *   `switch_version.sh` を使って `pmset` モードを有効にします。これにより、関連する `launchd` ジョブがアンロードされます。
        ```bash
        ./switch_version.sh pmset
        ```

4.  **動作確認:**
    ```bash
    # crontab設定を確認
    crontab -l
    # 手動で実行してみる
    ./scripts/pmset_version/auto_tweet.sh
    # ログを確認
    tail -f scripts/logs/pmset_version/auto_tweet/auto_tweet.log
    # pmsetスケジュールを確認 (sudoが必要)
    sudo pmset -g sched
    ```
    *   最終的には、`cron` で設定した時刻にスクリプトが実行され、ログが出力され、`sudo pmset -g sched` で次回の wake スケジュールが設定されることを確認します。

---

## 🐧 Linux環境での自動実行設定 (参考)

Linux 環境では `launchd` や `pmset` は使用できないため、`cron` を使用して `scripts/launchd_version/` ディレクトリ内のスクリプトを実行するのが一般的です（`pmset` を含まないため）。

1.  `crontab -e` で設定を開きます。
2.  以下のような設定を追加します（パスや実行間隔は環境に合わせて調整）。
    ```crontab
    # crontab for auto_tweet project (Linux - using launchd_version scripts)

    # 環境変数
    PATH=/path/to/your/project/auto_tweet/.venv/bin:/usr/local/bin:/usr/bin:/bin

    PROJECT_DIR="/path/to/your/project/auto_tweet"
    LOG_BASE_DIR="${PROJECT_DIR}/scripts/logs/launchd_version" # Linuxでも launchd_version を使う想定

    # launchd_version/auto_tweet.sh を90分ごとに実行
    */90 * * * * cd "${PROJECT_DIR}" && ./scripts/launchd_version/auto_tweet.sh >> "${LOG_BASE_DIR}/auto_tweet/auto_tweet.log" 2>> "${LOG_BASE_DIR}/auto_tweet/error.log"

    # launchd_version/process_tweets.sh を10分ごとに実行
    */10 * * * * cd "${PROJECT_DIR}" && ./scripts/launchd_version/process_tweets.sh >> "${LOG_BASE_DIR}/process_tweets/process_tweets.log" 2>> "${LOG_BASE_DIR}/process_tweets/error.log"
    ```

---

## 📝 使用方法

自動実行設定が完了していれば、基本的に操作は不要です。
手動で実行したい場合は、以下のように行います。

```bash
# --- macOS --- 

# Launchd モードで手動実行
launchctl start com.user.auto_tweet
launchctl start com.user.process_tweets

# Cron+PMSet モードで手動実行 (直接スクリプトを実行)
./scripts/pmset_version/auto_tweet.sh
./scripts/pmset_version/process_tweets.sh

# --- Linux (参考) --- 
# 手動実行 (直接スクリプトを実行)
./scripts/launchd_version/auto_tweet.sh
./scripts/launchd_version/process_tweets.sh

# --- Django コマンド直接実行 (デバッグ等) --- 
source .venv/bin/activate
cd auto_tweet_project

# 自動投稿コマンド (即時投稿)
python manage.py auto_post --text "テスト投稿" --post-now

# ツイート処理コマンド
python manage.py process_tweets
```

---

## ⚙️ 設定パラメータ

システムの挙動は主に以下のファイルで設定されます。

- **`.env`**: X APIキー, Django `SECRET_KEY`, `DEBUG` フラグなど。
- **`scripts/config/common_config.sh`**: シェルスクリプト共通のパス、実行間隔 (秒・分)、ピーク時間、再試行間隔など。
- **`auto_tweet_project/core/settings.py`**: Django プロジェクト固有の設定。

---

## 🔍 トラブルシューティング

### API接続/認証エラー
**症状**: 「API接続テスト失敗」というエラーメッセージが表示される  
**原因**: X APIの認証情報が正しくない、またはネットワーク接続の問題  
**解決策**:
1. `.env`ファイルのAPI認証情報が正しいか確認
2. インターネット接続を確認
3. X Developer Portalでアプリのアクセス権限を確認

### レート制限エラー
**症状**: 「Too Many Requests」または「Rate limit exceeded」というエラーメッセージ  
**原因**: X APIのレート制限に達した  
**解決策**:
1. スクリプトは自動的に5分後に再試行します
2. 手動での解決が必要な場合は、しばらく待ってから再試行してください
3. `DailyPostCounter`モデルのカウントをリセットするには管理画面を使用

### 自動実行が行われない
**症状**: 予定された時間に自動投稿が実行されない  
**原因**: スケジューラの設定問題、権限問題、またはスクリプトのエラー  
**解決策**:
1.  `./switch_version.sh status` で現在のモードを確認。
2.  有効なモードの設定（`launchd list`, `crontab -l`, `sudo pmset -g sched`）を確認。
3.  関連するログファイル (`scripts/logs/...`) でエラーを確認。
4.  スクリプトの実行権限 (`chmod +x`) を確認。
5.  `.env` ファイルや `common_config.sh` の設定を確認。
6.  (pmset モードの場合) `sudoers` 設定を確認。

### ロックファイルが残存する問題
**症状**: 「別のスクリプトが実行中です」というメッセージが表示されるが実際には実行されていない  
**原因**: 前回の実行が異常終了し、ロックファイルが削除されなかった  
**解決策**:
1. ロックファイルを手動で削除: `rm .auto_tweet.lock .process_tweets.lock`

---

## 🔧 開発者向け情報

- **共通関数**: `scripts/functions/common_functions.sh` に共通処理が集約されています。
- **共通設定**: `scripts/config/common_config.sh` で設定値を管理しています。
- **Djangoコマンド**: 実際の処理は `auto_tweet_project/x_scheduler/management/commands/` 以下の Python スクリプトで行われます。
- **テスト**: `cd auto_tweet_project && python manage.py test x_scheduler` で Django アプリケーションのテストを実行できます。

---

## 🔒 セキュリティ考慮事項

- APIキー等の機密情報は `.env` ファイルで管理し、Git リポジトリには含めないでください。
- `sudoers` 設定は必要最小限 (`NOPASSWD` 対象を `/usr/bin/pmset` のみに限定) にしてください。

---

## 📈 バージョン履歴

### v1.3.0 (2024-04-03)
- シェルスクリプトのリファクタリングを実施。
  - 設定 (`common_config.sh`) と関数 (`common_functions.sh`) を共通化。
  - ログ出力先を `scripts/logs/<version>/<script>/` に統一。
  - ディレクトリ構造を `scripts/` 以下に整理。
- `switch_version.sh` を修正し、macOSの実行モード (`launchd` vs `cron+pmset`) の管理を行うように変更。
- `README.md` を現状に合わせて大幅に更新。
- `launchd` 用の `.plist` テンプレートを修正。

### v1.2.1 (2025-03-12) - (旧バージョン)
...
### v1.2.0 (2025-03-11) - (旧バージョン)
...
### v1.1.0 (2025-03-09) - (旧バージョン)
...
### v1.0.0 (2025-03-08) - (旧バージョン)
...

(古いバージョン履歴は簡略化または削除してもOKです)

---

## 📄 ライセンス

(変更なし)

MIT License
...

---

## 📞 連絡先・サポート

(変更なし)

- **GitHub Issues**: ...
- **メール**: ...

---

*このプロジェクトは継続的に改善されています。フィードバックや貢献を歓迎します！*
