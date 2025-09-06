# 推奨コマンド一覧

## ビルド・実行コマンド

### Rust側
```bash
# ワークスペース全体のビルド
cargo build --all
cargo build --release

# lnxコマンドの実行
cargo run --bin lnx -- status
cargo run --bin lnx -- monitor --realtime

# テスト
cargo test --all

# ドキュメント生成
cargo doc --open

# 依存関係更新
cargo update
```

## Git関連
```bash
# Git LFS設定（大容量ファイル用）
git lfs install
git lfs track "*.wav"
git lfs track "*.aiff"

# ブランチ作成（Linear連携）
git checkout -b feature/LIN-XXX-description

# 状態確認
git status
git diff
```

## システムコマンド (macOS/Darwin)
```bash
# ファイル一覧
ls -la

# ディレクトリ移動
cd <directory>

# ファイル検索
find . -name "*.rs"

# テキスト検索（ripgrep推奨）
rg "pattern"

# プロセス確認
ps aux | grep lnx
```

## プロジェクト管理
```bash
# Linear CLIでタスク確認（要設定）
linear issues --me

# MCP経由でLinearタスク作成
# Claude Code内でlinear-serverツールを使用
```

## タスク完了時の必須コマンド
```bash
# Rust側
cargo test --all
cargo fmt --check
cargo clippy

# 必要に応じてlintツール実行
```