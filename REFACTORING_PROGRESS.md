# シェルスクリプトリファクタリング進捗管理

## 目的

シェルスクリプト (`pmset_version`, `launchd_version`) の可読性・保守性を向上させる。

## 対象スクリプト

*   `scripts/pmset_version/auto_tweet.sh`
*   `scripts/pmset_version/process_tweets.sh`
*   `scripts/launchd_version/auto_tweet.sh`
*   `scripts/launchd_version/process_tweets.sh`

## タスクリスト

| タスク内容                        | 対象スクリプト                     | 担当 | 進捗      | 備考                                   |
| :-------------------------------- | :--------------------------------- | :--- | :-------- | :------------------------------------- |
| 共通設定の外部ファイル化          | 全て                               | -    | ✅ 完了   | `scripts/config/common_config.sh` 作成 |
| 共通関数の外部ファイル化          | 全て                               | -    | ✅ 完了   | `scripts/functions/common_functions.sh` 作成 |
| 設定/関数ファイルの `source` 化   | 全て                               | -    | ✅ 完了   | 設定・関数ファイルをsource             |
| パス/定数の変数化                 | 全て                               | -    | ✅ 完了   | 共通設定ファイルに集約                 |
| 主要処理の関数化とコメント追加    | 全て                               | -    | ✅ 完了   | main 関数内の処理を関数化、一部関数を共通化 |
| エラーハンドリング (`set`/`trap`) | 全て                               | -    | ✅ 完了   | `set -euo pipefail` 追加               |
| ログ出力の統一と関数化            | 全て                               | -    | ✅ 完了   | 共通 `log` 関数導入                     |
| `shellcheck` 導入と修正           | 全て                               | -    | ⚠️確認済  | 修正スキップ (SC2034, SC2155等)     |
| `.sh` ファイルの実行権限確認     | 全て                               | -    | ✅ 完了   | `chmod +x` 実行済み                 |

</rewritten_file> 