# lnx プロジェクト概要

## プロジェクトの目的
lnx（リンクス）は、**wavelet synthesize engine**として、Low-Latency, High-Quality, Human-Friendlyをモットーとした、audio/visual表現のためのライブツールプロジェクトです。

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
- **言語**: Rust (edition 2024)
- **オーディオ処理**: cpal, dasp, coreaudio-rs
- **MIDI**: midir
- **非同期処理**: tokio
- **FFI**: cbindgen, libc
- **シリアライゼーション**: serde

## プロジェクト構造

```
lnx-experience/
├── crates/              # Rustクレート
│   ├── lnx-engine/      # オーディオエンジン
│   └── lnx-cli/         # CLIツール
├── docs/                # ドキュメント
└── Cargo.toml           # ワークスペース設定
```

## 主要な機能
- wavelet synthesize による音声処理
- リアルタイムオーディオ処理（低遅延目標: <5ms）
- MIDIデバイス対応
- 高品質オーディオ処理

## 開発状況
- Rustオーディオエンジン: 🚧
- CLIツール: ✅
- wavelet synthesize実装: 計画中