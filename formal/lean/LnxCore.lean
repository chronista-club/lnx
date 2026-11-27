/-
  lnx-protocol と lnx-gear の構造法則（Lean 4.36.0、公理ゼロ証明）。
  「どのアプリがどの Gear を使うか」を司る Broker の排他 lease・二段階 handoff・
  epoch/token 単調増加・stale_lease 出力拒否、および Gear 層の 7bit/14bit 正規化・
  SysEx 7bit 安全性を、sorry / propext / Quot.sound / Classical.choice を使わず構成的に証明する。
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

structure PendingRelease where
  fromLease : Lease
  toClient : Option Nat
  quiesced : Bool
  drained : Bool

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

-- クライアントと有効セッションに応じた active/waiting/off の割り当て（let 束縛を使わず直接分岐）。
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

-- Broker::reconcile の単一 Gear 構造モデル。
def reconcile (g : GearModel) (activeSession : Option Nat) : GearModel :=
  match g.pending with
  | some p =>
    match p.quiesced && p.drained with
    | false =>
      { g with
        phase := Phase.releasing
        lease := some p.fromLease
        releasingTo := p.toClient }
    | true => activateForOwner g activeSession
  | none => activateForOwner g activeSession

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

-- Broker::quiesced の構造モデル。
def markQuiesced (g : GearModel) (session : Nat) (token : Nat) (activeSession : Option Nat) :
    Outcome GearModel :=
  match g.pending with
  | some p =>
    match natEq p.fromLease.sessionId session && natEq p.fromLease.token token with
    | true =>
      Outcome.ok (reconcile { g with pending := some { p with quiesced := true } } activeSession)
    | false => Outcome.error AccessError.staleLease
  | none => Outcome.error AccessError.staleLease

-- Broker::drained の構造モデル。
def markDrained (g : GearModel) (activeSession : Option Nat) :
    Outcome GearModel :=
  match g.pending with
  | some p =>
    Outcome.ok (reconcile { g with pending := some { p with drained := true } } activeSession)
  | none => Outcome.error AccessError.staleLease

def isForeignOwner (currentOwner : Option Nat) (client : Nat) : Bool :=
  match currentOwner with
  | none => false
  | some owner => !natEq owner client

def canDisableOwner (currentOwner : Option Nat) (client : Nat) (takeover : Bool) : Bool :=
  match currentOwner with
  | none => true
  | some owner => natEq owner client || takeover

-- Broker::set_enabled の構造モデル。
def setEnabled (g : GearModel) (client : Nat) (enabled : Bool) (expectedRevision : Nat)
    (takeover : Bool) (activeSession : Option Nat) : Outcome GearModel :=
  match g.pending with
  | some _ => Outcome.error AccessError.pending
  | none =>
    match natEq g.assignment.revision expectedRevision with
    | false => Outcome.error AccessError.staleRevision
    | true =>
      match enabled with
      | true =>
        match isForeignOwner g.assignment.clientId client && !takeover with
        | true => Outcome.error AccessError.conflict
        | false =>
          match isForeignOwner g.assignment.clientId client, g.lease with
          | true, some oldLease =>
            Outcome.ok (reconcile {
              g with
              assignment := ⟨some client, g.assignment.revision + 1, false⟩
              pending := some ⟨oldLease, some client, false, false⟩
            } activeSession)
          | true, none =>
            Outcome.ok (reconcile {
              g with
              assignment := ⟨some client, g.assignment.revision + 1, false⟩
            } activeSession)
          | false, some _ =>
            Outcome.ok (reconcile {
              g with
              assignment := ⟨some client, g.assignment.revision + 1, false⟩
            } activeSession)
          | false, none =>
            Outcome.ok (reconcile {
              g with
              assignment := ⟨some client, g.assignment.revision + 1, false⟩
            } activeSession)
      | false =>
        match canDisableOwner g.assignment.clientId client takeover with
        | false => Outcome.error AccessError.conflict
        | true =>
          match g.lease with
          | some oldLease =>
            Outcome.ok (reconcile {
              g with
              assignment := ⟨none, g.assignment.revision + 1, false⟩
              pending := some ⟨oldLease, none, false, false⟩
            } activeSession)
          | none =>
            Outcome.ok (reconcile {
              g with
              assignment := ⟨none, g.assignment.revision + 1, false⟩
            } activeSession)

-- ============================================================================
-- 定理 1〜7: Broker の排他・リビジョン・テイクオーバー・出力フェンス法則
-- ============================================================================

-- 1. PendingRelease が進行中（Releasing）の間は、新規の setEnabled は必ず AccessError.pending で拒否される。
theorem setEnabled_rejected_while_pending (g : GearModel) (p : PendingRelease)
    (client : Nat) (enabled : Bool) (rev : Nat) (takeover : Bool) (sid : Option Nat)
    (h : g.pending = some p) :
    setEnabled g client enabled rev takeover sid = Outcome.error AccessError.pending := by
  unfold setEnabled
  rw [h]

#print axioms setEnabled_rejected_while_pending

-- 2. expectedRevision が不一致の setEnabled は、pending が無ければ必ず AccessError.staleRevision で拒否される。
theorem setEnabled_rejects_stale_revision (g : GearModel) (client : Nat) (enabled : Bool)
    (rev : Nat) (takeover : Bool) (sid : Option Nat)
    (hNoPending : g.pending = none) (hStale : natEq g.assignment.revision rev = false) :
    setEnabled g client enabled rev takeover sid = Outcome.error AccessError.staleRevision := by
  unfold setEnabled
  rw [hNoPending, hStale]

#print axioms setEnabled_rejects_stale_revision

-- 3. 他のアプリが所有している Gear に対して takeover = false で enabled = true を要求すると必ず AccessError.conflict になる。
theorem setEnabled_requires_takeover_for_foreign_owner (g : GearModel) (owner client : Nat)
    (sid : Option Nat) (hNoPending : g.pending = none)
    (hOwner : g.assignment.clientId = some owner) (hNe : natEq owner client = false) :
    setEnabled g client true g.assignment.revision false sid = Outcome.error AccessError.conflict := by
  unfold setEnabled isForeignOwner
  rw [hNoPending, natEq_refl g.assignment.revision, hOwner]
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
        pending := some ⟨oldLease, some client, false, false⟩
      } := by
  unfold setEnabled isForeignOwner
  rw [hNoPending, natEq_refl g.assignment.revision, hOwner, hLease]
  dsimp only
  rw [hNe]
  rfl

#print axioms takeover_enters_releasing_and_keeps_old_lease

-- 5. Phase.releasing の間は、旧所有者であっても新所有者であっても authorizeOutput（SendMidi / Present）は必ず staleLease で拒否される。
theorem releasing_rejects_all_outputs (g : GearModel) (session token : Nat)
    (hPhase : g.phase = Phase.releasing) :
    authorizeOutput g session token = Outcome.error AccessError.staleLease := by
  unfold authorizeOutput
  rw [hPhase]

#print axioms releasing_rejects_all_outputs

-- 6. Phase.waiting / off / error でも authorizeOutput は必ず staleLease で拒否される。
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

-- 7. authorizeOutput が ok を返すなら、必ず Phase.active である。
theorem authorizeOutput_ok_implies_active (g : GearModel) (session token : Nat)
    (hOk : authorizeOutput g session token = Outcome.ok ()) :
    g.phase = Phase.active := by
  unfold authorizeOutput at hOk
  cases hp : g.phase with
  | active => rfl
  | off => rw [hp] at hOk; cases hOk
  | waiting => rw [hp] at hOk; cases hOk
  | releasing => rw [hp] at hOk; cases hOk
  | error => rw [hp] at hOk; cases hOk

#print axioms authorizeOutput_ok_implies_active

-- ============================================================================
-- 定理 8〜15: 二段階 Handoff（quiesced × drained）とトークン単調性・不在時解放
-- ============================================================================

-- 8. quiesced だけでは（drained = false の間は）まだ Phase.releasing のままであり、次所有者に Active は渡らない。
theorem quiesced_alone_stays_releasing (g : GearModel) (oldLease : Lease) (nextClient : Option Nat)
    (sid : Option Nat)
    (hPending : g.pending = some ⟨oldLease, nextClient, false, false⟩) :
    markQuiesced g oldLease.sessionId oldLease.token sid =
      Outcome.ok {
        g with
        phase := Phase.releasing
        lease := some oldLease
        releasingTo := nextClient
        pending := some ⟨oldLease, nextClient, true, false⟩
      } := by
  unfold markQuiesced
  rw [hPending]
  dsimp only
  rw [natEq_refl oldLease.sessionId, natEq_refl oldLease.token]
  rfl

#print axioms quiesced_alone_stays_releasing

-- 9. drained だけでは（quiesced = false の間は）まだ Phase.releasing のままであり、次所有者に Active は渡らない。
theorem drained_alone_stays_releasing (g : GearModel) (oldLease : Lease) (nextClient : Option Nat)
    (sid : Option Nat)
    (hPending : g.pending = some ⟨oldLease, nextClient, false, false⟩) :
    markDrained g sid =
      Outcome.ok {
        g with
        phase := Phase.releasing
        lease := some oldLease
        releasingTo := nextClient
        pending := some ⟨oldLease, nextClient, false, true⟩
      } := by
  unfold markDrained
  rw [hPending]
  rfl

#print axioms drained_alone_stays_releasing

-- 10. 異なる token または異なる session からの markQuiesced は必ず AccessError.staleLease で拒否される。
theorem markQuiesced_rejects_wrong_token (g : GearModel) (p : PendingRelease)
    (session token : Nat) (sid : Option Nat)
    (hPending : g.pending = some p)
    (hWrong : (natEq p.fromLease.sessionId session && natEq p.fromLease.token token) = false) :
    markQuiesced g session token sid = Outcome.error AccessError.staleLease := by
  unfold markQuiesced
  rw [hPending]
  dsimp only
  rw [hWrong]

#print axioms markQuiesced_rejects_wrong_token

-- 11. quiesced → drained の順でも drained → quiesced の順でも、完了後の GearModel は完全に一致する（二段階フェンスの可換性）。
theorem handoff_quiesce_then_drain_eq_drain_then_quiesce (g : GearModel)
    (oldLease : Lease) (nextClient : Option Nat) (sid : Option Nat)
    (hPending : g.pending = some ⟨oldLease, nextClient, false, false⟩) :
    (match markQuiesced g oldLease.sessionId oldLease.token sid with
     | Outcome.ok g1 => markDrained g1 sid
     | Outcome.error e => Outcome.error e) =
    (match markDrained g sid with
     | Outcome.ok g1 => markQuiesced g1 oldLease.sessionId oldLease.token sid
     | Outcome.error e => Outcome.error e) := by
  rw [quiesced_alone_stays_releasing g oldLease nextClient sid hPending]
  rw [drained_alone_stays_releasing g oldLease nextClient sid hPending]
  unfold markDrained markQuiesced
  dsimp only
  rw [natEq_refl oldLease.sessionId, natEq_refl oldLease.token]
  rfl

#print axioms handoff_quiesce_then_drain_eq_drain_then_quiesce

-- 12. handoff 完了時、新所有者の別セッション newSid に切り替わると必ず新しい token (nextToken + 1) が発行され Phase.active になる。
theorem handoff_completion_issues_fresh_token (g : GearModel)
    (oldLease : Lease) (nextClient newSid : Nat)
    (hPending : g.pending = some ⟨oldLease, some nextClient, true, false⟩)
    (hAssign : g.assignment.clientId = some nextClient)
    (hPresent : g.present = true)
    (hLease : g.lease = some oldLease)
    (hDiffSession : natEq oldLease.sessionId newSid = false) :
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
  unfold reconcile activateForOwner
  dsimp only
  rw [hAssign, hPresent, hLease]
  dsimp only
  rw [hDiffSession]
  rfl

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

-- 14. 機器が取り外された（present = false）または所有アプリのセッションが消えた（activeSession = none）場合、
--     pending が無ければ reconcile は必ず lease = none に落として waiting（または off）にする。
theorem absent_gear_never_holds_lease (g : GearModel) (sid : Option Nat)
    (hNoPending : g.pending = none) (hAbsent : g.present = false) :
    (reconcile g sid).lease = none := by
  unfold reconcile activateForOwner
  rw [hNoPending]
  dsimp only
  cases g.assignment.clientId with
  | none => rfl
  | some _ =>
    rw [hAbsent]

#print axioms absent_gear_never_holds_lease

theorem disconnected_owner_never_holds_lease (g : GearModel)
    (hNoPending : g.pending = none) :
    (reconcile g none).lease = none := by
  unfold reconcile activateForOwner
  rw [hNoPending]
  dsimp only
  cases g.assignment.clientId with
  | none => rfl
  | some _ =>
    cases g.present with
    | false => rfl
    | true => rfl

#print axioms disconnected_owner_never_holds_lease

-- 15. activateForOwner が返す状態で Phase.active であれば、必ず present = true かつ lease ≠ none である。
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
-- 定理 16〜22: lnx-gear（maru / ROTO / Keystage）の 7bit/14bit 変換と SysEx 安全性
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

-- 0x00 と 0x01
def byte00 : Byte8 := ⟨false, false, false, false, false, false, false, false⟩
def byte01 : Byte8 := ⟨false, false, false, false, false, false, false, true⟩

-- 16. mask7 を通した任意のバイトは最上位ビットが false であり、SysEx データバイトとして安全。
theorem mask7_is_sysex_safe (b : Byte8) :
    isSysExDataByte (mask7 b) = true := by
  rfl

#print axioms mask7_is_sysex_safe

-- 17. mask7 を通した任意のバイトは SysEx 終端バイト 0xF7 と決して等しくならない。
theorem mask7_never_f7 (b : Byte8) :
    mask7 b ≠ sysexEndF7 := by
  intro hEq
  have hBit : (mask7 b).b7 = sysexEndF7.b7 := congrArg Byte8.b7 hEq
  cases hBit

#print axioms mask7_never_f7

-- 18. maru の u14 分割（Word14 → 2 つの Byte8）は上位・下位ともに常に SysEx データバイトとして安全（MSB = 0）。
def unpackWord14Hi (w : Word14) : Byte8 := w.hi.toByte8
def unpackWord14Lo (w : Word14) : Byte8 := w.lo.toByte8

theorem unpack14Hi_sysex_safe (w : Word14) :
    isSysExDataByte (unpackWord14Hi w) = true := by
  rfl

#print axioms unpack14Hi_sysex_safe

-- 19. maru の u14 分割の下位バイトも常に SysEx 安全（MSB = 0）かつ 0xF7 にならない。
theorem unpack14Lo_sysex_safe (w : Word14) :
    isSysExDataByte (unpackWord14Lo w) = true ∧ unpackWord14Lo w ≠ sysexEndF7 := by
  refine ⟨rfl, ?_⟩
  intro hEq
  have hBit : (unpackWord14Lo w).b7 = sysexEndF7.b7 := congrArg Byte8.b7 hEq
  cases hBit

#print axioms unpack14Lo_sysex_safe

-- 20. 14bit 値（上位 7bit × 下位 7bit）の 2 バイトへのエンコードとデコードは任意の入力で完全に往復する。
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

-- 21. MaruInput の連続 Lo CC メッセージの法則:
--     上位バイト hi が一度記憶された状態で下位バイト lo1, lo2 が連続して届くと、
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

-- 22. Keystage Identity Reply (14 bytes) -> Connection Mode Disconnect SysEx (9 bytes) の構造検証:
--     Keystage の Identity Reply から生成した disconnect フレームは常に先頭が 0xF0, 0x42、
--     channel が 0x40 | ch（SysEx 安全）、末尾が 0x00, 0xF7 であり、同一の ch と model を保持する。
structure Nibble4 where
  b3 : Bool
  b2 : Bool
  b1 : Bool
  b0 : Bool

structure KeystageIdentity where
  channel : Nibble4
  modelLo : Word7
  modelHi : Word7

structure KeystageDisconnectFrame where
  sysexStart : Byte8
  vendorKorg : Byte8
  channelByte : Byte8
  subId1 : Byte8
  subId2 : Byte8
  modelLo : Byte8
  modelHi : Byte8
  modeOff : Byte8
  sysexEnd : Byte8

def encodeKorgChannel40 (ch : Nibble4) : Byte8 :=
  ⟨false, true, false, false, ch.b3, ch.b2, ch.b1, ch.b0⟩

def decodeKorgChannel40 (b : Byte8) : Nibble4 :=
  ⟨b.b3, b.b2, b.b1, b.b0⟩

def buildKeystageDisconnect (id : KeystageIdentity) : KeystageDisconnectFrame :=
  { sysexStart := sysexStartF0
    vendorKorg := vendorKorg42
    channelByte := encodeKorgChannel40 id.channel
    subId1 := byte00
    subId2 := byte01
    modelLo := id.modelLo.toByte8
    modelHi := id.modelHi.toByte8
    modeOff := byte00
    sysexEnd := sysexEndF7 }

theorem keystage_disconnect_frame_well_formed (id : KeystageIdentity) :
    let f := buildKeystageDisconnect id
    f.sysexStart = sysexStartF0 ∧
    f.vendorKorg = vendorKorg42 ∧
    isSysExDataByte f.channelByte = true ∧
    decodeKorgChannel40 f.channelByte = id.channel ∧
    f.modeOff = byte00 ∧
    f.sysexEnd = sysexEndF7 ∧
    f.modelLo.truncate7 = id.modelLo ∧
    f.modelHi.truncate7 = id.modelHi := by
  cases id with
  | mk ch mLo mHi =>
    cases ch
    cases mLo
    cases mHi
    exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

#print axioms keystage_disconnect_frame_well_formed

end LnxCore
