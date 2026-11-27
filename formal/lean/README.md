# Gear Broker と 7bit/14bit 正規化・SysEx 安全性の構造法則（Lean 4）

`LnxCore.lean` は `crates/lnx-protocol`（`Broker` の排他 lease・リビジョン・二段階 handoff・出力フェンス）および `crates/lnx-gear`（`maru` / ROTO の 14bit CC 結合・SysEx 7bit データバイト安全性・Keystage 切断フレーム）を手書きでモデル化し、任意の入力について構造法則を証明します。

## 実行

Lean は `lean-toolchain` で **4.36.0** に固定しています。elan が利用可能な環境で実行します。外部 Lake パッケージは不要です。

```sh
cd formal/lean
lean -DwarningAsError=true LnxCore.lean
```

終了コード 0 に加えて、全 22 個の定理すべての `#print axioms` が `does not depend on any axioms` と報告することを確認します。`sorry`、追加の `axiom`、`Classical.choice`、`propext`、`Quot.sound` は証明に使いません。

## 証明している法則

### `lnx-protocol` — Broker 状態機械（排他 lease・二段階 handoff・出力フェンス）

| 定理 | 内容・Rust との対応 |
| --- | --- |
| `setEnabled_rejected_while_pending` | `Broker::set_enabled`: `PendingRelease`（`Phase::Releasing`）進行中は新規の `SetEnabled` を必ず `AccessError::Pending` で拒否する |
| `setEnabled_rejects_stale_revision` | `Broker::set_enabled`: `expected_revision` が現在の `assignment.revision` と異なれば必ず `AccessError::StaleRevision` で拒否する |
| `setEnabled_requires_takeover_for_foreign_owner` | `Broker::set_enabled`: 他アプリが所有中の Gear に対する `takeover = false` の獲得要求は必ず `AccessError::Conflict` で拒否する |
| `takeover_enters_releasing_and_keeps_old_lease` | `Broker::set_enabled`: 他アプリが active lease を持つ状態で `takeover = true` が来ると、即座に `Active` を奪わず `Phase::Releasing` に遷移し、`fromLease` を保持したまま二段階解放待ちに入る |
| `releasing_rejects_all_outputs` | `Broker::authorize_output`: `Phase::Releasing` の間は旧所有者・新所有者ともに `SendMidi` / `Present` が必ず `AccessError::StaleLease` で拒否される |
| `non_active_rejects_output` | `Broker::authorize_output`: `Phase::Off` / `Waiting` / `Releasing` / `Error` のいずれでも出力は必ず拒否される |
| `authorizeOutput_ok_implies_active_and_matching_lease` | `Broker::authorize_output`: 出力が許可されるなら、必ず `Phase::Active` である |
| `quiesced_alone_stays_releasing` | `Broker::quiesced`: アプリ側 `Quiesced` 完了だけでは（物理 I/O の `drained` が未完の間は）`Phase::Releasing` に留まる |
| `drained_alone_stays_releasing` | `Broker::drained`: 物理 I/O の `drained` 完了だけでは（アプリ側 `Quiesced` が未完の間は）`Phase::Releasing` に留まる |
| `markQuiesced_rejects_wrong_token` | `Broker::quiesced`: 引き継ぎ対象の `fromLease` と session または token が一致しない `Quiesced` は必ず `AccessError::StaleLease` で拒否される |
| `handoff_quiesce_then_drain_eq_drain_then_quiesce` | `Broker::quiesced` × `Broker::drained`: `Quiesced → Drained` の順で届いても `Drained → Quiesced` の順で届いても、合流後の `GearModel` は完全に一致する（二段階フェンスの可換性） |
| `handoff_completion_issues_fresh_token` | `Broker::reconcile`: 二段階 handoff 完了時、新所有者のセッションには必ず単調増加した新しい `nextToken + 1` が発行され `Phase::Active` に遷移する |
| `old_lease_rejected_after_handoff` | `Broker::authorize_output`: 新しい lease token へ遷移した後は、旧 token による遅延出力要求は必ず `AccessError::StaleLease` で拒否される |
| `absent_gear_never_holds_lease`, `disconnected_owner_never_holds_lease` | `Broker::reconcile`: 機器不在（`present = false`）または所有者セッション切断時は、必ず `lease = none` に落ちて `Waiting`（または `Off`）へ退避する |
| `active_implies_present_and_has_lease` | `Broker::reconcile`: `reconcile` 後の状態が `Phase::Active` ならば、必ず `present = true` かつ `lease ≠ none` である |

### `lnx-gear` — 7bit/14bit 正規化・`maru` SysEx 安全性・Keystage 切断フレーム

| 定理 | 内容・Rust との対応 |
| --- | --- |
| `mask7_is_sysex_safe`, `mask7_never_f7` | `crates/lnx-gear/src/gear_profile.rs`: `& 0x7F` でマスクした任意のバイトは最上位ビットが 0 であり、SysEx 終端 `0xF7` やステータスバイトと決して衝突しない |
| `unpack14Hi_sysex_safe`, `unpack14Lo_sysex_safe` | `MaruProfile::u14`: 任意の 14bit 値から切り出した上位・下位バイトはともに常に SysEx データバイトとして安全（MSB = 0） |
| `word14_roundtrip` | `MaruInput` / `RotoInput` / `MaruProfile`: 上位 7bit × 下位 7bit の 14bit 表現は 2 バイトへのエンコードとデコードで完全に往復する |
| `maru_consecutive_lo_preserves_hi` | `MaruInput::parse`: 上位 CC（CC 16–23）が記憶された後、下位 CC（CC 48–55）が連続して届いても記憶された上位 7bit は破壊されず最新の 14bit 値を合成し続ける |
| `keystage_disconnect_frame_well_formed` | `keystage::disconnect_for_identity_reply`: Keystage の Identity Reply から組み立てた 9 バイト切断 SysEx は常に `F0 42 (40|ch) 00 01 modelLo modelHi 00 F7` の構造と元の `model` を保持する |
