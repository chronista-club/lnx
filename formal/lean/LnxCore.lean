/-
  lnx-protocol と lnx-gear の構造法則（Lean 4.36.0、公理ゼロ証明）。
  「どのアプリがどの Gear を使うか」を司る Broker（crates/lnx-protocol/src/lib.rs）の
  排他 lease・revision 先行検査・二段階 handoff（quiesced → drained）・Releasing 中の disable・
  挿抜/切断時の Releasing 遷移・stale_lease 出力拒否、および Gear 層（crates/lnx-gear）の
  7bit/14bit 正規化・SysEx 7bit 安全性・Keystage 13 バイト切断フレーム変換を、
  sorry / propext / Quot.sound / Classical.choice を使わず構成的に証明する。
-/
namespace LnxCore

-- 重なりのない 4 分岐の構造再帰で Nat 等値判定を定義する（catch-all splitter の propext 混入を防ぐ）。
def natEq : Nat → Nat → Bool
  | 0, 0 => true
  | 0, _ + 1 => false
  | _ + 1, 0 => false
  | n + 1, m + 1 => natEq n m

theorem natEq_refl (n : Nat) : natEq n n = true := by
  induction n with
  | zero => rfl
  | succ n ih => exact ih

#print axioms natEq_refl

theorem natEq_succ_ne_self (n : Nat) : natEq (n + 1) n = false := by
  induction n with
  | zero => rfl
  | succ n ih => exact ih

#print axioms natEq_succ_ne_self

inductive Phase where
  | off
  | waiting
  | active
  | releasing
  | error

def Phase.isActive : Phase → Bool
  | .active => true
  | .off => false
  | .waiting => false
  | .releasing => false
  | .error => false

structure Lease where
  sessionId : Nat
  token : Nat

structure Assignment where
  clientId : Option Nat
  revision : Nat
  expected : Bool

-- Rust の Broker::quiescent (BTreeSet<String>) に対応する解放待ち状態。
-- drained はフラグとして保持せず、quiesced == true の状態で drained が呼ばれたときのみ解放を完了する。
structure PendingRelease where
  fromLease : Lease
  toClient : Option Nat
  quiesced : Bool

inductive AccessError where
  | conflict
  | staleRevision
  | staleLease
  | pending

inductive Outcome (α : Type) where
  | ok (value : α)
  | error (err : AccessError)

structure GearModel where
  present : Bool
  assignment : Assignment
  phase : Phase
  lease : Option Lease
  releasingTo : Option Nat
  pending : Option PendingRelease
  nextToken : Nat

-- Broker::activate の構造モデル（pending が解消した状態で呼ばれる）。
def activateForOwner (g : GearModel) (activeSession : Option Nat) : GearModel :=
  match g.assignment.clientId with
  | none =>
    { g with pending := none, releasingTo := none, phase := Phase.off, lease := none }
  | some _ =>
    match g.present with
    | false =>
      { g with pending := none, releasingTo := none, phase := Phase.waiting, lease := none }
    | true =>
      match activeSession with
      | none =>
        { g with pending := none, releasingTo := none, phase := Phase.waiting, lease := none }
      | some sid =>
        match g.lease with
        | some current =>
          match natEq current.sessionId sid && g.phase.isActive with
          | true => { g with pending := none, releasingTo := none }
          | false =>
            { g with
              pending := none
              releasingTo := none
              phase := Phase.active
              lease := some ⟨sid, g.nextToken + 1⟩
              nextToken := g.nextToken + 1 }
        | none =>
          { g with
            pending := none
            releasingTo := none
            phase := Phase.active
            lease := some ⟨sid, g.nextToken + 1⟩
            nextToken := g.nextToken + 1 }

-- Broker::authorize_output の構造モデル。Phase::Active かつ sessionId と token が完全一致するときのみ許可。
def authorizeOutput (g : GearModel) (session : Nat) (token : Nat) : Outcome Unit :=
  match g.phase with
  | Phase.active =>
    match g.lease with
    | some l =>
      match natEq l.sessionId session && natEq l.token token with
      | true => Outcome.ok ()
      | false => Outcome.error AccessError.staleLease
    | none => Outcome.error AccessError.staleLease
  | Phase.off => Outcome.error AccessError.staleLease
  | Phase.waiting => Outcome.error AccessError.staleLease
  | Phase.releasing => Outcome.error AccessError.staleLease
  | Phase.error => Outcome.error AccessError.staleLease

-- Broker::quiesced の構造モデル。quiesced になっても drained が呼ばれるまでは Phase.releasing に留まる。
def markQuiesced (g : GearModel) (session : Nat) (token : Nat) :
    Outcome GearModel :=
  match g.pending with
  | some p =>
    match natEq p.fromLease.sessionId session && natEq p.fromLease.token token with
    | true =>
      Outcome.ok {
        g with
        phase := Phase.releasing
        lease := some p.fromLease
        releasingTo := p.toClient
        pending := some { p with quiesced := true }
      }
    | false => Outcome.error AccessError.staleLease
  | none => Outcome.error AccessError.staleLease

-- Broker::drained の構造モデル（crates/lnx-protocol/src/lib.rs:204-213）。
-- quiesced == true でなければ AccessError.pending を返し、完了時は lease := none にリセットしてから activate する。
def markDrained (g : GearModel) (activeSession : Option Nat) :
    Outcome GearModel :=
  match g.pending with
  | some p =>
    match p.quiesced with
    | false => Outcome.error AccessError.pending
    | true =>
      Outcome.ok (activateForOwner { g with lease := none, releasingTo := none, pending := none } activeSession)
  | none => Outcome.error AccessError.pending

def isForeignOwner (currentOwner : Option Nat) (client : Nat) : Bool :=
  match currentOwner with
  | none => false
  | some owner => !natEq owner client

-- Broker::enable と Broker::disable を統合した setEnabled の構造モデル（crates/lnx-protocol/src/lib.rs:124-189）。
-- 1. 先に revision を検査し不一致なら AccessError.staleRevision。
-- 2. enabled = true のときは pending があれば AccessError.pending、他アプリ所有かつ !takeover なら AccessError.conflict。
-- 3. enabled = false（disable）のときは他アプリ所有なら常に AccessError.conflict（takeover による強制 disable は不可）。
--    Releasing 中でも現在の assignment 所有者からの disable は受け付け、releasingTo := none にキャンセルする。
def setEnabled (g : GearModel) (client : Nat) (enabled : Bool) (expectedRevision : Nat)
    (takeover : Bool) (activeSession : Option Nat) : Outcome GearModel :=
  match natEq g.assignment.revision expectedRevision with
  | false => Outcome.error AccessError.staleRevision
  | true =>
    match enabled with
    | true =>
      match g.pending with
      | some _ => Outcome.error AccessError.pending
      | none =>
        match isForeignOwner g.assignment.clientId client && !takeover with
        | true => Outcome.error AccessError.conflict
        | false =>
          match isForeignOwner g.assignment.clientId client, g.lease with
          | true, some oldLease =>
            Outcome.ok {
              g with
              assignment := ⟨some client, g.assignment.revision + 1, false⟩
              phase := Phase.releasing
              lease := some oldLease
              releasingTo := some client
              pending := some ⟨oldLease, some client, false⟩
            }
          | true, none =>
            Outcome.ok (activateForOwner {
              g with
              assignment := ⟨some client, g.assignment.revision + 1, false⟩
            } activeSession)
          | false, some _ =>
            Outcome.ok (activateForOwner {
              g with
              assignment := ⟨some client, g.assignment.revision + 1, false⟩
            } activeSession)
          | false, none =>
            Outcome.ok (activateForOwner {
              g with
              assignment := ⟨some client, g.assignment.revision + 1, false⟩
            } activeSession)
    | false =>
      match isForeignOwner g.assignment.clientId client with
      | true => Outcome.error AccessError.conflict
      | false =>
        match g.pending with
        | some p =>
          Outcome.ok {
            g with
            assignment := ⟨none, g.assignment.revision + 1, false⟩
            phase := Phase.releasing
            lease := some p.fromLease
            releasingTo := none
            pending := some { p with toClient := none }
          }
        | none =>
          match g.lease with
          | some oldLease =>
            Outcome.ok {
              g with
              assignment := ⟨none, g.assignment.revision + 1, false⟩
              phase := Phase.releasing
              lease := some oldLease
              releasingTo := none
              pending := some ⟨oldLease, none, false⟩
            }
          | none =>
            Outcome.ok {
              g with
              assignment := ⟨none, g.assignment.revision + 1, false⟩
              phase := Phase.off
              lease := none
              releasingTo := none
              pending := none
            }

-- Broker::set_present(false) と Broker::disconnect_session の構造モデル（crates/lnx-protocol/src/lib.rs:232-257）。
def unplugGear (g : GearModel) : GearModel :=
  match g.pending with
  | some _ => { g with present := false }
  | none =>
    match g.lease with
    | some oldLease =>
      { g with
        present := false
        phase := Phase.releasing
        lease := some oldLease
        pending := some ⟨oldLease, none, false⟩ }
    | none =>
      activateForOwner { g with present := false } none

def disconnectOwnerSession (g : GearModel) : GearModel :=
  match g.pending with
  | some p =>
    { g with
      phase := Phase.releasing
      pending := some { p with quiesced := true } }
  | none =>
    match g.lease with
    | some oldLease =>
      { g with
        phase := Phase.releasing
        lease := some oldLease
        pending := some ⟨oldLease, none, true⟩ }
    | none =>
      activateForOwner g none

-- ============================================================================
-- 定理 1〜7: Broker の排他・リビジョン・テイクオーバー・出力フェンス法則
-- ============================================================================

-- 1. expectedRevision が不一致の setEnabled は、pending の有無にかかわらず必ず AccessError.staleRevision で拒否される。
theorem setEnabled_rejects_stale_revision (g : GearModel) (client : Nat) (enabled : Bool)
    (rev : Nat) (takeover : Bool) (sid : Option Nat)
    (hStale : natEq g.assignment.revision rev = false) :
    setEnabled g client enabled rev takeover sid = Outcome.error AccessError.staleRevision := by
  unfold setEnabled
  rw [hStale]

#print axioms setEnabled_rejects_stale_revision

-- 2. PendingRelease が進行中（Releasing）の間は、revision が合っていても新規の enable（enabled = true）は必ず AccessError.pending で拒否される。
theorem enable_rejected_while_pending (g : GearModel) (p : PendingRelease)
    (client : Nat) (takeover : Bool) (sid : Option Nat)
    (h : g.pending = some p) :
    setEnabled g client true g.assignment.revision takeover sid = Outcome.error AccessError.pending := by
  unfold setEnabled
  rw [natEq_refl g.assignment.revision, h]

#print axioms enable_rejected_while_pending

-- 3. 他のアプリが所有している Gear に対して takeover = false で enabled = true を要求すると必ず AccessError.conflict になる。
theorem setEnabled_requires_takeover_for_foreign_owner (g : GearModel) (owner client : Nat)
    (sid : Option Nat) (hNoPending : g.pending = none)
    (hOwner : g.assignment.clientId = some owner) (hNe : natEq owner client = false) :
    setEnabled g client true g.assignment.revision false sid = Outcome.error AccessError.conflict := by
  unfold setEnabled isForeignOwner
  rw [natEq_refl g.assignment.revision, hNoPending, hOwner]
  dsimp only
  rw [hNe]
  rfl

#print axioms setEnabled_requires_takeover_for_foreign_owner

-- 4. 他のアプリが active lease を持つ状態で takeover = true を要求すると、即座に Active を奪わず Phase.releasing に遷移し旧 lease を保持する。
theorem takeover_enters_releasing_and_keeps_old_lease (g : GearModel) (owner client : Nat)
    (oldLease : Lease) (sid : Option Nat)
    (hNoPending : g.pending = none)
    (hOwner : g.assignment.clientId = some owner)
    (hLease : g.lease = some oldLease)
    (hNe : natEq owner client = false) :
    setEnabled g client true g.assignment.revision true sid =
      Outcome.ok {
        g with
        assignment := ⟨some client, g.assignment.revision + 1, false⟩
        phase := Phase.releasing
        lease := some oldLease
        releasingTo := some client
        pending := some ⟨oldLease, some client, false⟩
      } := by
  unfold setEnabled isForeignOwner
  rw [natEq_refl g.assignment.revision, hNoPending, hOwner, hLease]
  dsimp only
  rw [hNe]
  rfl

#print axioms takeover_enters_releasing_and_keeps_old_lease

-- 5. Phase.releasing 中に引き継ぎ先オーナーが disable（enabled = false）すると、旧 lease の解放待ちは維持したまま releasingTo が none にキャンセルされる。
theorem disable_while_releasing_cancels_target (g : GearModel) (p : PendingRelease)
    (client : Nat) (takeover : Bool) (sid : Option Nat)
    (hPending : g.pending = some p)
    (hOwner : g.assignment.clientId = some client) :
    setEnabled g client false g.assignment.revision takeover sid =
      Outcome.ok {
        g with
        assignment := ⟨none, g.assignment.revision + 1, false⟩
        phase := Phase.releasing
        lease := some p.fromLease
        releasingTo := none
        pending := some { p with toClient := none }
      } := by
  unfold setEnabled isForeignOwner
  rw [natEq_refl g.assignment.revision, hOwner, hPending]
  dsimp only
  rw [natEq_refl client]
  rfl

#print axioms disable_while_releasing_cancels_target

-- 6. Phase.releasing の間は、旧所有者であっても新所有者であっても authorizeOutput（SendMidi / Present）は必ず staleLease で拒否される。
theorem releasing_rejects_all_outputs (g : GearModel) (session token : Nat)
    (hPhase : g.phase = Phase.releasing) :
    authorizeOutput g session token = Outcome.error AccessError.staleLease := by
  unfold authorizeOutput
  rw [hPhase]

#print axioms releasing_rejects_all_outputs

-- 7. Phase.waiting / off / error でも authorizeOutput は必ず staleLease で拒否される。
theorem non_active_rejects_output (g : GearModel) (session token : Nat)
    (hNotActive : g.phase.isActive = false) :
    authorizeOutput g session token = Outcome.error AccessError.staleLease := by
  unfold authorizeOutput
  cases hp : g.phase with
  | off => rfl
  | waiting => rfl
  | releasing => rfl
  | error => rfl
  | active =>
    rw [hp] at hNotActive
    cases hNotActive

#print axioms non_active_rejects_output

-- 8. authorizeOutput が ok を返すなら、必ず Phase.active かつ lease が存在し sessionId と token が一致している。
theorem authorizeOutput_ok_implies_active_and_matching_lease (g : GearModel) (session token : Nat)
    (hOk : authorizeOutput g session token = Outcome.ok ()) :
    g.phase = Phase.active ∧
    match g.lease with
    | some l => (natEq l.sessionId session && natEq l.token token) = true
    | none => False := by
  cases g with
  | mk present assignment phase lease releasingTo pending nextToken =>
    cases phase with
    | off => cases hOk
    | waiting => cases hOk
    | releasing => cases hOk
    | error => cases hOk
    | active =>
      refine ⟨rfl, ?_⟩
      cases lease with
      | none => cases hOk
      | some l =>
        unfold authorizeOutput at hOk
        dsimp only at hOk ⊢
        cases hm : (natEq l.sessionId session && natEq l.token token) with
        | true => rfl
        | false => rw [hm] at hOk; cases hOk

#print axioms authorizeOutput_ok_implies_active_and_matching_lease

-- ============================================================================
-- 定理 9〜16: 二段階 Handoff（quiesced → drained）の順序契約とトークン単調性・挿抜/切断
-- ============================================================================

-- 9. quiesced だけでは（markDrained が呼ばれるまでは）まだ Phase.releasing のままであり、次所有者に Active は渡らない。
theorem quiesced_alone_stays_releasing (g : GearModel) (oldLease : Lease) (nextClient : Option Nat)
    (hPending : g.pending = some ⟨oldLease, nextClient, false⟩) :
    markQuiesced g oldLease.sessionId oldLease.token =
      Outcome.ok {
        g with
        phase := Phase.releasing
        lease := some oldLease
        releasingTo := nextClient
        pending := some ⟨oldLease, nextClient, true⟩
      } := by
  unfold markQuiesced
  rw [hPending]
  dsimp only
  rw [natEq_refl oldLease.sessionId, natEq_refl oldLease.token]
  rfl

#print axioms quiesced_alone_stays_releasing

-- 10. quiesced より先に markDrained を呼ぶと（quiesced = false の間は）必ず AccessError.pending で拒否される（Broker::drained の単方向順序契約）。
theorem drained_before_quiesced_returns_pending (g : GearModel) (oldLease : Lease)
    (nextClient : Option Nat) (sid : Option Nat)
    (hPending : g.pending = some ⟨oldLease, nextClient, false⟩) :
    markDrained g sid = Outcome.error AccessError.pending := by
  unfold markDrained
  rw [hPending]

#print axioms drained_before_quiesced_returns_pending

-- 11. 異なる token または異なる session からの markQuiesced は必ず AccessError.staleLease で拒否される。
theorem markQuiesced_rejects_wrong_token (g : GearModel) (p : PendingRelease)
    (session token : Nat)
    (hPending : g.pending = some p)
    (hWrong : (natEq p.fromLease.sessionId session && natEq p.fromLease.token token) = false) :
    markQuiesced g session token = Outcome.error AccessError.staleLease := by
  unfold markQuiesced
  rw [hPending]
  dsimp only
  rw [hWrong]

#print axioms markQuiesced_rejects_wrong_token

-- 12. quiesced → drained の正しい順序で完了すると、同一セッション・別セッションを問わず必ず新しい token (nextToken + 1) が発行され Phase.active になる。
theorem handoff_completion_issues_fresh_token (g : GearModel)
    (oldLease : Lease) (nextClient newSid : Nat)
    (hPending : g.pending = some ⟨oldLease, some nextClient, true⟩)
    (hAssign : g.assignment.clientId = some nextClient)
    (hPresent : g.present = true) :
    markDrained g (some newSid) =
      Outcome.ok {
        g with
        phase := Phase.active
        lease := some ⟨newSid, g.nextToken + 1⟩
        releasingTo := none
        pending := none
        nextToken := g.nextToken + 1
      } := by
  unfold markDrained
  rw [hPending]
  unfold activateForOwner
  dsimp only
  rw [hAssign, hPresent]

#print axioms handoff_completion_issues_fresh_token

-- 13. 新しい lease (newSid, oldToken + 1) に切り替わった後は、旧所有者の (oldSid, oldToken) による authorizeOutput は
--     たとえ同一セッション ID が再利用されても（newSid = oldSid でも）必ず staleLease で拒否される。
theorem old_lease_rejected_after_handoff (g : GearModel) (newSid oldSid oldToken : Nat) :
    authorizeOutput {
      g with
      phase := Phase.active
      lease := some ⟨newSid, oldToken + 1⟩
      releasingTo := none
      pending := none
      nextToken := oldToken + 1
    } oldSid oldToken = Outcome.error AccessError.staleLease := by
  unfold authorizeOutput
  dsimp only
  rw [natEq_succ_ne_self oldToken]
  cases natEq newSid oldSid <;> rfl

#print axioms old_lease_rejected_after_handoff

-- 14. active lease がある状態で抜線（unplugGear）またはセッション切断（disconnectOwnerSession）が起きると、
--     即座に lease を捨てず Phase.releasing に遷移してドライバの drain を待つ。
theorem unplug_with_lease_enters_releasing (g : GearModel) (oldLease : Lease)
    (hNoPending : g.pending = none) (hLease : g.lease = some oldLease) :
    (unplugGear g).phase = Phase.releasing ∧ (unplugGear g).lease = some oldLease := by
  unfold unplugGear
  rw [hNoPending, hLease]
  exact ⟨rfl, rfl⟩

#print axioms unplug_with_lease_enters_releasing

theorem disconnect_with_lease_enters_releasing_and_quiescent (g : GearModel) (oldLease : Lease)
    (hNoPending : g.pending = none) (hLease : g.lease = some oldLease) :
    (disconnectOwnerSession g).phase = Phase.releasing ∧
    (disconnectOwnerSession g).pending = some ⟨oldLease, none, true⟩ := by
  unfold disconnectOwnerSession
  rw [hNoPending, hLease]
  exact ⟨rfl, rfl⟩

#print axioms disconnect_with_lease_enters_releasing_and_quiescent

-- 15. drain 完了後（または lease 無し時）、機器が取り外されている（present = false）か所有アプリのセッションが無い（activeSession = none）なら、
--     activateForOwner は必ず lease = none に落として waiting（または off）にする。
theorem absent_gear_never_holds_lease (g : GearModel) (sid : Option Nat)
    (hAbsent : g.present = false) :
    (activateForOwner g sid).lease = none := by
  unfold activateForOwner
  cases g.assignment.clientId with
  | none => rfl
  | some _ => rw [hAbsent]

#print axioms absent_gear_never_holds_lease

theorem disconnected_owner_never_holds_lease (g : GearModel) :
    (activateForOwner g none).lease = none := by
  unfold activateForOwner
  cases g.assignment.clientId with
  | none => rfl
  | some _ =>
    cases g.present with
    | false => rfl
    | true => rfl

#print axioms disconnected_owner_never_holds_lease

-- 16. activateForOwner が返す状態で Phase.active であれば、必ず present = true かつ lease ≠ none である。
theorem active_implies_present_and_has_lease (g : GearModel) (sid : Option Nat)
    (hActive : (activateForOwner g sid).phase = Phase.active) :
    g.present = true ∧ (activateForOwner g sid).lease ≠ none := by
  cases g with
  | mk present assignment phase lease releasingTo pending nextToken =>
    cases assignment with
    | mk clientId revision expected =>
      cases clientId with
      | none => cases hActive
      | some c =>
        cases present with
        | false => cases hActive
        | true =>
          cases sid with
          | none => cases hActive
          | some s =>
            refine ⟨rfl, ?_⟩
            cases lease with
            | none =>
              intro hNone
              cases hNone
            | some current =>
              unfold activateForOwner at hActive ⊢
              dsimp only at hActive ⊢
              cases (natEq current.sessionId s && phase.isActive) with
              | true =>
                intro hNone
                cases hNone
              | false =>
                intro hNone
                cases hNone

#print axioms active_implies_present_and_has_lease

-- ============================================================================
-- 定理 17〜23: lnx-gear（maru / ROTO / Keystage）の 7bit/14bit 変換と SysEx 安全性
-- ============================================================================

-- 8bit バイトと 7bit ワードの構成的ビット表現（公理ゼロ）。
structure Word7 where
  b6 : Bool
  b5 : Bool
  b4 : Bool
  b3 : Bool
  b2 : Bool
  b1 : Bool
  b0 : Bool

structure Byte8 where
  b7 : Bool -- 最上位ビット (0x80): MIDI ステータス / データ識別ビット
  b6 : Bool
  b5 : Bool
  b4 : Bool
  b3 : Bool
  b2 : Bool
  b1 : Bool
  b0 : Bool

structure Word14 where
  hi : Word7
  lo : Word7

-- `& 0x7F` マスクと 7bit ワード変換
def mask7 (b : Byte8) : Byte8 := { b with b7 := false }

def Word7.toByte8 (w : Word7) : Byte8 :=
  ⟨false, w.b6, w.b5, w.b4, w.b3, w.b2, w.b1, w.b0⟩

def Byte8.truncate7 (b : Byte8) : Word7 :=
  ⟨b.b6, b.b5, b.b4, b.b3, b.b2, b.b1, b.b0⟩

-- SysEx データバイトは最上位ビット b7 (0x80) が false でなければならない。
def isSysExDataByte (b : Byte8) : Bool := !b.b7

-- SysEx 終端バイト 0xF7 (1111_0111)
def sysexEndF7 : Byte8 := ⟨true, true, true, true, false, true, true, true⟩

-- SysEx 開始バイト 0xF0 (1111_0000)
def sysexStartF0 : Byte8 := ⟨true, true, true, true, false, false, false, false⟩

-- Korg メーカー ID 0x42 (0100_0010)
def vendorKorg42 : Byte8 := ⟨false, true, false, false, false, false, true, false⟩

-- Keystage family/command 定数バイト
def byte00 : Byte8 := ⟨false, false, false, false, false, false, false, false⟩
def byte01 : Byte8 := ⟨false, false, false, false, false, false, false, true⟩
def byte02 : Byte8 := ⟨false, false, false, false, false, false, true, false⟩
def byte09 : Byte8 := ⟨false, false, false, false, true, false, false, true⟩
def byte69 : Byte8 := ⟨false, true, true, false, true, false, false, true⟩
def byte6F : Byte8 := ⟨false, true, true, false, true, true, true, true⟩

-- 17. mask7 を通した任意のバイトは最上位ビットが false であり、SysEx データバイトとして安全。
theorem mask7_is_sysex_safe (b : Byte8) :
    isSysExDataByte (mask7 b) = true := by
  rfl

#print axioms mask7_is_sysex_safe

-- 18. mask7 を通した任意のバイトは SysEx 終端バイト 0xF7 と決して等しくならない。
theorem mask7_never_f7 (b : Byte8) :
    mask7 b ≠ sysexEndF7 := by
  intro hEq
  have hBit : (mask7 b).b7 = sysexEndF7.b7 := congrArg Byte8.b7 hEq
  cases hBit

#print axioms mask7_never_f7

-- 19. maru::split14 分割（Word14 → 2 つの Byte8）は上位・下位ともに常に SysEx データバイトとして安全（MSB = 0）。
def unpackWord14Hi (w : Word14) : Byte8 := w.hi.toByte8
def unpackWord14Lo (w : Word14) : Byte8 := w.lo.toByte8

theorem unpack14Hi_sysex_safe (w : Word14) :
    isSysExDataByte (unpackWord14Hi w) = true := by
  rfl

#print axioms unpack14Hi_sysex_safe

-- 20. maru::split14 分割の下位バイトも常に SysEx 安全（MSB = 0）かつ 0xF7 にならない。
theorem unpack14Lo_sysex_safe (w : Word14) :
    isSysExDataByte (unpackWord14Lo w) = true ∧ unpackWord14Lo w ≠ sysexEndF7 := by
  refine ⟨rfl, ?_⟩
  intro hEq
  have hBit : (unpackWord14Lo w).b7 = sysexEndF7.b7 := congrArg Byte8.b7 hEq
  cases hBit

#print axioms unpack14Lo_sysex_safe

-- 21. 14bit 値（上位 7bit × 下位 7bit）の 2 バイトへのエンコードとデコードは任意の入力で完全に往復する。
def encodeWord14 (w : Word14) : Byte8 × Byte8 :=
  (unpackWord14Hi w, unpackWord14Lo w)

def decodeWord14 (pair : Byte8 × Byte8) : Word14 :=
  ⟨pair.1.truncate7, pair.2.truncate7⟩

theorem word14_roundtrip (w : Word14) :
    decodeWord14 (encodeWord14 w) = w := by
  cases w with
  | mk hi lo =>
    cases hi
    cases lo
    rfl

#print axioms word14_roundtrip

-- 22. MaruInput の連続 Lo CC メッセージ（CC 33 / CC 34）の法則:
--     上位バイト hi（CC 1 / CC 2）が一度記憶された状態で下位バイト lo1, lo2 が連続して届くと、
--     それぞれのイベントは同じ hi と最新の lo を組み合わせた Word14 を出力し、記憶された hi は破壊されない。
structure MaruAxisState where
  storedHi : Word7

def onMaruCcHi (_st : MaruAxisState) (hi : Word7) : MaruAxisState :=
  ⟨hi⟩

def onMaruCcLo (st : MaruAxisState) (lo : Word7) : MaruAxisState × Word14 :=
  (st, ⟨st.storedHi, lo⟩)

theorem maru_consecutive_lo_preserves_hi (st : MaruAxisState) (hi lo1 lo2 : Word7) :
    let st1 := onMaruCcHi st hi
    let (st2, ev1) := onMaruCcLo st1 lo1
    let (st3, ev2) := onMaruCcLo st2 lo2
    ev1 = ⟨hi, lo1⟩ ∧ ev2 = ⟨hi, lo2⟩ ∧ st3.storedHi = hi := by
  exact ⟨rfl, rfl, rfl⟩

#print axioms maru_consecutive_lo_preserves_hi

-- 23. crates/lnx-gear/src/keystage.rs の 13 バイト Connection Mode フレーム変換（disconnect_after / is_disconnect）の構造証明:
--     [0xF0, 0x42, 0x40|ch, 0x00, 0x01, 0x69, model(1|9), 0x02, 0x00, 0x00, 0x6F, mode(1→0), 0xF7]
--     任意の有効な connect フレーム（mode = true）に対して disconnectAfter は some f' を返し、
--     f' は isDisconnect f' = true を満たし、channel と model を保存し、2 回目の disconnectAfter f' は none を返す。
structure Nibble4 where
  b3 : Bool
  b2 : Bool
  b1 : Bool
  b0 : Bool

inductive KeystageModel where
  | k49 -- 0x01
  | k61 -- 0x09

def KeystageModel.toByte8 : KeystageModel → Byte8
  | .k49 => byte01
  | .k61 => byte09

-- 13 バイトの Keystage Connection Mode SysEx フレーム（b0..b12）
structure KeystageConnectionFrame where
  b0 : Byte8  -- 0xF0
  b1 : Byte8  -- 0x42 (Korg)
  b2 : Byte8  -- 0x40 | ch
  b3 : Byte8  -- 0x00
  b4 : Byte8  -- 0x01
  b5 : Byte8  -- 0x69 (Keystage family)
  b6 : Byte8  -- model (0x01 or 0x09)
  b7 : Byte8  -- 0x02
  b8 : Byte8  -- 0x00
  b9 : Byte8  -- 0x00
  b10 : Byte8 -- 0x6F (Connection mode command)
  mode : Bool -- b11: true = 0x01 (connect), false = 0x00 (disconnect)
  b12 : Byte8 -- 0xF7

def encodeKorgChannel40 (ch : Nibble4) : Byte8 :=
  ⟨false, true, false, false, ch.b3, ch.b2, ch.b1, ch.b0⟩

def decodeKorgChannel40 (b : Byte8) : Nibble4 :=
  ⟨b.b3, b.b2, b.b1, b.b0⟩

def buildKeystageConnect (ch : Nibble4) (m : KeystageModel) : KeystageConnectionFrame :=
  { b0 := sysexStartF0
    b1 := vendorKorg42
    b2 := encodeKorgChannel40 ch
    b3 := byte00
    b4 := byte01
    b5 := byte69
    b6 := m.toByte8
    b7 := byte02
    b8 := byte00
    b9 := byte00
    b10 := byte6F
    mode := true
    b12 := sysexEndF7 }

-- keystage::disconnect_after の構造モデル: mode == true (1) のときのみ mode := false (0) に落とした逆フレームを返す。
def keystageDisconnectAfter (f : KeystageConnectionFrame) : Option KeystageConnectionFrame :=
  match f.mode with
  | true => some { f with mode := false }
  | false => none

-- keystage::is_disconnect の構造モデル: mode == false (0)。
def keystageIsDisconnect (f : KeystageConnectionFrame) : Bool :=
  !f.mode

theorem keystage_disconnect_after_is_disconnect_and_idempotent (ch : Nibble4) (m : KeystageModel) :
    let connect := buildKeystageConnect ch m
    let disconnected := { connect with mode := false }
    keystageDisconnectAfter connect = some disconnected ∧
    keystageIsDisconnect disconnected = true ∧
    decodeKorgChannel40 disconnected.b2 = ch ∧
    disconnected.b6 = m.toByte8 ∧
    keystageDisconnectAfter disconnected = none := by
  cases ch
  cases m <;> exact ⟨rfl, rfl, rfl, rfl, rfl⟩

#print axioms keystage_disconnect_after_is_disconnect_and_idempotent

end LnxCore
