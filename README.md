# X API 自動投稿システム

<!-- 目次 (Table of Contents) -->
## 📚 目次

- [概要](#-概要)
- [主な機能](#-主な機能)
- [使用技術](#-使用技術)
- [ファイル構造](#-ファイル構造)
- [コンポーネント説明](#-コンポーネント説明)
- [インストールと設定](#-インストールと設定)
  - [前提条件](#前提条件)
  - [1. X Developer Portalでの設定](#1-x-developer-portalでの設定)
  - [2. システムのインストールと環境構築](#2-システムのインストールと環境構築)
- [macOSでの自動実行設定](#-macosでの自動実行設定)
  - [実行モードについて (launchd vs cron+pmset)](#実行モードについて-launchd-vs-cronpmset)
  - [モードの切り替え方法 (`switch_version.sh`)](#モードの切り替え方法-switch_versionsh)
  - [【推奨】Launchd モード設定手順](#推奨launchd-モード設定手順)
  - [【上級】Cron + PMSet モード設定手順](#上級cron--pmset-モード設定手順)
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
1.  **Launchd モード (推奨)**: Macが起動中（スリープしていない状態）にのみ実行されます。設定が比較的簡単です。
2.  **Cron + PMSet モード (上級)**: Cronで定期実行をトリガーし、スクリプト内で `pmset` を使用してMacのスリープからの自動起動をスケジュールします。`sudoers` 設定が必要です。

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

- **言語**: Python 3.12+, Bash (Shell Script)
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

### 前提条件
- macOS または Linux 環境
- Python 3.12 以降
- Git
- X (Twitter) Developer Account

### 1. X Developer Portalでの設定

#### 1.1 アプリケーションの作成
1. [X Developer Portal](https://developer.twitter.com/en/portal/dashboard)にアクセスし、サインインします。
2. プロジェクトとアプリケーションを作成します。
   - プロジェクト名（例: `My Auto Tweet Project`）
   - ユースケース（例: `Automated/Bot Account`）
   - アプリ名（例: `Auto Tweet Bot`）
3. 作成したアプリケーションの設定ページに移動します。

#### 1.2 User Authentication Settingsの設定
1. アプリケーション設定の「User authentication settings」セクションを探し、「Edit」をクリックします。
2. 以下の設定を行います:
   - **App permissions**: `Read and write` を選択します。(ツイート投稿に必要)
   - **Type of App**: `Web App, Automated App or Bot` を選択します。
   - **App info**:
     - **Callback URI / Redirect URL**: 以下を入力します (ローカル開発サーバー用)。
       ```
       http://127.0.0.1:8000/scheduler/x_auth/callback/
       ```
       (もし異なるポートやドメインを使用する場合は適宜変更してください)
     - **Website URL**: あなたのウェブサイトやGitHubリポジトリのURLなどを入力します (必須)。
3. 「Save」をクリックして設定を保存します。

#### 1.3 APIキーとトークンの取得
1. アプリケーション設定の「Keys and Tokens」タブに移動します。
2. **API Key and Secret**: 「Regenerate」ボタンをクリックし、表示される **API Key** と **API Key Secret** を**必ず安全な場所にコピーして保存**してください。**この Secret は一度しか表示されません。**
3. **Access Token and Secret**: 「Generate」ボタンをクリックし、表示される **Access Token** と **Access Token Secret** を**必ず安全な場所にコピーして保存**してください。**この Secret も一度しか表示されません。**

### 2. システムのインストールと環境構築

#### 2.1 リポジトリのクローンとディレクトリ移動
```bash
# 任意の作業ディレクトリにリポジトリをクローン
git clone https://github.com/tomoyasu-sasaki/AutoTweet.git

# クローンしたディレクトリに移動
cd auto_tweet
```

#### 2.2 Python仮想環境の作成と有効化
Pythonのバージョン (3.12以降) を確認し、プロジェクト用の仮想環境を作成して有効化します。
```bash
# Python 3.12以降が使われることを確認 (例: python3.12 -m venv ...)
python -m venv .venv

# 仮想環境を有効化 (macOS/Linux)
source .venv/bin/activate
# (Windowsの場合は source .venv/Scripts/activate)
```
これ以降の `pip` や `python` コマンドは、仮想環境内で実行されます。

#### 2.3 依存パッケージのインストール
`requirements.txt` に記載されたPythonライブラリをインストールします。
```bash
pip install -r requirements.txt
```

#### 2.4 環境変数ファイル `.env` の設定
`.env.example` をコピーして `.env` ファイルを作成し、**1.3** で取得したAPIキー等を設定します。
```bash
# .env.example をコピー
cp .env.example .env

# テキストエディタ (例: vim, nano, VSCodeなど) で .env ファイルを開き編集
# 例: nano .env
```
`.env` ファイルの内容を以下のように編集します:
```dotenv
# X API認証情報 (必須)
X_API_KEY=ここにあなたのAPI_Keyを入力
X_API_SECRET=ここにあなたのAPI_Key_Secretを入力
X_ACCESS_TOKEN=ここにあなたのAccess_Tokenを入力
X_ACCESS_TOKEN_SECRET=ここにあなたのAccess_Token_Secretを入力

# Djangoの設定 (必須)
# SECRET_KEYは推測困難なランダムな文字列を設定してください
# 例: python -c 'import secrets; print(secrets.token_hex(50))' で生成
SECRET_KEY=ここにDjangoのSECRET_KEYを入力
DEBUG=False # 本番運用時は False を推奨 (開発時は True でも可)
ALLOWED_HOSTS=localhost,127.0.0.1 # 開発サーバーにアクセスするホスト名 (必要に応じて追加)

# ログ設定 (通常は変更不要)
DJANGO_LOG_LEVEL=INFO
APP_LOG_LEVEL=INFO

# アプリケーション設定 (必要に応じて変更)
MAX_DAILY_POSTS=16
DEFAULT_TWEET_TEXT="投稿テキスト"
# DEFAULT_IMAGE_DIR=auto_post_images # 必要なら設定
POST_INTERVAL_MINUTES=90 # 自動投稿スクリプトの実行間隔(分)
PROCESS_TWEETS_INTERVAL_MINUTES=10 # ツイート処理スクリプトの実行間隔(分)
DEFAULT_SCHEDULE_HOURS=1
MAX_TWEET_LENGTH=280
```

#### 2.5 Djangoデータベースの初期化
Djangoアプリケーションが使用するデータベース（デフォルトはSQLite）を初期化します。
```bash
# Djangoプロジェクトディレクトリに移動
cd auto_tweet_project

# データベースマイグレーションを実行
python manage.py migrate

# (任意) Django管理画面を使用するための管理者ユーザーを作成
python manage.py createsuperuser

# プロジェクトのルートディレクトリに戻る
cd ..
```

#### 2.6 シェルスクリプトへの実行権限付与
自動実行に使用するシェルスクリプトに実行権限を与えます。
```bash
chmod +x scripts/pmset_version/*.sh
chmod +x scripts/launchd_version/*.sh
chmod +x switch_version.sh
```

#### 2.7 画像ディレクトリの作成 (任意)
Djangoアプリケーション内で画像を生成・管理する場合、メディアディレクトリを作成します (Djangoの `MEDIA_ROOT` 設定に関連)。
```bash
# Djangoプロジェクトディレクトリ内に media ディレクトリを作成
mkdir -p auto_tweet_project/media
# (もし .env の DEFAULT_IMAGE_DIR を設定した場合は、そのパスも作成)
# mkdir -p auto_tweet_project/media/auto_post_images
```

これで基本的なインストールと環境構築は完了です。次に、OSに合わせた自動実行設定を行います。

---

## 💻 macOSでの自動実行設定

macOSでは、以下の2つのモードから自動実行方法を選択できます。`switch_version.sh` を使って設定を管理します。

### 実行モードについて (launchd vs cron+pmset)

1.  **Launchd モード (推奨)**:
    *   **スケジューラ**: macOS標準の `launchd`。
    *   **使用スクリプト**: `scripts/launchd_version/*.sh`。
    *   **動作**: Macが起動中（スリープしていない状態）に、`.plist` ファイルで指定された間隔でスクリプトを実行します。
    *   **利点**: macOS標準の方法で安定性が高い。`sudoers` 設定が不要。設定が比較的容易。
    *   **欠点**: Macがスリープしていると実行されません。

2.  **Cron + PMSet モード (上級)**:
    *   **スケジューラ**: 標準の `cron` + スクリプト内の `pmset` コマンド。
    *   **使用スクリプト**: `scripts/pmset_version/*.sh`。
    *   **動作**: `cron` が指定された時刻にスクリプトを起動します。スクリプトは実行後、次回の実行時刻を計算し、`sudo pmset schedule wake ...` コマンドでMacのスリープ解除を予約します。
    *   **利点**: Macがスリープしていても、指定時刻に自動で復帰してスクリプトを実行できます。
    *   **欠点**: `cron` と `pmset` の両方を管理する必要がある。`sudo pmset` をパスワードなしで実行するための **`sudoers` 設定が必須**であり、セキュリティリスクを伴います。`cron` の環境設定（特にPATH）が複雑になる場合があります。

### モードの切り替え方法 (`switch_version.sh`)

付属の切り替えスクリプトで、これらのモードの有効/無効を管理します。

```bash
# 現在のモード状況を確認
./switch_version.sh status

# Launchd モードを有効化 (Cron+PMSetモードを無効化する準備)
# -> この後、必要に応じて crontab -e で cron ジョブを削除/コメントアウトします
./switch_version.sh launchd

# Cron + PMSet モードを有効化 (Launchdモードを無効化する)
# -> この後、sudoers 設定と crontab -e での cron ジョブ設定が必要です
./switch_version.sh pmset

# ヘルプ表示
./switch_version.sh help
```

**注意:** このスクリプトは `launchd` のジョブは直接ロード/アンロードしますが、`crontab` の編集や `sudoers` の設定は行いません。`pmset` モードと `launchd` モードを切り替える際は、スクリプトの指示に従って関連する手動設定が必要です。

### 【推奨】Launchd モード設定手順

1.  **`.plist` テンプレートの準備と編集:**
    *   `scripts/launchd_version/` 内にある `.plist.template` ファイルをコピーし、末尾の `.template` を削除します。
        ```bash
        # テンプレートをコピーしてリネーム
        cp scripts/launchd_version/com.user.auto_tweet.plist.template scripts/launchd_version/com.user.auto_tweet.plist
        cp scripts/launchd_version/com.user.process_tweets.plist.template scripts/launchd_version/com.user.process_tweets.plist
        ```
    *   コピーした `.plist` ファイルを開き、以下の **3つのプレースホルダー** を**あなたの環境のフルパスに**置き換えます。
        *   `${PROJECT_DIR}`: この `auto_tweet` プロジェクトの**フルパス** (例: `/Users/yourname/Projects/Public/auto_tweet`)。
        *   `${VENV_BIN_PATH}`: プロジェクトのPython仮想環境 (`.venv`) の `bin` ディレクトリの**フルパス** (例: `/Users/yourname/Projects/Public/auto_tweet/.venv/bin`)。
        *   `${SYSTEM_PATH}`: システムの基本 `PATH`。通常は `/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` で問題ありません。
    *   **編集例 (`sed` コマンドを使用する場合 - 現在のディレクトリがプロジェクトルートであること):**
        ```bash
        # プロジェクトルートのフルパスを取得 (pwd コマンドの結果を確認)
        PROJECT_FULL_PATH=$(pwd)
        # パス内の / を sed で使えるようにエスケープ
        PROJECT_PATH_ESC=$(echo "${PROJECT_FULL_PATH}" | sed 's/\//\\\//g')
        VENV_PATH_ESC=$(echo "${PROJECT_FULL_PATH}/.venv/bin" | sed 's/\//\\\//g')
        SYS_PATH_ESC=$(echo "/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" | sed 's/\//\\\//g') # 必要なら変更

        # sed コマンドで一括置換 (macOS の sed なので -i '' を付ける)
        sed -i '' \
          -e "s/\${PROJECT_DIR}/${PROJECT_PATH_ESC}/g" \
          -e "s/\${VENV_BIN_PATH}/${VENV_PATH_ESC}/g" \
          -e "s/\${SYSTEM_PATH}/${SYS_PATH_ESC}/g" \
          scripts/launchd_version/com.user.auto_tweet.plist scripts/launchd_version/com.user.process_tweets.plist

        # (念のため) 置換結果を確認
        # grep -E '\$|\{' scripts/launchd_version/*.plist
        ```
    *   **手動編集の場合:** 各 `.plist` ファイルを開き、`string` タグ内の `${...}` 部分を上記のフルパスに書き換えてください。

2.  **LaunchAgents ディレクトリへの配置:**
    *   編集済みの `.plist` ファイルを、ユーザーの `LaunchAgents` ディレクトリ (`~/Library/LaunchAgents/`) に移動またはコピーします。
        ```bash
        # LaunchAgents ディレクトリがなければ作成
        mkdir -p ~/Library/LaunchAgents

        # plist ファイルを移動
        mv scripts/launchd_version/com.user.auto_tweet.plist ~/Library/LaunchAgents/
        mv scripts/launchd_version/com.user.process_tweets.plist ~/Library/LaunchAgents/
        ```
        (コピーする場合は `mv` の代わりに `cp` を使用)

3.  **モードの有効化とジョブのロード:**
    *   `switch_version.sh` を使って `launchd` モードを有効にします。これにより、配置した `.plist` ファイルが `launchd` に読み込まれ、スケジュールが有効になります。
        ```bash
        ./switch_version.sh launchd
        ```
    *   もし以前に `Cron + PMSet` モードを使用していた場合は、`crontab -e` を実行し、関連するジョブの行を `#` でコメントアウトするか削除してください。

4.  **動作確認:**
    *   `launchd` がジョブを認識しているか確認します。
        ```bash
        launchctl list | grep com.user
        # com.user.auto_tweet と com.user.process_tweets が表示されればOK
        ```
    *   ジョブを手動で実行してテストします。
        ```bash
        launchctl start com.user.auto_tweet
        launchctl start com.user.process_tweets
        ```
    *   実行ログを確認します。エラーが出ていないか、期待通りに動作しているかを確認します。
        ```bash
        tail -f scripts/logs/launchd_version/auto_tweet/auto_tweet.log
        tail -f scripts/logs/launchd_version/process_tweets/process_tweets.log
        # (Ctrl+C で tail を終了)
        ```
    *   しばらく待って、`.plist` の `StartInterval` で指定した間隔でジョブが自動実行され、ログが追記されるか確認します。

### 【上級】Cron + PMSet モード設定手順

**警告:** このモードは `sudo` コマンドをパスワードなしで実行する設定が必要です。セキュリティリスクを理解した上で設定してください。

1.  **`sudoers` 設定 (必須かつ重要):**
    *   `pmset_version/*.sh` スクリプトは、Macのスリープ解除をスケジュールするために `sudo pmset schedule wake ...` コマンドを実行します。`cron` ジョブからこのコマンドをパスワードなしで実行できるように、`sudoers` ファイルに設定を追加します。
    *   **必ず `visudo` コマンドを使用して編集してください。** 直接ファイルを編集すると構文エラーで `sudo` が使えなくなる危険があります。
    *   以下のコマンドを実行し、エディタが開いたら内容を追記します。ファイル名は `pmset` など分かりやすい名前にします。
        ```bash
        sudo visudo -f /etc/sudoers.d/pmset_nopasswd
        ```
    *   開いたエディタに以下の1行を追加します。**`your_username` はあなたのmacOSのユーザー名に置き換えてください。**
        ```
        your_username ALL=(ALL) NOPASSWD: /usr/bin/pmset
        ```
    *   ファイルを保存してエディタを終了します (例: nanoなら `Ctrl+O`, `Enter`, `Ctrl+X`)。`visudo` が構文チェックを行います。
    *   **セキュリティのため、作成したファイルの権限を読み取り専用に変更します。**
        ```bash
        sudo chmod 440 /etc/sudoers.d/pmset_nopasswd
        ```

2.  **`crontab` の設定:**
    *   `crontab -e` コマンドを実行して crontab の編集画面を開きます。
    *   以下の内容を追加します。**パス (`/Users/yourname/...`) はあなたの環境に合わせて正確なフルパスに書き換えてください。** 特に `PATH=` の行の `.venv/bin` へのパスは重要です。 **`crontab` 内では `${VAR}` のような変数は使わず、直接パスを記述することを推奨します。**
        ```crontab
        # crontab for auto_tweet project (using pmset_version scripts)

        # 環境変数 (Python仮想環境のパスを先頭に追加)
        PATH=/Users/yourname/Projects/Public/auto_tweet/.venv/bin:/usr/local/bin:/usr/bin:/bin

        # pmset_version/auto_tweet.sh を90分ごとに実行 (フルパス指定)
        # 例: 0:00, 1:30, 3:00, ...
        0 0,3,6,9,12,15,18,21 * * * /Users/yourname/Projects/Public/auto_tweet/scripts/pmset_version/auto_tweet.sh >> /Users/yourname/Projects/Public/auto_tweet/scripts/logs/pmset_version/auto_tweet/auto_tweet.log 2>> /Users/yourname/Projects/Public/auto_tweet/scripts/logs/pmset_version/auto_tweet/error.log
        30 1,4,7,10,13,16,19,22 * * * /bin/bash /Users/yourname/Projects/Public/auto_tweet/scripts/pmset_version/auto_tweet.sh >> /Users/yourname/Projects/Public/auto_tweet/scripts/logs/pmset_version/auto_tweet/auto_tweet.log 2>> /Users/yourname/Projects/Public/auto_tweet/scripts/logs/pmset_version/auto_tweet/error.log

        # pmset_version/process_tweets.sh を10分ごとに実行 (5分開始、フルパス指定)
        5,15,25,35,45,55 * * * * /Users/yourname/Projects/Public/auto_tweet/scripts/pmset_version/process_tweets.sh >> /Users/yourname/Projects/Public/auto_tweet/scripts/logs/pmset_version/process_tweets/process_tweets.log 2>> /Users/yourname/Projects/Public/auto_tweet/scripts/logs/pmset_version/process_tweets/error.log
        ```
    *   ファイルを保存してエディタを終了します。

3.  **フルディスクアクセスの確認 (重要):**
    *   cron ジョブがスクリプトファイルやログファイル（ユーザーディレクトリ内にある場合）にアクセスするには、cron デーモン (`/usr/sbin/cron`) に「フルディスクアクセス」権限が必要です。
    *   「システム設定」>「プライバシーとセキュリティ」>「フルディスクアクセス」を開きます。
    *   リストに `/usr/sbin/cron` が存在し、スイッチが **オン** になっていることを確認します。
    *   もし存在しない場合は、`+` ボタンをクリックし、ファイル選択ダイアログで `/usr/sbin/cron` を選択して追加し、スイッチをオンにします (管理者パスワードが必要です)。 Finder で `/usr/sbin` を表示するには、メニュー「移動」>「フォルダへ移動...」で `/usr/sbin` と入力します。
    *   **設定変更後は Mac を再起動するとより確実に反映されます。**

4.  **モードの有効化:**
    *   `switch_version.sh` を使って `pmset` モードを有効にします。これにより、もし Launchd モードが有効だった場合、関連する `launchd` ジョブがアンロードされます。
        ```bash
        ./switch_version.sh pmset
        ```

5.  **動作確認:**
    *   `crontab` の設定内容を再確認します。
        ```bash
        crontab -l
        ```
    *   スクリプトを手動で実行してテストします（`sudoers` 設定が正しくないと `pmset` 実行時にエラーになる可能性があります）。
        ```bash
        ./scripts/pmset_version/auto_tweet.sh
        ./scripts/pmset_version/process_tweets.sh
        ```
    *   実行ログを確認します。
        ```bash
        tail -f scripts/logs/pmset_version/auto_tweet/auto_tweet.log
        tail -f scripts/logs/pmset_version/process_tweets/process_tweets.log
        # (Ctrl+C で tail を終了)
        ```
    *   スクリプト実行後、次回のスリープ解除スケジュールが設定されているか確認します (`sudo` が必要です)。
        ```bash
        sudo pmset -g sched
        ```
    *   最終的には、`cron` で設定した時刻（例: `process_tweets.sh` なら次の 5分, 15分, ...）にスクリプトが自動実行され、ログが更新され、次回の `pmset` スケジュールが設定されることを確認します。

---

## 🐧 Linux環境での自動実行設定 (参考)

Linux 環境では `launchd` や `pmset` は使用できないため、`cron` を使用して `scripts/launchd_version/` ディレクトリ内のスクリプトを実行するのが一般的です（`pmset` を含まないため）。

1.  `crontab -e` で設定を開きます。
2.  以下のような設定を追加します（パスや実行間隔は環境に合わせて調整）。**ここでも変数は使わず、直接パスを記述することを推奨します。**
    ```crontab
    # crontab for auto_tweet project (Linux - using launchd_version scripts)

    # 環境変数 (Python仮想環境のパスを先頭に追加)
    PATH=/path/to/your/project/auto_tweet/.venv/bin:/usr/local/bin:/usr/bin:/bin

    # launchd_version/auto_tweet.sh を90分ごとに実行 (フルパス指定)
    */90 * * * * /bin/bash /path/to/your/project/auto_tweet/scripts/launchd_version/auto_tweet.sh >> /path/to/your/project/auto_tweet/scripts/logs/launchd_version/auto_tweet/auto_tweet.log 2>> /path/to/your/project/auto_tweet/scripts/logs/launchd_version/auto_tweet/error.log

    # launchd_version/process_tweets.sh を10分ごとに実行 (フルパス指定)
    */10 * * * * /bin/bash /path/to/your/project/auto_tweet/scripts/launchd_version/process_tweets.sh >> /path/to/your/project/auto_tweet/scripts/logs/launchd_version/process_tweets/process_tweets.log 2>> /path/to/your/project/auto_tweet/scripts/logs/launchd_version/process_tweets/error.log
    ```

---

## 📝 使用方法

自動実行設定が完了していれば、基本的に操作は不要です。
ログファイル (`scripts/logs/...`) を定期的に確認し、エラーが発生していないか監視することをお勧めします。

手動で各コンポーネントを実行したい場合は、以下のように行います。

```bash
# --- macOS ---

# Launchd モードで手動実行 (launchd 経由)
# (現在時刻に関わらず即時実行される)
launchctl start com.user.auto_tweet
launchctl start com.user.process_tweets

# Cron+PMSet モードで手動実行 (直接スクリプトを実行)
# (スクリプト内の実行間隔チェックが働く可能性がある)
./scripts/pmset_version/auto_tweet.sh
./scripts/pmset_version/process_tweets.sh

# --- Linux (参考) ---
# 手動実行 (直接スクリプトを実行)
# (スクリプト内の実行間隔チェックが働く可能性がある)
./scripts/launchd_version/auto_tweet.sh
./scripts/launchd_version/process_tweets.sh

# --- Django コマンド直接実行 (デバッグ等) ---
# 1. 仮想環境を有効化
source .venv/bin/activate
# 2. Django プロジェクトディレクトリに移動
cd auto_tweet_project

# 3. コマンド実行
# 自動投稿コマンド (即時投稿テスト)
python manage.py auto_post --text "手動テスト投稿です！" --post-now

# ツイート処理コマンド (スケジュール済みツイートの処理など)
python manage.py process_tweets

# 4. ルートディレクトリに戻る
cd ..
```

---

## ⚙️ 設定パラメータ

システムの挙動は主に以下のファイルで設定されます。

- **`.env`**: X APIキー, Django `SECRET_KEY`, `DEBUG` フラグなど。
- **`scripts/config/common_config.sh`**: シェルスクリプト共通のパス定義, ピーク時間、再試行間隔(秒)など。シェルスクリプトレベルでの設定。
- **`auto_tweet_project/core/settings.py`**: Django プロジェクト固有の設定 (データベース, `TIME_ZONE`, `INSTALLED_APPS` など)。

---

## 🔍 トラブルシューティング

### API接続/認証エラー
**症状**: ログに「API接続テスト失敗」や認証に関するエラーメッセージが表示される。ツイートが投稿されない。
**原因**: `.env` ファイルに設定した X API のキーやトークンが正しくない、または X Developer Portal でのアプリ設定 (権限、コールバックURLなど) が不適切。ネットワーク接続の問題。
**解決策**:
1. `.env` ファイルの `X_API_KEY`, `X_API_SECRET`, `X_ACCESS_TOKEN`, `X_ACCESS_TOKEN_SECRET` が正確か再確認。コピー＆ペーストミスがないか注意。
2. X Developer Portal でアプリの権限が `Read and Write` になっているか確認。
3. インターネット接続を確認。
4. Django コマンドを手動実行 (`python manage.py process_tweets` 内でAPIテストが行われる) してエラー詳細を確認。

### レート制限エラー
**症状**: ログに「Too Many Requests」, 「Rate limit exceeded」, またはステータスコード `429` のエラーメッセージが表示される。
**原因**: 短時間に X API を呼び出しすぎたため、一時的に制限された。
**解決策**:
1. スクリプト (`common_functions.sh` 内) は、レート制限エラーを検知すると自動的に5分後に再試行するようになっています。基本的には待つだけでOKです。
2. 頻繁に発生する場合は、`crontab` や `launchd` の実行間隔を長くすることを検討してください (`.env` の `POST_INTERVAL_MINUTES` なども関連)。
3. どうしてもすぐに制限を解除したい場合は、X Developer Portal で制限状況を確認するか、しばらく時間を置くしかありません。

### 自動実行が行われない (macOS)
**症状**: 設定した時刻になってもスクリプトが実行された形跡がない (ログファイルが更新されない)。
**原因**: スケジューラ (`launchd` または `cron`) の設定ミス、権限不足、スクリプトのエラー。
**解決策**:
1. **モード確認**: `./switch_version.sh status` で意図したモードが有効になっているか確認。
2. **設定確認**:
   - **Launchd モード**: `~/Library/LaunchAgents/` に `.plist` ファイルが存在するか？ `.plist` ファイル内のパス指定は正しいか？ `launchctl list | grep com.user` でジョブがロードされているか？
   - **Cron + PMSet モード**: `crontab -l` でジョブの行が正しく記述され、コメントアウトされていないか？ `PATH` 設定は正しいか？ スクリプトやログのパスは正しいか？
3. **ログ確認**: `scripts/logs/<version>/<script>/` 内の `.log` ファイルと `.error.log` ファイルにエラーが出力されていないか確認。
4. **権限確認**:
   - シェルスクリプト (`.sh`) に実行権限 (`chmod +x`) が付与されているか？
   - **(Cron + PMSet モード)** `/usr/sbin/cron` に**フルディスクアクセス**が許可されているか？（「システム設定」>「プライバシーとセキュリティ」>「フルディスクアクセス」） **最重要確認項目**。
   - **(Cron + PMSet モード)** `sudoers` 設定は正しく行われているか？ (`sudo visudo -c` で構文チェック可能)
5. **手動実行**: 各モードのスクリプト (`./scripts/<version>/...sh`) や Django コマンド (`python manage.py ...`) を手動で実行し、エラーが出ないか確認。
6. **Mac 再起動**: 設定変更後、Mac を再起動すると問題が解決することがあります。

### ロックファイルが残存する問題
**症状**: ログに「別のスクリプトが実行中です」というメッセージが出てスキップされるが、実際には他のプロセスは実行されていない。
**原因**: 前回のスクリプト実行が異常終了し、終了時に削除されるはずのロックファイル (`.auto_tweet.lock` または `.process_tweets.lock`) がプロジェクトルートに残ってしまった。
**解決策**:
1. プロジェクトのルートディレクトリにあるロックファイルを手動で削除します。
   ```bash
   rm -f .auto_tweet.lock .process_tweets.lock
   ```

---

## 🔧 開発者向け情報

- **共通関数**: `scripts/functions/common_functions.sh` に共通処理が集約されています。ログ出力、ロック管理、コマンド実行、エラーハンドリングなど。
- **共通設定**: `scripts/config/common_config.sh` でシェルスクリプトレベルの設定値を管理しています。
- **Djangoコマンド**: 実際の X API 操作やデータベースアクセスは `auto_tweet_project/x_scheduler/management/commands/` 以下の Python スクリプト (`auto_post.py`, `process_tweets.py`) で行われます。
- **テスト**: `cd auto_tweet_project && python manage.py test x_scheduler` で Django アプリケーションの基本的なテストを実行できます。

---

## 🔒 セキュリティ考慮事項

- **APIキー等の機密情報**: 絶対に Git リポジトリにコミットしないでください。`.env` ファイルで管理し、`.gitignore` に `.env` が含まれていることを確認してください。
- **`sudoers` 設定 (Cron + PMSet モード)**: `NOPASSWD` 設定は、対象コマンド (`/usr/bin/pmset`) とユーザーを限定し、必要最小限にしてください。設定ファイルの権限 (`chmod 440`) も適切に設定してください。この設定はシステムのセキュリティレベルを下げる可能性があることを理解してください。
- **Django `SECRET_KEY`**: `.env` ファイルで管理し、推測困難なランダムな値を設定してください。
- **`DEBUG` モード**: 本番運用環境では `DEBUG=False` に設定してください。`True` のままだと、エラー発生時に機密情報が漏洩する可能性があります。

---

## 📈 バージョン履歴

### v1.3.1 (2024-04-03)
- `README.md`: インストールとmacOS自動実行設定の手順を詳細化。特に `Launchd` と `Cron+PMSet` の設定を具体的に記述。`crontab` の変数展開問題を考慮し、直接パスを記述する形式に修正。

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

(古いバージョン履歴は適宜更新してください)

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
