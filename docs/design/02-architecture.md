# 02. lnx の構成 — Unison の上に載せる Signal Hub + Routing

> **Status**: Draft（Status log 参照）
> **Related**: [spec 01](../spec/01-core-concept.md)（機器と場をつなぐもの、場の同期）、[spec 02](../spec/02-creare.md)（統合のハブ、UI の方針）、[design 01](01-lnx-server-link.md)（最初の実装）、`mem_1ChTKAVaEY4JhcPwSuBqPc`（midistage・maru・lnx 統合構想 6 Steps）、`mem_1ChTKc23Veo6sEXMJ16mAf`（火花: 全部まとめて Gear）、`mem_1ChTKAxCNTrpAgXr4XM1Cc`（Step 1）、`mem_1ChTKjX4gofAKD7vNcWB62`（Step 2）、[archive/ARCHITECTURE.md](../archive/ARCHITECTURE.md)（前身、Deprecated）
> **対象**: `Cargo.toml`, `rust-toolchain.toml`, `crates/lnx-protocol/`, `crates/lnx-gear/`, `crates/lnx-server/`, `apps/ios/project.yml`

## Abstract

spec 01 の「機器と場をつなぐもの（links）」を、**「接続方式や通信規格（MIDI / SysEx / USB Serial / Network QUIC 等）は裏に隠し、すべてを `Gear` として束ね、どのアプリ（場）がどの `Gear` を使うかを司る Signal Hub + Routing（`lnx-server`）」** および Apple ネイティブアプリ（**`lnx creare`、`apps/ios`**）として実装する。

> 「接続方式とか通信規格とかいろいろややこしいんで、全部まとめてGearじゃ。どのアプリがどのGear使うか。そう認識したい。」（mako、`mem_1ChTKc23Veo6sEXMJ16mAf`）

ノード間の通信は **Unison Protocol**（club-unison、QUIC、KDL スキーマ）に統一し、標準のネットワークライブラリを直接は使わない。

## Architecture

### 構成要素と現状

| 構成要素 | 場所 | 役割 | 現状 |
|---|---|---|---|
| **lnx-protocol** | `crates/lnx-protocol` | **[data + calculations]** どのアプリがどの Gear を使うかの wire 型と `Broker` 状態機械（presence / assignment / lease / phase / handoff / setup）。I/O なし | 動く（Step 2 で導入） |
| **lnx-gear** | `crates/lnx-gear` | **[calculations]** Gear ごとの入力正規化（`GearInput` → `ControlEvent`）と表示投影・設定変換（`GearProfile` → `Present` / SysEx / ROTO serial & palette / Keystage）。**`maru`（14bit CC + `TRACK / PARAM / VALUE` SysEx 投影）**・ROTO・Keystage・LPD8・X-Touch・nanoKONTROL2 対応。I/O なし | 動く（Step 2 で導入） |
| **lnx-server** | `crates/lnx-server` | **[actions]** lnx サーバ（Signal Hub + Router）。session（名乗り・heartbeat）、registry（一覧）、pairing（QR ペアリング）、Bonjour `_lnx._udp` で名乗る | 動く（design 01）。Step 3 で `lnx-protocol` / `lnx-gear` と実機 I/O Runtime を統合予定 |
| **lnx creare**（Apple） | `apps/ios` | 入り口のアプリ。SwiftUI、iPad が主。一つのターゲットで iOS / macOS。Mac 版はメニューバーから同梱の `lnx-server` を `SMAppService` で常駐管理する | 動く。接続・名乗り・heartbeat・ペアリング・一覧・画面切り替え |

### Signal Hub + Routing の全体像（統合ターゲット）

```mermaid
graph TB
    subgraph Apps["Application / Field — 使うアプリ（場）"]
        Creare["lnx creare（apps/ios、SwiftUI: iPad / iPhone / macOS）"]
        LL["Ladyland（音・演奏の場）"]
        VP["Vantage Point（開発・Editor の場）"]
    end
    subgraph Hub["Hub — Signal Hub + Routing"]
        Server["lnx-server（actions）<br/>session / registry / pairing / gear"]
        Proto["lnx-protocol（data + calculations）<br/>どのアプリがどの Gear を使うか（Broker / Lease / Handoff）"]
        GearCalc["lnx-gear（calculations）<br/>GearInput（ControlEvent）/ GearProfile（Present / ROTO serial）"]
        Server --> Proto
        Server --> GearCalc
    end
    subgraph Gears["Gear — 外部機器レイヤー（接続方式・通信規格は裏に隠す）"]
        Maru["maru（MARU01 / ESP32-S3 自作ハード）"]
        MIDI["Keystage / ROTO / LPD8 / X-Touch / nanoKONTROL2 等"]
    end
    subgraph Infra["Infrastructure"]
        Unison["Unison Protocol<br/>club-unison、QUIC、KDL"]
        Bonjour["Bonjour<br/>mdns-sd（Rust）/ NWBrowser（Swift）"]
    end
    Creare ==>|"QUIC :12730 / :12731（design 01）"| Server
    LL -.->|"Step 3〜6 で lnx-server に統合"| Server
    VP -.->|"Step 3〜6 で lnx-server に統合"| Server
    GearCalc -.->|"Step 3 で CoreMIDI / USB Serial 接続"| Maru
    GearCalc -.->|"Step 3 で CoreMIDI / USB Serial 接続"| MIDI
    Server --> Unison
    Server --> Bonjour
    Creare --> Bonjour
```

### 6 Steps の統合ロードマップ（`mem_1ChTKAVaEY4JhcPwSuBqPc`）

| Step | 内容 | 状態 |
|---|---|---|
| **Step 1** | 未接続の旧 3 crate（`lnx-engine` / `lnx-cli` / Bevy `lnx-creare`）と未使用依存を撤去し workspace を純化 | 完了（#51） |
| **Step 2** | `Gear` を中心語彙にした I/O なしの純粋層 `crates/lnx-protocol` と `crates/lnx-gear`（`maru` の入力変換・SysEx 投影込み）を導入 | **本変更で完了** |
| **Step 3** | `lnx-server` に Gear Runtime と `gear` channel を組み込み、`crates/lnx-client`（Rust SDK）と `clients/swift`（`LnxClient`）を追加 | 次 |
| **Step 4** | Mac 版 `LnxCreare.app` メニューバーに Gear ステータス一覧・トレース・ログ表示を合流 | 予定 |
| **Step 5** | 3D 機材資産（`gear/`）と机配置（`desk.kdl`）を `lnx` に合流し、Mac / iPad の `lnx creare` に展開 | 予定 |
| **Step 6** | `Ladyland` と `VP` を `LnxClient` / `lnx-client` に繋ぎ替え、`midistage` をアーカイブ | 予定 |

### Unison をどう使うか

- サーバ側は `club-unison`（crate 識別子は `unison`）の `ProtocolServer`。`with_identity(name, VERSION, "club.chronista.lnx")` → `enable_discovery(LNX_KDL)` → `register_channel`。スキーマ `crates/lnx-server/schemas/lnx.kdl` が正本で、バイナリに焼き込んで discovery で配る
- アプリ側は club-unison の Swift package（`UnisonClient`、`apps/ios/project.yml`）
- 待ち受けは UDP / QUIC の `[::]:12730`（本体）と `[::1]:12731`（手元用 pairing）。証明書は保存した自己署名（`cert.pem` / `key.pem`）、LAN の実機は QR ペアリングで leaf DER を pin（design 01）
- 探索は Bonjour。Rust は `mdns-sd` で `_lnx._udp` を広告、Swift は `NWBrowser`

### 分岐の答え

| 分岐 | 答え | 理由 |
|---|---|---|
| 中心語彙 | **すべて `Gear` に統一。「どのアプリがどの `Gear` を使うか」** | 接続方式や通信規格（MIDI / SysEx / USB Serial / QUIC）の複雑さを裏に隠し、3D 資産（`gear/`）や机配置（`desk.kdl`）とも語彙を一本化する（`mem_1ChTKc23Veo6sEXMJ16mAf`） |
| 役割と境界 | **`midistage` と `lnx-server` を統合し、`lnx-server` を唯一の Signal Hub + Router にする**。`maru` は市販コントローラと同じ Gear レイヤーに置く | 裁定 2026-11-27（`mem_1ChTKAVaEY4JhcPwSuBqPc`） |
| 後方互換 | **旧 `midistage` 名や旧パスとの後方互換は持たず、あるべき姿（`lnx` と `Gear` の語彙・置き場）へ一直線に揃える** | 裁定 2026-11-27「後方互換なんて気にせず、あるべき姿に目指して、一直線でいこうよ」（`mem_1ChTKAVaEY4JhcPwSuBqPc`） |
| 旧 3 crate | **`lnx-engine` / `lnx-cli` / Bevy `lnx-creare` は撤去済み** | Step 1（#51、`mem_1ChTKAxCNTrpAgXr4XM1Cc`） |
| 言語 | サーバ・プロトコル・Gear 変換は Rust、Apple の UI は Swift（SwiftUI） | 純粋計算層と低遅延通信は Rust、UI は Apple ネイティブ（`apps/ios`） |
| ノード間通信 | Unison Protocol 一本 | tokio 等を直接ではなく Unison 経由にする |
| Rust の版 | `rust-toolchain.toml` で 1.99.1 に固定。mise には rust を書かない | 裁定 2026-09-15「Rust toolchain は rustup 一本」（`mem_1Cf5RnR2KKVdmemBSpiU9A`）、1.99.1 は裁定 2026-11-04 |

## Data Model

### Rust workspace（`Cargo.toml`）

- `[workspace]` の 3 member: `crates/lnx-protocol`, `crates/lnx-gear`, `crates/lnx-server`（Step 3 で `crates/lnx-client` を追加予定）
- `workspace.package` は version `0.1.0-alpha3`、edition 2024、license `MIT OR Apache-2.0`
- `workspace.dependencies`: `libc`、`tokio`、`serde`、`serde_json`、`toml`
- profile: release は `opt-level 3` / LTO / `codegen-units 1` / `panic = abort`

### `lnx-protocol` の主な型

| 型 | 場所 | 役割 |
|---|---|---|
| `Broker` | `lib.rs` | Gear の検出（`present`）、アプリへの割り当て（`Assignment`）、実行中の使用権（`Lease`）、引き継ぎ（`Phase`: `Off` / `Waiting` / `Active` / `Releasing` / `Error`）を管理する純粋な状態機械 |
| `GearState`, `GearView`, `Snapshot` | `lib.rs`, `wire.rs` | 各 Gear の状態、操作子（`Control`）、仮想ポート（`NativePorts`）、ROTO 等の setup 状態（`configuring` / `current_setup` / `setup_owners`） |
| `Hello`, `SetEnabled`, `Quiesced`, `Present`, `SendMidi`, `ApplyGearSetup`, `Event` | `wire.rs` | `gear` channel（`wire::CHANNEL = "gear"`）の要求とイベント |

### `lnx-gear` の主な型

| 型 | 場所 | 役割 |
|---|---|---|
| `GearInput`, `ControlEvent` | `gear_input.rs` | Gear からの raw byte を正規化した操作イベント（`Knob`, `KnobTouch`, `Button`, `Fader`, `FaderTouch`, `Pad`）に変換する純粋 trait。`nanokontrol`, `roto`, `xtouch`, `lpd8`, **`maru`** を実装 |
| `GearProfile`, `ParamSpec`, `Rgb` | `gear_profile.rs` | アプリの状態（トラック名・色・パラメータ名・現在値・段階・中央クリック）を Gear 固有の投影 byte 列に変換する純粋 trait。`xtouch`, `lpd8`, `roto`, **`maru`** を実装 |
| `roto_serial`, `roto_palette` | `roto_serial.rs`, `roto_palette.rs` | ROTO-CONTROL の USB Serial API フレーミング（setup の読み書きと差分計算）および 83 色パレット量子化 |
| `keystage` | `keystage.rs` | KORG Keystage の接続モード（`0x6F`）に対する解除フレーム生成 |

## Implementation

- どこに何があるか: 上の表。ビルドと日々の回し方は [guide 01](../guide/01-development.md)
- つながっているもの: lnx creare ⇄ lnx-server（QUIC、design 01）
- テスト: Rust は `cargo test --workspace`（`lnx-protocol` の状態機械・wire テスト、`lnx-gear` の各 Gear 入出力・ROTO serial テスト、`lnx-server` の実 QUIC 往復テスト）。Swift は Swift Testing の単体 + 実サーバ相手の UI テスト（design 01「テストは三層」）

## やってはいけない

- **Rust の版を mise に書かない。** `rust-toolchain.toml` が正。cargo-edit 等の auto_install が rustc の版で止まった実例（2026-11-04、`.mise.toml` のコメント）
- **前身の `ARCHITECTURE.md` のコード例を写さない。** `unison_protocol::ServiceBuilder` や `unison_node::NodeManager` は実在しない API。実物は club-unison の `ProtocolServer` / `ProtocolClient`（`crates/lnx-server/src/serve.rs`、`tests/link.rs`）
- **スキーマ（`lnx.kdl`）を変えたら Swift の写し（`LnxProtocol.swift`）も同じ PR で。** codegen は無い（design 01）
- **`lnx-protocol` と `lnx-gear` に I/O を持ち込まない。** これらは純粋な `data` + `calculations` 層であり、ポート接続・ファイル読み書き・時刻取得・非同期通信は `lnx-server`（`actions` 層）に置く

## Status log

- 2025-09-27: 前身 `docs/ARCHITECTURE.md`。Unison エコシステム前提の構想で、分散処理・自動スケーリング・監視・コンテナ化まで含んでいた
- 2026-11-04: SDG の design として `02-architecture.md` に書き直し、Draft。v0.1.0-alpha2 の実装（lnx-server、apps/ios）に合わせ、
  実在しない API のコード例と、実装も裁定も無い節（分散処理 / 自動スケーリング / Prometheus / Docker）を落とした。
  前身は `docs/archive/ARCHITECTURE.md`（Deprecated）
- 2026-11-27: `midistage`・`maru`・`lnx` の統合構想（6 Steps、裁定 `mem_1ChTKAVaEY4JhcPwSuBqPc`）に基づき、`lnx-server` を唯一の Signal Hub + Router とする方針を明記。
  Step 1（#51、`mem_1ChTKAxCNTrpAgXr4XM1Cc`）として、未接続の旧世代 3 crate（`lnx-engine`、`lnx-cli`、Bevy `lnx-creare`）と未使用の音声・GUI 依存を workspace から撤去した
- 2026-11-27: 火花 `mem_1ChTKc23Veo6sEXMJ16mAf`（「接続方式とか通信規格とかいろいろややこしいんで、全部まとめてGearじゃ。どのアプリがどのGear使うか。そう認識したい。」）を受け、中心語彙を `Gear` に統一。
  Step 2（`mem_1ChTKjX4gofAKD7vNcWB62`）として、I/O なしの純粋層 `crates/lnx-protocol`（`GearState` / `Broker` / `wire`）と `crates/lnx-gear`（`GearInput` / `GearProfile` / `roto_serial` / `roto_palette` / `keystage`、`maru` の入力変換と SysEx 投影を含む）を導入した
