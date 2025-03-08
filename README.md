# X API 自動投稿システム

## 概要
本システムは、指定された画像とテキストを定期的にX（旧Twitter）へ自動投稿するためのツールです。DjangoフレームワークとTweepy（X API SDK）を使用して、安定した投稿スケジュール管理とAPIレート制限の最適な管理を実現しています。マシンがスリープ状態にある場合でも、自動的に復帰して投稿処理を行う機能も備えています。

## 主な機能

- **X APIを使用した自動投稿**: 90分ごとに安定して自動投稿を実行
- **画像付き投稿対応**: テキストだけでなく画像も含めた投稿が可能
- **スケジュール管理**: 指定した日時に投稿するスケジュール機能
- **画像の自動ローテーション**: 複数画像を順番に使用して投稿を多様化
- **投稿制限管理**: APIレート制限（1日15回）を考慮した制御
- **API接続テスト最適化**: API接続テストをピーク時間帯（6時、12時、18時）のみに限定
- **レート制限対応**: "Too Many Requests"エラー時の自動再試行機能
- **スリープ復帰機能**: macOSのスリープ状態からの自動復帰と実行
- **並行実行の防止**: ロックファイルによる同時実行防止機能

## 使用技術
- **言語**: Python 3.12
- **フレームワーク**: Django 5.0+
- **API連携**: Tweepy 4.14.0+（X API v2対応）
- **データベース**: SQLite（Django ORM）
- **スケジューリング**: crontab（launchd推奨）
- **スリープ制御**: pmset（macOS）
- **環境変数管理**: python-dotenv

## 詳細なディレクトリ構成
```
auto_tweet/
├── auto_tweet_project/        # Djangoプロジェクトディレクトリ
│   ├── core/                  # プロジェクト設定
│   │   ├── __init__.py
│   │   ├── asgi.py
│   │   ├── settings.py        # Django設定ファイル
│   │   ├── urls.py            # URLルーティング設定
│   │   └── wsgi.py
│   ├── x_scheduler/           # 自動投稿管理アプリケーション
│   │   ├── __init__.py
│   │   ├── admin.py           # 管理画面設定
│   │   ├── apps.py
│   │   ├── forms.py           # フォーム定義
│   │   ├── management/        # カスタムコマンド
│   │   │   └── commands/
│   │   │       ├── auto_post.py       # 自動投稿コマンド
│   │   │       └── process_tweets.py  # ツイート処理コマンド
│   │   ├── migrations/        # データベースマイグレーション
│   │   ├── models.py          # データモデル定義
│   │   ├── templates/         # HTMLテンプレート
│   │   ├── tests.py           # テストケース
│   │   ├── urls.py            # アプリ内URLルーティング
│   │   ├── utils.py           # ユーティリティ関数
│   │   └── views.py           # ビュー定義
│   ├── media/                 # メディアファイル
│   │   ├── auto_post_images/  # 自動投稿用画像
│   │   └── tweet_images/      # アップロードされた画像
│   ├── static/                # 静的ファイル
│   └── manage.py              # Django管理スクリプト
├── auto_tweet.sh              # 自動投稿実行スクリプト
├── process_tweets.sh          # ツイート処理実行スクリプト
├── .env                       # 環境変数設定ファイル（gitignoreに含まれる）
├── .env.example               # 環境変数の例
├── .gitignore                 # Git除外設定
├── .venv/                     # Python仮想環境（gitignoreに含まれる）
├── auto_post.log              # 自動投稿ログファイル
├── process_tweets.log         # ツイート処理ログファイル
├── requirements.txt           # 依存パッケージリスト
└── README.md                  # このファイル
```

## 各コンポーネントの詳細説明

### 1. auto_tweet.sh
自動投稿の主要な実行スクリプトです。以下の機能を提供します：
- 90分間隔での実行制御（前回実行から90分経過していない場合は実行をスキップ）
- ピーク時間（6時、12時、18時）の特別処理
- 夜間（22時〜6時）実行後のスリープ復帰
- ロックファイルによる並行実行防止
- 詳細なログ記録
- レート制限エラーの検出と自動再試行
- 次回実行のpmsetによる自動起動設定

### 2. process_tweets.sh
スケジュールされたツイートを処理するスクリプトです。以下の機能を提供します：
- 10分間隔での定期実行
- ロックファイルによる並行実行防止
- API接続テストの最適化
- レート制限エラーの自動再試行
- 夜間実行時のスリープ復帰
- 詳細なログ記録

### 3. x_scheduler Django アプリケーション

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
- macOS（他のUnixベースのシステムでも動作しますが、スリープ復帰機能はmacOS専用）
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
# ファイル名は image_0001.png, image_0002.png のように連番で命名します
```

### 8. 手動での実行テスト
```bash
./auto_tweet.sh
./process_tweets.sh
```

### 9. cronによる自動実行の設定
```bash
crontab -l > mycron
cat << EOF >> mycron
# 90分ごとに自動投稿を実行
0 0,3,6,9,12,15,18,21 * * * cd $(pwd) && ./auto_tweet.sh
30 1,4,7,10,13,16,19,22 * * * cd $(pwd) && ./auto_tweet.sh

# 10分ごとにスケジュールされたツイートを処理
# auto_tweet.shとの実行タイミングの競合を避けるため、5分から開始
5,15,25,35,45,55 * * * * cd $(pwd) && ./process_tweets.sh
EOF
crontab mycron
rm mycron
```

### 10. macOSのsudoers設定（pmsetコマンドの使用権限）
```bash
sudo visudo -f /etc/sudoers.d/pmset
```
以下の行を追加します（usernameはあなたのユーザー名に置き換え）：
```
username ALL = (root) NOPASSWD: /usr/bin/pmset
```

### 11. macOSのプライバシー設定
1. システム環境設定 > セキュリティとプライバシー > フルディスクアクセス
2. ターミナルアプリにアクセス権を付与

## 使用方法

### 自動投稿機能の使用
自動投稿機能はcronによって定期的に実行されます。以下のパターンで実行されます：
- 0時、3時、6時、9時、12時、15時、18時、21時の0分
- 1時30分、4時30分、7時30分、10時30分、13時30分、16時30分、19時30分、22時30分

### 手動実行
```bash
# 自動投稿を手動で実行
./auto_tweet.sh

# スケジュールされたツイートを手動で処理
./process_tweets.sh
```

### Django管理コマンドの直接実行
```bash
# 仮想環境の有効化
source .venv/bin/activate

# 自動投稿コマンドの実行（スケジュール作成のみ）
cd auto_tweet_project
python manage.py auto_post --text "#AI画像"

# 即時投稿
python manage.py auto_post --text "#AI画像" --post-now

# ピーク時間帯のフラグを付けて実行
python manage.py auto_post --text "#AI画像" --post-now --peak-hour

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

### cronジョブが実行されない
**症状**: 予定された時間に自動投稿が実行されない
**原因**: cronの設定問題、権限問題、またはスクリプトのエラー
**解決策**:
1. `crontab -l`でcron設定を確認
2. ログファイル（auto_post.log, process_tweets.log）で詳細なエラーを確認
3. スクリプトのパスが絶対パスになっているか確認
4. スクリプトの実行権限を確認: `chmod +x *.sh`

### ロックファイルが残存する問題
**症状**: 「別のスクリプトが実行中です」というメッセージが表示されるが実際には実行されていない
**原因**: 前回の実行が異常終了し、ロックファイルが削除されなかった
**解決策**:
1. ロックファイルを手動で削除: `rm .auto_tweet.lock .process_tweets.lock`

### pmsetコマンドのエラー
**症状**: 「自動起動スケジュールの設定に失敗しました」というメッセージ
**原因**: pmsetコマンドの実行権限がない
**解決策**:
1. sudoersファイルの設定を確認
2. システム環境設定のフルディスクアクセス権限を確認

## パフォーマンスチューニング

### 投稿頻度の最適化
APIレート制限と投稿の効果のバランスを考慮して、適切な投稿頻度を設定します。現在は90分間隔（1日に16回）に設定されていますが、これは以下の方法で調整できます：
1. `auto_tweet.sh`の`MIN_INTERVAL`パラメータを変更
2. crontabの実行スケジュールを変更

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
   - crontabの実行スケジュールを変更

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