# X API 自動投稿システム

## 概要
本システムは、指定された画像とテキストを定期的にX（旧Twitter）へ自動投稿するためのツールです。DjangoフレームワークとTweepy（X API SDK）を使用して、安定した投稿スケジュール管理とAPIレート制限の最適な管理を実現しています。macOSのlaunchdとpmsetの両方に対応しており、使用環境に合わせて選択できます。

## 主な機能

- **X APIを使用した自動投稿**: 90分ごとに安定して自動投稿を実行
- **画像付き投稿対応**: テキストだけでなく画像も含めた投稿が可能
- **スケジュール管理**: 指定した日時に投稿するスケジュール機能
- **画像の自動ローテーション**: 複数画像を順番に使用して投稿を多様化
- **投稿制限管理**: APIレート制限（1日15回）を考慮した制御
- **API接続テスト最適化**: API接続テストをピーク時間帯（6時、12時、18時）のみに限定
- **レート制限対応**: "Too Many Requests"エラー時の自動再試行機能
- **並行実行の防止**: ロックファイルによる同時実行防止機能
- **実行モード切替**: launchdとpmsetの両方に対応し、環境に合わせて切替可能

## 使用技術
- **言語**: Python 3.12
- **フレームワーク**: Django 5.0+
- **API連携**: Tweepy 4.14.0+（X API v2対応）
- **データベース**: SQLite（Django ORM）
- **スケジューリング**: macOS launchd / pmset
- **環境変数管理**: python-dotenv

## ファイル構造

```
.
├── auto_tweet_project/         # Djangoプロジェクトディレクトリ
│   ├── auto_tweet/             # アプリケーションディレクトリ
│   │   ├── migrations/         # DBマイグレーションファイル
│   │   ├── __init__.py
│   │   ├── admin.py            # 管理画面設定
│   │   ├── apps.py             # アプリケーション設定
│   │   ├── models.py           # データモデル
│   │   ├── tests.py            # テスト
│   │   └── views.py            # ビュー関数
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

## 各コンポーネントの詳細説明

### 1. auto_tweet.sh
自動投稿の主要な実行スクリプトです。以下の機能を提供します：
- 90分間隔での実行制御（前回実行から90分経過していない場合は実行をスキップ）
- ピーク時間（6時、12時、18時）の特別処理
- ロックファイルによる並行実行防止
- 詳細なログ記録
- レート制限エラーの検出と自動再試行
- 次回実行管理（バージョンによりlaunchdまたはpmsetで管理）

### 2. process_tweets.sh
スケジュールされたツイートを処理するスクリプトです。以下の機能を提供します：
- 10分間隔での定期実行
- ロックファイルによる並行実行防止
- API接続テストの最適化
- レート制限エラーの自動再試行
- 詳細なログ記録

### 3. switch_version.sh
実行モードを切り替えるためのユーティリティスクリプトです：
- launchdバージョンとpmsetバージョンの切り替えを管理
- 適切なシンボリックリンクを設定
- 現在のバージョン確認機能
- launchdジョブの自動ロード/アンロード

### 4. x_scheduler Django アプリケーション

#### models.py
データベースモデルを定義しています：
- `TweetSchedule`: ツイートのスケジュール情報を管理
- `DailyPostCounter`: 1日の投稿数を記録し、制限を管理
- `SystemSetting`: API接続テスト状況など、システム設定を管理

#### management/commands/
Django管理コマンドを提供します：
- `auto_post.py`: 自動投稿コマンド（画像ローテーション機能も実装）
- `process_tweets.py`: スケジュールされたツイートを処理するコマンド

#### utils.py
APIとのやり取りを行うユーティリティ関数を提供：
- `post_tweet()`: X APIを使用して実際にツイートを投稿
- `test_api_connection()`: API接続をテストし、結果を返す

## 詳細なインストール手順

### 前提条件
- Python 3.12以上
- macOS（launchdはmacOS専用）
- X Developer Portalで作成したAPIキー

### 1. リポジトリのクローン
```bash
git clone <repository-url>
cd auto_tweet
```

### 2. 仮想環境の作成と有効化
```bash
python -m venv .venv
source .venv/bin/activate
```

### 3. 依存パッケージのインストール
```bash
pip install -r requirements.txt
```

### 4. 環境変数の設定
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

### 5. データベースの初期化
```bash
cd auto_tweet_project
python manage.py migrate
python manage.py createsuperuser  # 管理者ユーザーを作成
```

### 6. 実行権限の設定
```bash
chmod +x auto_tweet.sh
chmod +x process_tweets.sh
```

### 7. 画像ディレクトリの作成とサンプル画像の配置
```bash
mkdir -p auto_tweet_project/media/auto_post_images
# ここに投稿したい画像を配置します
```

### 8. 手動での実行テスト
```bash
./auto_tweet.sh
./process_tweets.sh
```

### 9. launchdによる自動実行の設定
launchdプロパティリストファイルを編集して、正しいパスを設定します。以下はプロパティリストファイルの例です：

```xml
<!-- com.user.auto_tweet.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.auto_tweet</string>
    <key>ProgramArguments</key>
    <array>
        <string>/path/to/auto_tweet.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>5400</integer>
    <key>StandardOutPath</key>
    <string>/path/to/logs/auto_tweet/auto_tweet.log</string>
    <key>StandardErrorPath</key>
    <string>/path/to/logs/auto_tweet/error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:/path/to/pyenv/shims</string>
        <key>PYTHONPATH</key>
        <string>/path/to/python/site-packages</string>
    </dict>
</dict>
</plist>
```

プロパティリストファイルのパスを実際の環境に合わせて変更します：

```bash
# com.user.auto_tweet.plistを編集
sed -i '' "s|/path/to/auto_tweet.sh|$(pwd)/auto_tweet.sh|g" com.user.auto_tweet.plist
sed -i '' "s|/path/to/logs/auto_tweet/auto_tweet.log|$(pwd)/logs/auto_tweet/auto_tweet.log|g" com.user.auto_tweet.plist
sed -i '' "s|/path/to/logs/auto_tweet/error.log|$(pwd)/logs/auto_tweet/error.log|g" com.user.auto_tweet.plist

# com.user.process_tweets.plistを編集
sed -i '' "s|/path/to/process_tweets.sh|$(pwd)/process_tweets.sh|g" com.user.process_tweets.plist
sed -i '' "s|/path/to/logs/process_tweets/process_tweets.log|$(pwd)/logs/process_tweets/process_tweets.log|g" com.user.process_tweets.plist
sed -i '' "s|/path/to/logs/process_tweets/error.log|$(pwd)/logs/process_tweets/error.log|g" com.user.process_tweets.plist
```

プロパティリストファイルをユーザーのLaunchAgentsディレクトリにコピーします：
```bash
cp com.user.auto_tweet.plist ~/Library/LaunchAgents/
cp com.user.process_tweets.plist ~/Library/LaunchAgents/
```

launchdにプロパティリストファイルをロードします：
```bash
launchctl load ~/Library/LaunchAgents/com.user.auto_tweet.plist
launchctl load ~/Library/LaunchAgents/com.user.process_tweets.plist
```

### launchdプロパティリストファイル
- `Label`: ジョブを識別するための一意の名前
- `ProgramArguments`: 実行するコマンドとその引数
- `StartInterval`: 実行間隔（秒）（auto_tweet: 5400秒、process_tweets: 600秒）
- `StandardOutPath`: 標準出力のログファイルパス
- `StandardErrorPath`: 標準エラーのログファイルパス
- `EnvironmentVariables`: 環境変数の設定（PATH、PYTHONPATHなど）

### launchdジョブの管理
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

## 使用方法

### 自動投稿機能の使用
自動投稿機能はlaunchdによって以下のスケジュールで実行されます：
- auto_tweet.sh: 90分ごとに実行
- process_tweets.sh: 10分ごとに実行

### 手動実行
```bash
# 自動投稿を手動で実行
./auto_tweet.sh

# スケジュールされたツイートを手動で処理
./process_tweets.sh
```

### launchd手動実行
```bash
# 自動投稿を即時実行
launchctl start com.user.auto_tweet

# ツイート処理を即時実行
launchctl start com.user.process_tweets
```

### Django管理コマンドの直接実行
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

## 設定パラメータ

### 環境変数
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

## トラブルシューティング

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

### launchdジョブが実行されない
**症状**: 予定された時間に自動投稿が実行されない
**原因**: launchdの設定問題、権限問題、またはスクリプトのエラー
**解決策**:
1. `launchctl list | grep com.user` でlaunchdジョブの状態を確認
2. ログファイル（launchd_auto_tweet.log, launchd_process_tweets.log）で詳細なエラーを確認
3. プロパティリストファイルのパスが絶対パスになっているか確認
4. スクリプトの実行権限を確認: `chmod +x *.sh`

### ロックファイルが残存する問題
**症状**: 「別のスクリプトが実行中です」というメッセージが表示されるが実際には実行されていない
**原因**: 前回の実行が異常終了し、ロックファイルが削除されなかった
**解決策**:
1. ロックファイルを手動で削除: `rm .auto_tweet.lock .process_tweets.lock`

## パフォーマンスチューニング

### 投稿頻度の最適化
APIレート制限と投稿の効果のバランスを考慮して、適切な投稿頻度を設定します。現在は90分間隔（1日に16回）に設定されていますが、これは以下の方法で調整できます：
1. `auto_tweet.sh`の`MIN_INTERVAL`パラメータを変更
2. launchdの実行スケジュールを変更

### APIテストの最適化
APIレート制限を最大限に活用するため、API接続テストは以下の条件で行われます：
1. 処理対象のツイートが存在する場合のみ実行
2. 1日1回のみ実行（ピーク時間帯で実行された場合はその情報も記録）
3. `--force-api-test`フラグで強制実行可能

## 開発者向け情報

### カスタマイズポイント
システムをカスタマイズする主なポイント：

1. **投稿テキストの変更**:
   - `auto_tweet.sh`の`TEXT`変数を編集

2. **投稿間隔の変更**:
   - `auto_tweet.sh`の`MIN_INTERVAL`変数を編集
   - launchdの実行スケジュールを変更

3. **画像ローテーションの変更**:
   - `SystemSetting.get_next_image_index()`メソッドをカスタマイズ

4. **ピーク時間の変更**:
   - `auto_tweet.sh`と`process_tweets.sh`の`CURRENT_HOUR`チェック条件を変更

### 主要クラスとメソッド

#### TweetSchedule（モデル）
ツイートのスケジュール情報を管理します。
- `scheduled_time`: 投稿予定時刻
- `content`: 投稿内容
- `image`: 投稿画像
- `status`: 投稿ステータス（0:待機中、1:投稿済み、2:失敗）
- `error_message`: エラーメッセージ

#### DailyPostCounter（モデル）
1日の投稿数を記録し、制限を管理します。
- `date`: 日付
- `count`: 投稿数
- `max_daily_posts`: 1日の最大投稿数
- `increment()`: 投稿カウントをインクリメント
- `is_limit_reached()`: 制限に達したかチェック

#### SystemSetting（モデル）
システム設定を管理します。
- `get_value()`, `set_value()`: キーバリューの取得と設定
- `is_api_test_done_today()`: 今日のAPI接続テスト実施確認
- `mark_api_test_done()`: API接続テスト実施を記録
- `get_last_image_index()`, `get_next_image_index()`: 画像インデックス管理

### テスト手順
```bash
# テスト実行
cd auto_tweet_project
python manage.py test x_scheduler

# 特定のテストのみ実行
python manage.py test x_scheduler.tests.ModelTests
```

## セキュリティ考慮事項

### API認証情報の保護
- APIキーなどの機密情報は`.env`ファイルに保存し、`.gitignore`に含めています
- リポジトリにAPIキーをコミットしないよう注意してください

### クロスサイトリクエストフォージェリ（CSRF）対策
- Djangoの組み込みCSRF保護を使用しています

### ログファイルのセキュリティ
- ログにはAPIキーの一部のみが記録され、完全なキーは表示されません

## バージョン履歴

### v1.2.0（2025-03-11）
- 実行モード切替機能の追加
  - launchdモードとpmsetモードの両方をサポート
  - ディレクトリ構造による分離管理
  - 簡単に切り替え可能なスクリプト追加
  - READMEの更新と設定方法の追加
- ログ出力の改善
  - プロセスIDベースの一時ログファイル機能
  - 重複ログの排除

### v1.1.1（2025-03-10）
- ログファイル構造の整理
  - ログファイルをlogs/ディレクトリに集約
  - 機能別にログを分類（auto_tweet/およびprocess_tweets/）
  - 標準出力とエラー出力の分離

### v1.1.0（2025-03-09）
- cron/pmsetからlaunchdへの移行
  - スケジュール管理をcronからlaunchdに移行
  - スリープ制御を内部管理からlaunchdへ移行
  - スクリプトからpmset関連のコードをコメントアウト
- 実行安定性の向上
  - Python環境の依存性問題を解決
  - 環境変数の適切な設定
- ログ出力の改善
  - launchd専用のログファイルを追加
  - エラーログと標準ログの分離
- 不要ファイルの整理
  - __pycache__ディレクトリの削除
  - .DS_Storeファイルの削除
  - 未使用ファイルの削除

### v1.0.0（2025-03-08）
- 初回リリース
- 自動投稿機能
- スケジュール管理機能
- API接続テスト最適化

### v0.9.0（2024-12-15）
- ベータ版リリース
- 画像ローテーション機能追加
- APIレート制限対応

### v0.5.0（2024-10-01）
- アルファ版リリース
- 基本的な投稿機能実装

## ライセンス
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

## 連絡先・サポート
質問やバグ報告は[Issues](https://github.com/yourusername/auto_tweet/issues)で受け付けています。

## バージョン切り替え機能

このプロジェクトには2つの実行モードがあります：

1. **launchdモード（デフォルト）**: 
   - macOSのlaunchdを使用してスケジューリング
   - **特徴**: Macが起動している間のみ実行されます
   - **用途**: 常時起動環境やスリープが不要な場合に最適

2. **pmsetモード**:
   - macOSのpmsetを使用してスリープからの自動起動をスケジュール
   - **特徴**: Macがスリープ状態でも指定時刻に自動起動して実行し、終了後に再びスリープ
   - **用途**: 省電力が必要な環境や、Macの使用頻度が低い場合に最適
   - **注意点**: sudoの設定が必要（パスワードなしでpmsetを実行できるように）

### モードの切り替え方法

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

### pmsetモードの設定（追加手順）

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

## テンプレートファイルの使用方法

本リポジトリには、実環境設定用のテンプレートファイルが含まれています。GitHubから取得した後、ご自身の環境に合わせてカスタマイズしてください。

### launchdプロパティリストのテンプレート

以下のテンプレートファイルを編集して使用します：

- `launchd_version/com.user.auto_tweet.plist.template` - 自動投稿用のlaunchdジョブ定義テンプレート
- `launchd_version/com.user.process_tweets.plist.template` - ツイート処理用のlaunchdジョブ定義テンプレート

### テンプレートからの設定手順

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

テンプレートファイルは環境設定のサンプルとして提供されており、実際の使用時は必ずあなたの環境に合わせて適切なパスと設定に変更してください。