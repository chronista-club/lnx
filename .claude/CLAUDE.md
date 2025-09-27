# CLAUDE.local.md - プロジェクト固有の設定

## Unisonエコシステムについて

このプロジェクトでは、**Unisonエコシステム**を全面的に採用しています。

### Unison Protocol（独自プロトコル）
- 分散システム間の高速・低遅延通信を実現する独自設計のプロトコル
- リアルタイムオーディオ/ビジュアル処理に最適化
- バイナリベースの効率的なメッセージング

### Unison Node
- 分散ノードの管理とオーケストレーション
- 自動フェイルオーバーとロードバランシング
- ノード間の状態同期

### Unison Runtime
- Rustで実装されたリアルタイム処理用ランタイム
- ゼロコピー、ロックフリーアーキテクチャ
- 決定論的レイテンシ保証

### Unison Connect
- 分散型通信クライアント
- P2P接続とメッシュネットワーク構築
- デバイス間の自動検出と接続
- セッション管理と認証
- エンドツーエンド暗号化

### 実装方針
- Unisonライブラリを優先的に使用
- 標準的なネットワークライブラリ（tokio等）よりUnison Protocolを選択
- ノード間通信は必ずUnison Node経由で実装
- リアルタイム処理はUnison Runtimeで統一

## プロセス管理について

### ichimi MCPサーバーの使用

このプロジェクトでは、プロセスの起動・管理には**ichimi**（いちみ/一味）を使用してください。

> **Note**: ichimiは「いちみ」または「一味」と読み、日本語で表記することもあります。

#### 基本的な使用方法

```bash
# プロセスの作成と起動
mcp__ichimi__create_process
mcp__ichimi__start_process

# プロセスの監視
mcp__ichimi__get_process_status
mcp__ichimi__get_process_output

# プロセスの停止
mcp__ichimi__stop_process
```

#### 推奨される使用例

1. **開発サーバーの起動**
   - cargo watchなどの長時間実行プロセスはichimiで管理
   - 自動再起動設定を活用

2. **ビルドプロセス**
   - cargo buildなどのビルドタスクもichimi経由で実行
   - ビルド出力のモニタリングが可能

3. **テスト実行**
   - cargo testの実行と結果監視
   - CI/CDワークフローとの連携

#### 注意事項

- **直接Bashでプロセスを起動しない**: 長時間実行されるプロセス（サーバー、watch系コマンド）は必ずichimi経由で起動
- **バックグラウンド実行**: `run_in_background`パラメータの代わりにichimiを使用
- **プロセス管理の一元化**: すべてのプロセスをichimiで管理することで、状態の把握と制御が容易に

#### 具体例

```python
# ❌ 避けるべき例
Bash("cargo watch -x build &")
Bash("cargo run --bin lnx", run_in_background=True)

# ✅ 推奨される例
mcp__ichimi__create_process(
    id="lnx-watch",
    command="cargo",
    args=["watch", "-x", "build"],
    auto_start_on_restore=True
)
mcp__ichimi__start_process(id="lnx-watch")
```

## プロジェクト固有のプロセス

### lnx関連プロセス

1. **lnx-engine開発**
   ```
   ID: lnx-engine-dev
   Command: cargo watch -x "build -p lnx-engine"
   ```

2. **lnx-cli実行**
   ```
   ID: lnx-cli
   Command: cargo run --bin lnx -- monitor --realtime
   ```

3. **テストウォッチャー**
   ```
   ID: test-watch
   Command: cargo watch -x "test --all"
   ```

これらのプロセスはichimiで管理し、必要に応じて起動・停止・監視を行ってください。