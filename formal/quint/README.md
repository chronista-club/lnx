# Gear Handoff と排他 Lease の設計規則を Quint で確かめる

`mem_1ChTPJv4KqgX7AuML7cY5T`

`gear_handoff.qnt` は、`crates/lnx-protocol`（`Broker`）における「どのアプリがどの Gear を使うか」の引き継ぎ状態機械を有限モデルで検査する。設計規則を 1 つずつ外すと対応する不変条件に反例（`ng`）が出ることも検査し、現在の二段階 handoff 規則が必要な理由を残す。

## 実行

Bun が入った環境で、リポジトリのルートから実行する。

```sh
bun formal/quint/check.ts
```

ランナーは `bunx @informalsystems/quint@0.33.1` を呼ぶ。`gear_handoff.qnt` の 6 モード × 8 シナリオ（計 48 シナリオ）と 6 モード × 5 不変条件（計 30 不変条件チェック）を実行し、期待表と全件一致すれば `PASS` / exit 0 で終了する。

## 比較する 6 モード

| モード | `REQUIRE_TAKEOVER_CONFIRM` | `WAIT_FOR_QUIESCE` | `WAIT_FOR_DRAIN` | `MONOTONIC_LEASE_TOKEN` |
|---|---|---|---|---|
| `naive` | false | false | false | false |
| `noTakeoverConfirm` | false | true | true | true |
| `skipQuiesceWait` | true | false | true | true |
| `skipDrainFence` | true | true | false | true |
| `reusableLeaseToken` | true | true | true | false |
| `lnxCurrent` | true | true | true | true |

## 不変条件と期待表

`ok` は反例なし、`ng` は設計規則を外したことで期待通り反例が見つかることを表す。

| モード | `noImplicitTakeover` | `handoffWaitsForQuiesce` | `handoffWaitsForDrain` | `staleLeaseOutputRejected` | `allInvariants` |
|---|---|---|---|---|---|
| `naive` | ng | ng | ng | ng | ng |
| `noTakeoverConfirm` | ng | ok | ok | ok | ng |
| `skipQuiesceWait` | ok | ng | ok | ok | ng |
| `skipDrainFence` | ok | ok | ng | ok | ng |
| `reusableLeaseToken` | ok | ok | ok | ng | ng |
| `lnxCurrent` | ok | ok | ok | ok | ok |
