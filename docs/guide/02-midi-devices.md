# 02. MIDI 機器 — Korg Keystage 49 と Akai LPD8

> **Status**: Draft（Status log 参照）
> **Related**: [spec 01](../spec/01-core-concept.md)（道具・楽器との自然な対話）、[design 02](../design/02-architecture.md)（Signal Hub + Routing と Gear 層）
> **対象**: `crates/lnx-gear/src/gear_input.rs`, `crates/lnx-gear/src/gear_profile.rs`, `crates/lnx-gear/src/keystage.rs`, `crates/lnx-server/src/gear/inventory.rs`

## Overview

LNX が手元で前提にしている代表的な MIDI 機器（Keystage 49 と LPD8）の仕様と、lnx で使うときの推奨設定。
Keystage 49 がメインの鍵盤（メロディ、ch 1）、LPD8 がパッドコントローラー（ドラム、ch 10）。

**実装の所在**:
- ポート名からの自動認識（spec 01「ゼロコンフィグ、自動認識」）は `crates/lnx-server/src/gear/inventory.rs`（`keystage`, `lpd8` ほか `roto`, `maru`, `xtouch`, `nanokontrol`, `numa`, `minilab`, `fgdp`, `l6max`, `zenith2`）
- 入力イベント（Note / CC）の正規化と SysEx / 接続モード（Keystage Daw In/Out）は `crates/lnx-gear`（`KeystageInput`, `Lpd8Input`, `keystage` モジュール）に実装されている。

## Prerequisites

- どちらも USB Class Compliant でドライバ不要（Keystage は USB-B、LPD8 は USB mini-B でバスパワーのみ）
- USB ハブを避けて直結する（レイテンシと干渉）
- macOS では Audio MIDI 設定（`open -a "Audio MIDI Setup"`）の MIDI スタジオで認識を確認する

## Usage

### Korg Keystage 49 — メインの鍵盤、DAW コントロール

| 項目 | 値 |
|---|---|
| 鍵盤 | 49 鍵（4 オクターブ）、ベロシティ対応、アフタータッチ非対応。ノート範囲 C1(24)〜C5(72) |
| 接続 | USB-B（USB-MIDI）、MIDI DIN（5 ピン） |
| 電源 | USB バスパワーまたは DC 9V |
| MIDI | MIDI 1.0 として扱う。既定 ch 1。Note On `0x90`〜`0x9F` / Note Off `0x80`〜`0x8F`、ベロシティ 1〜127（0 は Note Off 扱い） |
| メーカー ID | `0x42`（Korg） |

CC（アサイナブル。ノブ 1〜8 の役割は既定値）:

| CC | 役割 |
|---|---|
| 1 | Modulation Wheel |
| 7 | Volume（スライダー） |
| 10 | Pan |
| 11 | Expression |
| 64 | Sustain Pedal（ペダル端子） |
| 71 | ノブ 1: Filter Resonance |
| 74 | ノブ 2: Filter Cutoff |
| 73 | ノブ 3: Attack Time |
| 72 | ノブ 4: Release Time |
| 75 | ノブ 5: Decay Time |
| 76 | ノブ 6: Vibrato Rate |
| 77 | ノブ 7: Vibrato Depth |
| 78 | ノブ 8: Vibrato Delay |

トランスポート（システムリアルタイム / コモンメッセージ）: `0xFA` Start、`0xFB` Continue、`0xFC` Stop、`0xF2` Song Position Pointer。

特殊機能:

- ページボタン: ノブの CC を 8 バンク切り替え（8 ノブ × 8 ページ = 64 パラメータ）
- アルペジエーター内蔵（MIDI クロック同期可）
- スケール機能: メジャー / マイナースケールに限定した演奏モード

SysEx（文書の値。実機からの応答で確認したものではない。nn はデバイス ID）:

```
Identity Reply:  F0 7E nn 06 02 42 00 01 34 00 01 00 00 F7
                 42 = Korg、00 01 = Sub ID、34 00 = Keystage の Model ID、01 00 00 = Version
Native Mode ON:  F0 42 40 00 01 35 F7        DAW インテグレーション用
```

### Akai LPD8 — パッドコントローラー、ビートメイキング

| 項目 | 値 |
|---|---|
| パッド | 8（ベロシティ対応、感圧式） |
| ノブ | 8（エンドレスではない、0〜127） |
| 接続 / 電源 | USB mini-B（USB-MIDI 専用）、バスパワーのみ。330g |
| MIDI | 既定 ch 10（ステータス `0x99` が Note On） |
| プログラム | 4 つ — Preset 1 Drums / Preset 2 Melodic / Preset 3 User 1 / Preset 4 User 2。Program Change で切り替え |

パッド（Program 1 の既定、Note モード）:

| パッド | ノート | 想定する音 |
|---|---|---|
| 1 | 36 (C1) | Kick |
| 2 | 37 (C#1) | Snare Side |
| 3 | 38 (D1) | Snare |
| 4 | 39 (D#1) | Clap |
| 5 | 40 (E1) | Snare 2 |
| 6 | 41 (F1) | Low Tom |
| 7 | 42 (F#1) | Closed HH |
| 8 | 43 (G1) | Low Tom 2 |

CC モードのパッドは CC 1〜8（Program 依存）。ノブは Program 1 の既定で CC 1〜8
（K1 Modulation、K2 Breath Controller、K3 Controller 3、K4 Foot Controller、K5 Portamento Time、K6 Data Entry MSB、K7 Channel Volume、K8 Balance）。

パッドのモードは Note（ドラムパッド）/ CC（0 / 127 のトグル）/ Program Change。
ベロシティカーブは Linear / Exponential（軽いタッチで大きく変化）/ Logarithmic（強いタッチが要る）/ Fixed（1〜127 の固定値）。
これらと MIDI ch（1〜16）、ノブの CC 番号と範囲は Akai の LPD8 Editor で設定する。

### 推奨設定

| | Keystage | LPD8 |
|---|---|---|
| MIDI ch | 1（メロディ） | 10（ドラム） |
| 割り当て | ノブは lnx 用のカスタム CC | ノブはエフェクトのパラメータ |
| その他 | ベロシティカーブ Normal、サステインペダル接続推奨 | パッドは Note モード（ビート作成時）、プログラムは用途別に 4 つ |

## Troubleshooting

- **認識されない**: Audio MIDI 設定の MIDI スタジオに出ているか見る。出ていなければケーブルとポートを替える（どちらもドライバ不要）
- **レイテンシが大きい**: バッファは 64〜128 サンプル、USB ハブを避けて直結、ほかの USB 機器との干渉を避ける
- **Gear として見えない**: `lnx-server` の `inventory.rs` でポート名（`Keystage` / `LPD8`）を照合している。`LNX_TRACE=1` でトレースを有効にするか、`gear` channel の `Snapshot` で `present` を確認する

## Status log

- 2026-11-27: Step 2 / Step 3（`mem_1ChTKjX4gofAKD7vNcWB62`、`mem_1ChTLTLa5yr1LQ2CtNHo8p`）で `crates/lnx-gear` と `crates/lnx-server/src/gear/` に Keystage / LPD8 の自動認識と入力変換が実装されたのに合わせ、Overview と Troubleshooting を更新した
- 2025-09-27: `docs/MIDI_DEVICES.md`（機器仕様、lnx-engine での実装例、推奨設定、トラブルシューティング）
- 2026-11-04: guide の骨格で `docs/guide/02-midi-devices.md` に移設、Draft。機器の仕様と推奨設定は保ち、Rust の定数ブロックは表にした。
  落とした・直したもの: 実装例のコード（lnx-engine に MIDI 実装が無く、例も `self.input` を持たないなどそのままでは動かない）、
  トランスポートの「MMC」（実体はシステムリアルタイムメッセージ）、シリアルポートでの確認（USB-MIDI はそこに出ない）、
  Identity Reply の配列長（`[u8; 13]` と書かれていたが 14 バイト）
