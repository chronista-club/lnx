# lnx

lnx（リンクス）— 機器と場をつなぐ Signal Hub + Routing と、ヴィジョンクリエイティブツール **lnx creare**。

## 概要

lnx（リンクス）は、機器と場をつなぐもの。読みの「リンクス」は links（つなぐもの）に通じます。
**Low-Latency, High-Quality, Human-Friendly** をモットーとした、リアルタイム表現と外部機器ルーティングのためのプロジェクトです。
画面と文書では小文字の lnx と書きます（大文字の LNX は Linux と読まれやすいため。識別子は変えない。[spec 01](docs/spec/01-core-concept.md)「名前と表記」）。

## アーキテクチャ

```
lnx/
├── Cargo.toml               # Rust ワークスペース設定
├── crates/
│   ├── lnx-protocol/        # [data + calculations] Gear の使用権・引き継ぎ・wire 型の純粋状態機械
│   ├── lnx-gear/            # [calculations] Gear ごとの入力変換・SysEx/ROTO 表示投影（maru / ROTO / Keystage / LPD8 等）
│   ├── lnx-client/          # [actions] Rust SDK（lnx-server の gear channel クライアント）
│   └── lnx-server/          # [actions] lnx サーバ（Unison / QUIC、Bonjour _lnx._udp、Signal Hub + Router）
├── clients/
│   └── swift/               # [actions] Swift SDK「LnxClient」（Swift Package、Ladyland / Mac 用）
├── apps/
│   └── ios/                 # iOS / macOS アプリ「lnx creare」（SwiftUI + XcodeGen）
│                            #   iPad / iPhone: lnx-server へ常時接続する窓 + Gear & Desk（机配置）
│                            #   Mac: メニューバー常駐管理（SMAppService）+ Gear ステータス / トレース / ログ + ペアリング QR
├── gear/                    # Gear の 3D 資産（意味の層 <id>/gear.json + 見た目の層 <id>/<id>.blend、build.py / check.py）
├── config/examples/         # 机配置スキーマ（desk-home.kdl / desk-studio.kdl）
├── formal/
│   ├── lean/                # Lean 4（4.36.0、公理ゼロ定理証明）: Broker 排他・二段階 handoff・7bit/14bit 変換・SysEx 安全性
│   └── quint/               # Quint（0.33.1、6 モード反例探索）: Gear 引き継ぎ状態機械の設計規則検査
├── tasks/                   # mise の開発タスク（Ruby）
└── docs/                    # ドキュメント（spec / design / guide / archive）
```

文書の索引は [docs/README.md](docs/README.md)（[spec 01](docs/spec/01-core-concept.md)、[spec 02](docs/spec/02-creare.md)、[design 01](docs/design/01-lnx-server-link.md)、[design 02](docs/design/02-architecture.md)、[guide 01](docs/guide/01-development.md)）。

## セットアップと使い方

### 要件
- **Rust**: 1.99.1（[`rust-toolchain.toml`](rust-toolchain.toml) で固定。rustup が自動で選ぶ）
- **Xcode**: 27 以上（iOS / macOS の `lnx creare` ビルド用）
- **mise**: タスク実行と `xcodegen` の管理（[`.mise.toml`](.mise.toml)）

### lnx サーバ

```bash
mise run server:run          # この Mac で起動（[::]:12730、Bonjour _lnx._udp で名乗る）
mise run server:test         # 実 QUIC の往復を含むテストと常駐タスクのテスト
```

iPad の lnx creare はここへ常時つなぎ、名乗りと heartbeat を受け、知っているサーバの一覧から画面を切り替えます。
設計は [docs/design/01-lnx-server-link.md](docs/design/01-lnx-server-link.md)。

### lnx creare（iOS / macOS）

```bash
mise run ios:test            # 単体テスト + UI テスト（既定は iPad シミュレータ）
mise run ios:run             # iPad シミュレータで起動
mise run mac:test            # Mac 版の単体テスト（メニューバー・同梱サーバ・表記検査）
mise run mac:run             # Mac 版をビルドして起動
mise run mac:install         # Mac 版を ~/Applications に入れて起動（メニューバーから lnx-server を常駐登録）
```

詳細は [apps/ios/README.md](apps/ios/README.md) および [docs/guide/01-development.md](docs/guide/01-development.md)。

## ライセンス

[MIT License](LICENSE-MIT) または [Apache License 2.0](LICENSE-APACHE)。
