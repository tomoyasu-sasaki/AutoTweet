# X API 自動投稿システム

<!-- 目次 (Table of Contents) -->
## 📚 目次

- [概要](#-概要)
- [主な機能](#-主な機能)
- [使用技術](#-使用技術)
- [ファイル構造](#-ファイル構造)
- [コンポーネント説明](#-コンポーネント説明)
- [インストールと設定](#-インストールと設定)
- [自動実行の設定](#-自動実行の設定)
  - [バージョン切り替え機能](#バージョン切り替え機能)
  - [macOS - launchdによる設定](#macos---launchdによる設定)
  - [macOS - pmsetモードの追加設定](#macos---pmsetモードの追加設定)
  - [Linux環境 - crontabによる設定](#linux環境---crontabによる設定)
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

本システムは、指定された画像とテキストを定期的にX（旧Twitter）へ自動投稿するためのツールです。DjangoフレームワークとTweepy（X API SDK）を使用して、安定した投稿スケジュール管理とAPIレート制限の最適な管理を実現しています。macOSのlaunchdとpmsetの両方に対応しており、使用環境に合わせて選択できます。

> **X API**: X（旧Twitter）が提供する公式API。アプリケーションからプログラム的にツイートの投稿や取得を行うことができます。  
> **launchd**: macOSの標準的なサービス管理システム。定期的なタスク実行を管理します。  
> **pmset**: macOSでスリープ状態からの自動起動をスケジュールするためのツール。

---

## ✨ 主な機能

システムは以下の主要な機能を提供します：

- **X APIを使用した自動投稿**: 90分ごとに安定して自動投稿を実行
- **画像付き投稿対応**: テキストだけでなく画像も含めた投稿が可能
- **スケジュール管理**: 指定した日時に投稿するスケジュール機能
- **画像の自動ローテーション**: 複数画像を順番に使用して投稿を多様化
- **投稿制限管理**: APIレート制限（1日15回）を考慮した制御
- **API接続テスト最適化**: API接続テストをピーク時間帯（6時、12時、18時）のみに限定
- **レート制限対応**: "Too Many Requests"エラー時の自動再試行機能
- **並行実行の防止**: ロックファイルによる同時実行防止機能
- **実行モード切替**: launchdとpmsetの両方に対応し、環境に合わせて切替可能

---

## 🔧 使用技術

システムは以下の技術スタックで構築されています：

- **言語**: Python 3.12
- **フレームワーク**: Django 5.0+
- **API連携**: Tweepy 4.14.0+（X API v2対応）
- **データベース**: SQLite（Django ORM）
- **スケジューリング**: macOS launchd / pmset、Linux crontab
- **環境変数管理**: python-dotenv

---

## 📁 ファイル構造

システムは以下のディレクトリとファイル構造で構成されています：

```
.
├── auto_tweet_project/         # Djangoプロジェクトディレクトリ
│   ├── core/                   # コアアプリケーション（設定、ログ等）
│   │   ├── __init__.py
│   │   └── settings.py         # プロジェクト設定
│   ├── x_scheduler/            # X API投稿スケジューラアプリケーション
│   │   ├── management/         # Djangoカスタムコマンド
│   │   │   └── commands/      # 投稿処理コマンド
│   │   │       ├── auto_post.py    # 自動投稿コマンド
│   │   │       └── process_tweets.py # ツイート処理コマンド
│   │   ├── migrations/        # DBマイグレーションファイル
│   │   ├── __init__.py
│   │   ├── admin.py          # 管理画面設定
│   │   ├── apps.py           # アプリケーション設定
│   │   ├── models.py         # データモデル
│   │   ├── tests.py          # テスト
│   │   └── utils.py          # ユーティリティ関数
│   ├── auto_tweet_project/     # プロジェクト設定ディレクトリ
│   │   ├── __init__.py
│   │   ├── asgi.py             # ASGI設定
│   │   ├── settings.py         # プロジェクト設定
│   │   ├── urls.py             # URL設定
│   │   └── wsgi.py             # WSGI設定
│   ├── db.sqlite3              # SQLiteデータベース
│   └── manage.py               # Django管理スクリプト
├── logs/                       # ログディレクトリ
│   ├── auto_tweet/             # 自動投稿のログ
│   └── process_tweets/         # ツイート処理のログ
├── launchd_version/            # launchdベースのシステム（起動中のみ実行）
│   ├── auto_tweet.sh           # launchd用自動投稿スクリプト
│   ├── process_tweets.sh       # launchd用ツイート処理スクリプト
│   ├── com.user.auto_tweet.plist # launchd設定ファイル
│   └── com.user.process_tweets.plist # launchd設定ファイル
├── pmset_version/              # pmsetベースのシステム（スリープからの自動起動）
│   ├── auto_tweet.sh           # pmset用自動投稿スクリプト
│   ├── process_tweets.sh       # pmset用ツイート処理スクリプト
│   ├── wake_schedule.txt       # 自動投稿の次回スケジュール記録
│   └── process_wake_schedule.txt # ツイート処理の次回スケジュール記録
├── auto_tweet.sh               # メインスクリプトへのシンボリックリンク
├── process_tweets.sh           # メインスクリプトへのシンボリックリンク
├── switch_version.sh           # バージョン切り替えスクリプト
├── auto_tweet_last_run.txt     # 自動投稿の最終実行時刻記録ファイル
├── process_tweets_last_run.txt # ツイート処理の最終実行時刻記録ファイル
├── .auto_tweet.lock            # 自動投稿の多重起動防止用ロックファイル
├── .process_tweets.lock        # ツイート処理の多重起動防止用ロックファイル
├── com.user.auto_tweet.plist   # 自動投稿用のlaunchdジョブ定義
├── com.user.process_tweets.plist # ツイート処理用のlaunchdジョブ定義
├── .env                        # 環境変数設定ファイル（gitignoreに含まれる）
├── .env.example                # 環境変数の例
├── .gitignore                  # Git除外設定
├── .venv/                      # Python仮想環境（gitignoreに含まれる）
├── requirements.txt            # 依存パッケージリスト
└── README.md                   # このファイル
```

---

## 🧩 コンポーネント説明

このセクションでは、システムの主要コンポーネントと各役割について説明します。

### 主要スクリプト

#### 1. auto_tweet.sh
自動投稿の主要な実行スクリプトです。以下の機能を提供します：
- 90分間隔での実行制御（前回実行から90分経過していない場合は実行をスキップ）
- ピーク時間（6時、12時、18時）の特別処理
- ロックファイルによる並行実行防止
- 詳細なログ記録
- レート制限エラーの検出と自動再試行
- 次回実行管理（バージョンによりlaunchdまたはpmsetで管理）

#### 2. process_tweets.sh
スケジュールされたツイートを処理するスクリプトです。以下の機能を提供します：
- 10分間隔での定期実行
- ロックファイルによる並行実行防止
- API接続テストの最適化
- レート制限エラーの自動再試行
- 詳細なログ記録

#### 3. switch_version.sh
実行モードを切り替えるためのユーティリティスクリプトです：
- launchdバージョンとpmsetバージョンの切り替えを管理
- 適切なシンボリックリンクを設定
- 現在のバージョン確認機能
- launchdジョブの自動ロード/アンロード

### Django アプリケーション

#### データモデル (models.py)
データベースモデルを定義しています：
- `TweetSchedule`: ツイートのスケジュール情報を管理
- `DailyPostCounter`: 1日の投稿数を記録し、制限を管理
- `SystemSetting`: API接続テスト状況など、システム設定を管理

#### 管理コマンド (management/commands/)
Django管理コマンドを提供します：
- `auto_post.py`: 自動投稿コマンド（画像ローテーション機能も実装）
- `process_tweets.py`: スケジュールされたツイートを処理するコマンド

#### ユーティリティ (utils.py)
APIとのやり取りを行うユーティリティ関数を提供：
- `post_tweet()`: X APIを使用して実際にツイートを投稿
- `test_api_connection()`: API接続をテストし、結果を返す

### ログ管理
システムは統一されたログフォーマットを使用します：

#### ログフォーマッタ
- **shell_style**: シェルスタイルのログフォーマット
  - タイムスタンプ
  - プロセスID（SCRIPT_PID環境変数による親プロセスの追跡）
  - ログレベル（INFO/WARN/ERROR）
  - メッセージ

#### ログファイル管理
- 一時ログファイルによる重複排除
- プロセスIDベースのログ分離
- ログの自動ローテーション

### プロセス管理
システムは以下の方法でプロセスを管理します：

- **プロセス追跡**:
  - `SCRIPT_PID`環境変数による親プロセスの追跡
  - 子プロセスへのPID継承
  - ログ出力での一貫したPID表示

- **並行実行制御**:
  - ロックファイルによる多重起動防止
  - プロセス終了時の自動クリーンアップ
  - 異常終了時のロックファイル自動解放

---

## 🚀 インストールと設定

このセクションでは、システムをセットアップするための手順を説明します。

### 前提条件
- Python 3.12以上
- macOS（launchdはmacOS専用）または Linux
- X Developer Portalで作成したAPIキー

### インストール手順

#### 1. リポジトリのクローン
```bash
git clone <repository-url>
cd auto_tweet
```

#### 2. 仮想環境の作成と有効化
```bash
python -m venv .venv
source .venv/bin/activate
```

#### 3. 依存パッケージのインストール
```bash
pip install -r requirements.txt
```

#### 4. 環境変数の設定
`.env.example`をコピーして`.env`ファイルを作成し、必要な環境変数を設定します：
```bash
cp .env.example .env
```

`.env`ファイルを編集し、以下の情報を設定します：
```
X_API_KEY=your_api_key_here
X_API_SECRET=your_api_secret_here
X_ACCESS_TOKEN=your_access_token_here
X_ACCESS_TOKEN_SECRET=your_access_token_secret_here
SECRET_KEY=django_secret_key_here
DEBUG=False
ALLOWED_HOSTS=localhost,127.0.0.1
```

#### 5. データベースの初期化
```bash
cd auto_tweet_project
python manage.py migrate
python manage.py createsuperuser  # 管理者ユーザーを作成
```

#### 6. 実行権限の設定
```bash
chmod +x auto_tweet.sh
chmod +x process_tweets.sh
chmod +x switch_version.sh
```

#### 7. 画像ディレクトリの作成とサンプル画像の配置
```bash
mkdir -p auto_tweet_project/media/auto_post_images
# ここに投稿したい画像を配置します
```

#### 8. 手動での実行テスト
```bash
./auto_tweet.sh
./process_tweets.sh
```

---

## 🔄 自動実行の設定

システムには複数の実行モードがあります。このセクションでは、各環境での自動実行の設定方法を説明します。

### バージョン切り替え機能

このプロジェクトには2つの実行モードがあります：

1. **launchdモード（macOS、デフォルト）**: 
   - macOSのlaunchdを使用してスケジューリング
   - **特徴**: Macが起動している間のみ実行されます
   - **用途**: 常時起動環境やスリープが不要な場合に最適

2. **pmsetモード（macOS）**:
   - macOSのpmsetを使用してスリープからの自動起動をスケジュール
   - **特徴**: Macがスリープ状態でも指定時刻に自動起動して実行し、終了後に再びスリープ
   - **用途**: 省電力が必要な環境や、Macの使用頻度が低い場合に最適
   - **注意点**: sudoの設定が必要（パスワードなしでpmsetを実行できるように）

#### モードの切り替え方法

付属の切り替えスクリプトを使用して簡単に切り替えができます:

```bash
# 現在のモード確認
./switch_version.sh status

# launchdモードに切り替え（起動中のみ実行）
./switch_version.sh launchd

# pmsetモードに切り替え（スリープからの自動起動）
./switch_version.sh pmset

# ヘルプ表示
./switch_version.sh help
```

### macOS - launchdによる設定

launchdを使用してmacOSでシステムを自動実行するための設定方法を説明します。

#### テンプレートファイルの使用方法

本リポジトリには、実環境設定用のテンプレートファイルが含まれています。GitHubから取得した後、ご自身の環境に合わせてカスタマイズしてください。

##### テンプレートファイル
- `launchd_version/com.user.auto_tweet.plist.template` - 自動投稿用のlaunchdジョブ定義テンプレート
- `launchd_version/com.user.process_tweets.plist.template` - ツイート処理用のlaunchdジョブ定義テンプレート

##### 設定手順

1. テンプレートファイルをコピーして`.template`拡張子を削除：

```bash
cp launchd_version/com.user.auto_tweet.plist.template launchd_version/com.user.auto_tweet.plist
cp launchd_version/com.user.process_tweets.plist.template launchd_version/com.user.process_tweets.plist
```

2. ファイル内の`/path/to/auto_tweet`をあなたの実際のプロジェクトパスに置き換え：

```bash
# 例: プロジェクトが/Users/username/Projects/auto_tweetにある場合
sed -i '' "s|/path/to/auto_tweet|/Users/username/Projects/auto_tweet|g" launchd_version/com.user.auto_tweet.plist
sed -i '' "s|/path/to/auto_tweet|/Users/username/Projects/auto_tweet|g" launchd_version/com.user.process_tweets.plist
```

3. プロパティリストファイルをユーザーのLaunchAgentsディレクトリにコピー：

```bash
cp launchd_version/com.user.auto_tweet.plist ~/Library/LaunchAgents/
cp launchd_version/com.user.process_tweets.plist ~/Library/LaunchAgents/
```

4. launchdにプロパティリストファイルをロード：

```bash
launchctl load ~/Library/LaunchAgents/com.user.auto_tweet.plist
launchctl load ~/Library/LaunchAgents/com.user.process_tweets.plist
```

5. バージョン切り替えスクリプトで管理する場合：

```bash
# launchdバージョンに切り替え
./switch_version.sh launchd
```

##### launchdジョブの管理

launchdジョブを管理するための主要コマンド：

```bash
# ジョブの状態確認
launchctl list | grep com.user

# ジョブの手動実行
launchctl start com.user.auto_tweet
launchctl start com.user.process_tweets

# ジョブの停止
launchctl stop com.user.auto_tweet
launchctl stop com.user.process_tweets

# ジョブのアンロード（無効化）
launchctl unload ~/Library/LaunchAgents/com.user.auto_tweet.plist
launchctl unload ~/Library/LaunchAgents/com.user.process_tweets.plist

# ジョブの再ロード（有効化）
launchctl load ~/Library/LaunchAgents/com.user.auto_tweet.plist
launchctl load ~/Library/LaunchAgents/com.user.process_tweets.plist
```

### macOS - pmsetモードの追加設定

pmsetモードではsudoers設定が必要です。以下の手順で設定してください：

1. sudoers設定ファイルの編集:
```bash
sudo visudo -f /etc/sudoers.d/pmset
```

2. 以下の内容を追加（ユーザー名を適宜変更）:
```
username ALL=(ALL) NOPASSWD: /usr/bin/pmset
```

3. 権限設定:
```bash
sudo chmod 440 /etc/sudoers.d/pmset
```

この設定により、パスワード入力なしでpmsetコマンドを実行できるようになります。

### Linux環境 - crontabによる設定

macOS以外のLinux環境などでは、crontabを使用して自動実行をスケジュールできます。

#### crontabの設定手順

1. crontabを編集して自動実行をスケジュールします：

```bash
crontab -e
```

2. 以下のような設定を追加します（パスは実際の環境に合わせて調整してください）：

```
# 自動投稿スクリプト - 90分ごとに実行
*/90 * * * * cd /path/to/auto_tweet && ./auto_tweet.sh >> /path/to/auto_tweet/logs/auto_tweet/auto_tweet.log 2>> /path/to/auto_tweet/logs/auto_tweet/error.log

# ツイート処理スクリプト - 10分ごとに実行
*/10 * * * * cd /path/to/auto_tweet && ./process_tweets.sh >> /path/to/auto_tweet/logs/process_tweets/process_tweets.log 2>> /path/to/auto_tweet/logs/process_tweets/error.log
```

#### crontabのフォーマット説明

crontabのフォーマットは以下の通りです：

```
分 時 日 月 曜日 コマンド
```

- **分**: 0-59
- **時**: 0-23
- **日**: 1-31
- **月**: 1-12
- **曜日**: 0-7（0と7は日曜日）

例：
- `*/90 * * * *` - 90分ごとに実行
- `*/10 * * * *` - 10分ごとに実行
- `0 */1 * * *` - 1時間ごとに実行
- `0 6,12,18 * * *` - 6時、12時、18時に実行

#### crontabでの環境変数の設定

crontabで実行する場合、通常のシェル環境と異なるため、必要な環境変数を設定する必要があります：

```
# 環境変数の設定
PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/path/to/your/python/bin
PYTHONPATH=/path/to/your/python/site-packages

# 自動投稿スクリプト
*/90 * * * * cd /path/to/auto_tweet && ./auto_tweet.sh >> /path/to/auto_tweet/logs/auto_tweet/auto_tweet.log 2>> /path/to/auto_tweet/logs/auto_tweet/error.log
```

#### crontabのログと監視

crontabの実行ログを確認するには：

```bash
# システムログの確認（Linuxの場合）
grep CRON /var/log/syslog

# 独自のログファイルの確認
tail -f /path/to/auto_tweet/logs/auto_tweet/auto_tweet.log
tail -f /path/to/auto_tweet/logs/process_tweets/process_tweets.log
```

---

## 📝 使用方法

このセクションでは、システムの基本的な使用方法を説明します。

### コマンドラインからの実行

#### 自動投稿機能の使用
自動投稿機能はスケジューラによって以下のスケジュールで自動的に実行されますが、必要に応じて手動でも実行できます：
- auto_tweet.sh: 90分ごとに実行
- process_tweets.sh: 10分ごとに実行

#### 手動実行
```bash
# 自動投稿を手動で実行
./auto_tweet.sh

# スケジュールされたツイートを手動で処理
./process_tweets.sh
```

#### launchd手動実行 (macOSのみ)
```bash
# 自動投稿を即時実行
launchctl start com.user.auto_tweet

# ツイート処理を即時実行
launchctl start com.user.process_tweets
```

### Django管理コマンドの直接実行

より細かい制御が必要な場合は、Django管理コマンドを直接実行できます：

```bash
# 仮想環境の有効化
source .venv/bin/activate

# 自動投稿コマンドの実行（スケジュール作成のみ）
cd auto_tweet_project
python manage.py auto_post --text "投稿テキスト"

# 即時投稿
python manage.py auto_post --text "投稿テキスト" --post-now

# ピーク時間帯のフラグを付けて実行
python manage.py auto_post --text "投稿テキスト" --post-now --peak-hour

# スケジュールされたツイートの処理
python manage.py process_tweets

# API接続テストをスキップ
python manage.py process_tweets --skip-api-test

# ピーク時間帯としてAPI接続テストを強制実行
python manage.py process_tweets --force-api-test --peak-hour
```

---

## ⚙️ 設定パラメータ

このセクションでは、システムの主要な設定パラメータについて説明します。

### 環境変数
主要な環境変数の説明：
- `X_API_KEY`: X API Key
- `X_API_SECRET`: X API Secret
- `X_ACCESS_TOKEN`: X Access Token
- `X_ACCESS_TOKEN_SECRET`: X Access Token Secret
- `SECRET_KEY`: Django Secret Key
- `DEBUG`: Djangoデバッグモード（True/False）
- `ALLOWED_HOSTS`: 許可するホスト名のカンマ区切りリスト

### auto_tweet.sh の主要パラメータ
- `MIN_INTERVAL`: 前回実行からの最小間隔（秒）、デフォルト5390秒（約90分）
- `TEXT`: 投稿するテキスト（ハッシュタグを含む）

### process_tweets.sh の主要パラメータ
- `OPTIONS`: process_tweetsコマンドに渡すオプション

---

## 🔍 トラブルシューティング

このセクションでは、よくある問題とその解決方法を説明します。

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
1. スケジューラの状態を確認（launchd: `launchctl list | grep com.user`、cron: `crontab -l`）
2. ログファイルで詳細なエラーを確認
3. スクリプトの実行権限を確認: `chmod +x *.sh`
4. 環境変数の設定を確認

### ロックファイルが残存する問題
**症状**: 「別のスクリプトが実行中です」というメッセージが表示されるが実際には実行されていない  
**原因**: 前回の実行が異常終了し、ロックファイルが削除されなかった  
**解決策**:
1. ロックファイルを手動で削除: `rm .auto_tweet.lock .process_tweets.lock`

---

## 🔧 開発者向け情報

このセクションでは、システムをカスタマイズするための情報を提供します。

### カスタマイズポイント
システムをカスタマイズする主なポイント：

1. **投稿テキストの変更**:
   - `auto_tweet.sh`の`TEXT`変数を編集

2. **投稿間隔の変更**:
   - `auto_tweet.sh`の`MIN_INTERVAL`変数を編集
   - スケジューラの実行間隔を変更（launchdのStartIntervalまたはcrontabの実行間隔）

3. **画像ローテーションの変更**:
   - `SystemSetting.get_next_image_index()`メソッドをカスタマイズ

4. **ピーク時間の変更**:
   - `auto_tweet.sh`と`process_tweets.sh`の`CURRENT_HOUR`チェック条件を変更

### テスト手順
システムのテスト実行方法：
```bash
# テスト実行
cd auto_tweet_project
python manage.py test x_scheduler

# 特定のテストのみ実行
python manage.py test x_scheduler.tests.ModelTests
```

---

## 🔒 セキュリティ考慮事項

システムのセキュリティに関する重要な考慮事項：

- **API認証情報の保護**: APIキーなどの機密情報は`.env`ファイルに保存し、`.gitignore`に含めています
- **CSRF対策**: Djangoの組み込みCSRF保護を使用しています
- **ログファイルのセキュリティ**: ログにはAPIキーの一部のみが記録され、完全なキーは表示されません

---

## 📈 バージョン履歴

システムの主要なリリースと変更点：

### v1.2.1（2025-03-12）
- ログフォーマットの統一
  - shell_styleフォーマッタの導入
  - プロセスID管理の改善
  - 重複ログの排除機能強化
- pmsetスケジュール管理の改善
  - スケジュール重複の防止
  - タイムスタンプベースの比較導入

### v1.2.0（2025-03-11）
- 実行モード切替機能の追加
  - launchdモードとpmsetモードの両方をサポート
  - ディレクトリ構造による分離管理
  - 簡単に切り替え可能なスクリプト追加
- ログ出力の改善
  - プロセスIDベースの一時ログファイル機能
  - 重複ログの排除

### v1.1.0（2025-03-09）
- cron/pmsetからlaunchdへの移行
- 実行安定性の向上
- ログ出力の改善

### v1.0.0（2025-03-08）
- 初回リリース
- 自動投稿機能
- スケジュール管理機能
- API接続テスト最適化

詳細な変更履歴は[CHANGELOG.md](./CHANGELOG.md)を参照してください。

---

## 📄 ライセンス

本プロジェクトはMITライセンスのもとで提供されています。

MIT License

Copyright (c) 2025 Your Name

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

---

## 📞 連絡先・サポート

質問やバグ報告、機能要望などがある場合は、以下の方法でご連絡ください：

- **GitHub Issues**: [Issues](https://github.com/yourusername/auto_tweet/issues)
- **メール**: your.email@example.com

---

*このプロジェクトは継続的に改善されています。フィードバックや貢献を歓迎します！*
