# コードスタイルとコンベンション

## Rustコーディング規約

### 命名規則
- **モジュール・関数**: snake_case（例: `lnx_engine`, `handle_status`）
- **型**: UpperCamelCase（例: `AudioEngine`, `Commands`）
- **定数**: UPPER_SNAKE_CASE

### Cargo設定
- Edition: 2024
- Workspace構成でdependencies共有
- プロファイル最適化:
  - Release: `opt-level = 3`, `lto = true`
  - Dev: `opt-level = 2`（オーディオパフォーマンスのため）

### FFI規約
- `cbindgen`でC/C++バインディング生成
- `#[no_mangle]`と`extern "C"`の使用

## 共通規約

### Gitコミット
- ブランチ名: `feature/LIN-XXX-description`（Linear連携）
- コミットメッセージ: 明確で簡潔に

### ドキュメント
- **メイン言語は日本語**（プロジェクト方針）
- README.mdは詳細なプロジェクト説明を含む
- C4モデルでアーキテクチャを視覚化（必要に応じて）

### テスト
- Rust: `cargo test`でユニットテスト
- TDD推奨（可能な限り）

### セキュリティ
- 秘密情報はコードに含めない
- 環境変数で機密情報を管理

### パフォーマンス
- オーディオ処理の低遅延を最優先
- 目標レイテンシー: <5ms