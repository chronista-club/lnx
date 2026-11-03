# lnx

lnx - wavelet synthesize engine

## 概要

lnx(リンクス)は、**Low-Latency, High-Quality, Human-Friendly** をモットーとした、audio/visual表現のためのライブツールプロジェクトです。

### ✅ 実装済み機能

#### オーディオエンジン（lnx-engine）
- **低遅延オーディオ処理**: CPAL (Cross-Platform Audio Library) による実装
- **リアルタイム音声処理**: ロックフリー設計で安定した音声出力
- **クロスプラットフォーム対応**: macOS、Windows、Linux対応

#### ビートマシン機能
- **16パッドドラムサンプラー**
  - 各パッド個別のボリューム調整
  - ミュート/ソロ機能
  - サンプル動的ロード
- **16ステップシーケンサー**
  - パターンベースのシーケンス
  - リアルタイムパターン編集
  - 最大8パターン保存可能
- **テンポコントロール**
  - BPM: 60-300
  - リアルタイムBPM変更
  - スイング機能（実装予定）
- **オーディオファイル再生**
  - WAV/AIFF形式対応
  - モノラル/ステレオ自動判定
  - mono-to-stereo変換対応

### 🚧 開発中機能
- ウェーブレット合成エンジン設計
- MIDI機器連携
- ビジュアライザー基盤

## 技術スタック

### 言語とフレームワーク
- **Rust** 1.75+
- **CPAL** 0.15+ - クロスプラットフォームオーディオ
- **Slint** 1.9 - Rust製クロスプラットフォームGUIツールキット
- **hound** - WAVファイル処理
- **atomic_float** - ロックフリー浮動小数点演算
- **ringbuf** - ロックフリーリングバッファ

### 🔗 Unisonエコシステム統合
- **Unison Protocol** - 分散システム間の高速通信プロトコル
- **Unison Node** - 分散ノード管理とオーケストレーション
- **Unison Runtime** - リアルタイム処理用ランタイム
- **Unison Connect** - デバイス間接続と同期

### アーキテクチャ
```
lnx/
├── Cargo.toml               # ワークスペース設定
├── crates/
│   ├── lnx-engine/         # オーディオエンジンコア
│   │   ├── src/
│   │   │   ├── engine.rs      # メインエンジン
│   │   │   ├── beatmachine.rs # ビートマシン実装
│   │   │   ├── audio_file.rs  # オーディオファイル処理
│   │   │   ├── devices.rs     # デバイス管理
│   │   │   ├── graph.rs       # オーディオグラフ
│   │   │   └── effects.rs     # エフェクト処理
│   │   └── examples/
│   │       ├── beatmachine_demo.rs
│   │       └── beatmachine_demo_with_samples.rs
│   ├── lnx-cli/            # CLIインターフェース
│   └── lnx-creare/         # ビジュアルクリエーター（計画中）
└── apps/
    └── ios/                # iOS アプリ「lnx creare」（SwiftUI + XcodeGen、メイン開発機は iPad）
```


## セットアップ

### システム要件
- **Rust**: 1.75以降
- **Cargo**: 最新版
- **OS**: macOS 12+、Windows 10+、Ubuntu 20.04+
- **メモリ**: 4GB RAM以上（推奨: 8GB以上）
- **オーディオ**: 低遅延対応のオーディオインターフェース推奨

### インストール

```bash
# リポジトリのクローン
git clone https://github.com/chronista-club/lnx.git
cd lnx

# ビルド
cargo build --release

# テスト実行
cargo test
```

### デモの実行

```bash
# ビートマシンデモ（サンプル音源付き）
cargo run --example beatmachine_demo_with_samples

# シンプルなビートマシンデモ
cargo run --example beatmachine_demo
```

### iOS アプリ（lnx creare）

```bash
cd apps/ios
xcodegen generate            # LnxCreare.xcodeproj を生成（git 管理外）
open LnxCreare.xcodeproj     # Xcode で開く

# コマンドラインから
mise run ios:build           # シミュレータ向けビルド
mise run ios:test            # 単体テスト（既定は iPad シミュレータ）
```

詳細は [apps/ios/README.md](apps/ios/README.md)。

## 使用方法

### CLIコマンド

```bash
# エンジン起動
cargo run --bin lnx -- start

# リアルタイムモニタリング
cargo run --bin lnx -- monitor --realtime

# デバイスリスト表示
cargo run --bin lnx -- devices
```

### Rustライブラリとして使用

```rust
use lnx_engine::{AudioEngine, BeatMachine};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    // エンジン初期化
    let mut engine = AudioEngine::new()?;
    
    // ビートマシン作成
    let beatmachine = BeatMachine::new();
    
    // サンプルロード
    beatmachine.load_sample_to_pad(0, "kick.wav")?;
    beatmachine.load_sample_to_pad(1, "snare.wav")?;
    
    // パターン設定
    beatmachine.set_step(0, 0, true);  // Kick on beat 1
    beatmachine.set_step(1, 4, true);  // Snare on beat 2
    
    // 再生開始
    beatmachine.play();
    engine.start()?;
    
    Ok(())
}
```

## パフォーマンス

### 現在達成している指標
- **オーディオレイテンシ**: < 10ms (ASIO/CoreAudio)
- **CPU使用率**: < 5% (ビートマシン再生時)
- **メモリ使用量**: ~50MB (基本動作時)
- **サンプルレート**: 44.1kHz / 48kHz / 96kHz対応

### 最適化のポイント
- ロックフリーアーキテクチャ採用
- Atomic操作による同期
- ゼロコピーオーディオ処理
- SIMD命令の活用（一部実装済み）

## ロードマップ

### Phase 1: 基盤構築 ✅ 完了
- [x] Rustプロジェクト構成
- [x] CPALオーディオエンジン統合
- [x] ビートマシン実装
- [x] オーディオファイル再生
- [x] ステレオ音声出力対応

### Phase 2: ウェーブレット合成（現在）
- [ ] ウェーブレット変換実装
- [ ] リアルタイム合成エンジン
- [ ] パラメータコントロール
- [ ] プリセット管理

### Phase 3: インターフェース
- [ ] Slint GUIフレームワーク統合（進行中）
- [x] iOS アプリ（lnx creare）のプロジェクト作成 — SwiftUI + XcodeGen、iPad をメイン開発機に
- [ ] ビートマシンコントロールUI
- [ ] MIDI 2.0対応
- [ ] OSC通信
- [ ] タッチコントロール対応

### Phase 4: ビジュアル機能
- [ ] リアルタイムスペクトラム表示
- [ ] ウェーブレット係数可視化
- [ ] 3Dビジュアライザー
- [ ] シェーダーエフェクト

### Phase 5: 拡張機能
- [ ] VST3/AU プラグイン化
- [ ] ネットワーク同期
- [ ] AI支援機能
- [ ] クラウド連携

## トラブルシューティング

### よくある問題と解決方法

#### オーディオが出力されない
```bash
# デバイスリストを確認
cargo run --bin lnx -- devices

# デフォルトデバイスを変更
export LNX_AUDIO_DEVICE="Your Device Name"
```

#### ビルドエラー
```bash
# 依存関係をクリーンアップ
cargo clean
cargo update
cargo build
```

#### レイテンシが大きい
- ASIOドライバー（Windows）またはCoreAudio（macOS）を使用
- バッファサイズを調整: `LNX_BUFFER_SIZE=256`
- リアルタイムカーネル使用（Linux）

## コントリビューション

プロジェクトへの貢献を歓迎します！

### 開発環境セットアップ
```bash
# 開発用ツールインストール
cargo install cargo-watch cargo-nextest

# 開発モードで実行
cargo watch -x run

# テスト監視モード
cargo watch -x nextest
```

### コーディング規約
- `cargo fmt` でフォーマット
- `cargo clippy` で警告チェック
- 全ての公開APIにドキュメント記載
- ユニットテスト追加必須

### プルリクエスト手順
1. フォーク & クローン
2. フィーチャーブランチ作成: `git checkout -b feature/amazing-feature`
3. 変更をコミット: `git commit -m 'Add amazing feature'`
4. プッシュ: `git push origin feature/amazing-feature`
5. プルリクエスト作成

## ライセンス

MIT License (予定)

## 謝辞

- Rustオーディオコミュニティ
- CPALプロジェクトコントリビューター
- 全てのテスターとフィードバック提供者

## お問い合わせ

- GitHub Issues: [https://github.com/chronista-club/lnx/issues](https://github.com/chronista-club/lnx/issues)
- Discord: [準備中]

---

**lnx** - Build the wave, Feel the experience

*Last updated: 2025-10-13*
