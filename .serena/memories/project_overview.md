# lnx プロジェクト概要

## プロジェクトの目的
lnx（リンクス）は、**wavelet synthesize engine**として、Low-Latency, High-Quality, Human-Friendlyをモットーとした、audio/visual表現のためのライブツールプロジェクトです。

## 🔗 Unisonエコシステム統合

このプロジェクトでは**Unisonエコシステム**を全面的に採用しています：

### Unison Protocol
- **GitHub**: [https://github.com/chronista-club/unison-protocol](https://github.com/chronista-club/unison-protocol)
- **型安全な高速通信フレームワーク**
- KDL (KDL Document Language) ベースのスキーマ定義
- QUIC トランスポート（WebSocketより50%低遅延、850K msg/秒）
- TLS 1.3暗号化標準搭載
- 双方向ストリーミング対応

### Unison Node
- **GitHub**: [https://github.com/chronista-club/unison-node](https://github.com/chronista-club/unison-node)
- **分散ノード管理システム**
- QUICプロトコルベースの高速ノード間通信
- mDNSによる自動サービスディスカバリー
- ヘルスチェック機能と自動フェイルオーバー
- Prometheusメトリクス対応
- 将来的にRaftコンセンサス対応予定

### その他のUnison Components（計画中）
- **Unison Runtime**: リアルタイム処理用ランタイム
- **Unison Connect**: 分散型通信クライアント（P2P、メッシュネットワーク）

## 技術統一方針

### 🦀 実装言語: Rust統一
lnx系プロダクトは、**出来るだけ実装言語はRustで統一**します。

#### 統一の理由
- **パフォーマンス**: リアルタイムオーディオ処理に必要な低レイテンシーを実現
- **メモリ安全性**: クラッシュフリーなライブパフォーマンスを保証
- **並行処理**: 複雑なオーディオグラフの並列処理が安全に実装可能
- **エコシステム**: 高品質なオーディオライブラリ（cpal, dasp等）が豊富
- **FFI**: C/C++ライブラリとの連携が容易
- **クロスプラットフォーム**: macOS/Windows/Linux対応

#### 例外ケース
以下の場合のみ、他言語の使用を検討：
- プラットフォーム固有のGUI（SwiftUI/Objective-C on macOS）
- 既存の高度に最適化されたC/C++ライブラリの直接利用
- WebAssemblyによるブラウザ対応

## 技術スタック

### Rust側
- **言語**: Rust (edition 2021以降)
- **オーディオ処理**: cpal, dasp, coreaudio-rs
- **MIDI**: midir
- **非同期処理**: tokio 1.40+
- **FFI**: cbindgen, libc
- **シリアライゼーション**: serde, bincode

### Unisonライブラリ
- **unison-protocol**: KDL型安全通信、QUICトランスポート
- **unison-node**: 分散ノード管理、サービスディスカバリー
- **quinn**: QUIC実装（0.11+）
- **rustls**: TLS 1.3（0.23+）
- **mdns-sd**: mDNSサービス検出（0.11+）

## プロジェクト構造

```
lnx/
├── crates/              # Rustクレート
│   ├── lnx-engine/      # オーディオエンジン
│   ├── lnx-cli/         # CLIツール
│   └── lnx-visualizer/  # ビジュアライザー（計画中）
├── docs/                # ドキュメント
│   └── ARCHITECTURE.md  # アーキテクチャ設計書
└── Cargo.toml           # ワークスペース設定
```

## 主要な機能
- wavelet synthesize による音声処理
- リアルタイムオーディオ処理（低遅延目標: <5ms）
- MIDIデバイス対応
- 高品質オーディオ処理
- **分散処理対応**（Unison Node）
- **QUIC通信**（Unison Protocol）
- **自動ノード検出**（mDNS）

## 開発状況
- Rustオーディオエンジン: 🚧
- CLIツール: ✅
- wavelet synthesize実装: 計画中
- Unison Protocol統合: 🚧 実装中
- Unison Node統合: 🚧 実装中

## アーキテクチャ方針
- **通信**: Unison Protocol（QUIC）を使用
- **ノード管理**: Unison Nodeで実装
- **サービス検出**: mDNS自動検出
- **メトリクス**: Prometheus形式で出力
- **セキュリティ**: TLS 1.3標準搭載