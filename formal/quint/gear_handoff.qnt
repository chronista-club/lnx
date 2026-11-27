// mem_1ChTPJv4KqgX7AuML7cY5T
// lnx-protocol (Broker) の有限抽象モデル。
// 「どのアプリがどの Gear を使うか」の設計規則（明示 takeover・Quiesce 待機・Drain フェンス・単調増加 Lease Token）を
// 1 つずつ外した比較モードで反例が出ることを確かめる。
module gearHandoffModel {
  const REQUIRE_TAKEOVER_CONFIRM: bool
  const WAIT_FOR_QUIESCE: bool
  const WAIT_FOR_DRAIN: bool
  const MONOTONIC_LEASE_TOKEN: bool

  type StepOutcome = {
    phase: str,
    assignedClient: str,
    revision: int,
    leaseSession: str,
    leaseToken: int,
    releasingTo: str,
    quiesced: bool,
    drained: bool,
    lastError: str,
    previousToken: int,
    staleOutputAccepted: bool,
    implicitTakeoverHappened: bool,
    prematureActiveWithoutQuiesce: bool,
    prematureActiveWithoutDrain: bool,
  }

  var outcome: StepOutcome

  pure def initialOutcome: StepOutcome = {
    phase: "active",
    assignedClient: "ladyland",
    revision: 1,
    leaseSession: "sess_ladyland",
    leaseToken: 1,
    releasingTo: "",
    quiesced: false,
    drained: false,
    lastError: "",
    previousToken: 1,
    staleOutputAccepted: false,
    implicitTakeoverHappened: false,
    prematureActiveWithoutQuiesce: false,
    prematureActiveWithoutDrain: false,
  }

  // 他のアプリ（vp）が takeover フラグ付き/無しで SetEnabled(enabled=true) を送り、
  // その後 quiesce / drain の完了有無と旧 token での SendMidi 試行を評価する純粋遷移関数。
  pure def evaluateSequence(
    takeoverFlag: bool,
    doQuiesce: bool,
    doDrain: bool,
    tryStaleOutputAfter: bool
  ): StepOutcome = {
    val start = initialOutcome
    val foreign = start.assignedClient != "vp"
    // 1. SetEnabled from "vp"
    val afterRequest =
      if (foreign and not(takeoverFlag) and REQUIRE_TAKEOVER_CONFIRM) {
        { ...start, lastError: "conflict" }
      } else {
        val implicitTakeover = foreign and not(takeoverFlag)
        val qDone = if (WAIT_FOR_QUIESCE) false else true
        val dDone = if (WAIT_FOR_DRAIN) false else true
        if (qDone and dDone) {
          val nextTok = if (MONOTONIC_LEASE_TOKEN) start.leaseToken + 1 else start.leaseToken
          {
            ...start,
            phase: "active",
            assignedClient: "vp",
            revision: start.revision + 1,
            leaseSession: "sess_vp",
            leaseToken: nextTok,
            releasingTo: "",
            quiesced: false,
            drained: false,
            lastError: "",
            previousToken: start.leaseToken,
            implicitTakeoverHappened: implicitTakeover,
            prematureActiveWithoutQuiesce: true,
            prematureActiveWithoutDrain: true,
          }
        } else {
          {
            ...start,
            phase: "releasing",
            assignedClient: "vp",
            revision: start.revision + 1,
            releasingTo: "vp",
            quiesced: qDone,
            drained: dDone,
            lastError: "",
            previousToken: start.leaseToken,
            implicitTakeoverHappened: implicitTakeover,
          }
        }
      }

    // 2. Quiesced / Drained イベントの到着
    val afterEvents =
      if (afterRequest.phase != "releasing") {
        afterRequest
      } else {
        val qNow = afterRequest.quiesced or doQuiesce
        val dNow = afterRequest.drained or doDrain
        if (qNow and dNow) {
          val nextTok = if (MONOTONIC_LEASE_TOKEN) afterRequest.leaseToken + 1 else afterRequest.leaseToken
          {
            ...afterRequest,
            phase: "active",
            leaseSession: "sess_vp",
            leaseToken: nextTok,
            releasingTo: "",
            quiesced: qNow,
            drained: dNow,
            prematureActiveWithoutQuiesce: not(doQuiesce),
            prematureActiveWithoutDrain: not(doDrain),
          }
        } else {
          {
            ...afterRequest,
            quiesced: qNow,
            drained: dNow,
          }
        }
      }

    // 3. 旧 lease token（previousToken）を使った遅延出力（SendMidi / Present）の検査
    //    同一アプリのセッション再接続やトークン再利用があると token 比較だけで通過してしまう境界を検査。
    val staleAccepted =
      if (tryStaleOutputAfter and afterEvents.phase == "active" and afterEvents.assignedClient == "vp") {
        afterEvents.leaseToken == afterEvents.previousToken
      } else {
        false
      }

    { ...afterEvents, staleOutputAccepted: staleAccepted }
  }

  action setOutcome(o: StepOutcome): bool = all {
    outcome' = o
  }

  action init = setOutcome(initialOutcome)

  action step = {
    nondet takeoverFlag = Set(false, true).oneOf()
    nondet doQuiesce = Set(false, true).oneOf()
    nondet doDrain = Set(false, true).oneOf()
    nondet tryStaleOutputAfter = Set(false, true).oneOf()
    setOutcome(evaluateSequence(takeoverFlag, doQuiesce, doDrain, tryStaleOutputAfter))
  }

  // 不変条件
  val noImplicitTakeover = not(outcome.implicitTakeoverHappened)
  val handoffWaitsForQuiesce = not(outcome.prematureActiveWithoutQuiesce)
  val handoffWaitsForDrain = not(outcome.prematureActiveWithoutDrain)
  val staleLeaseOutputRejected = not(outcome.staleOutputAccepted)
  val allInvariants = and {
    noImplicitTakeover,
    handoffWaitsForQuiesce,
    handoffWaitsForDrain,
    staleLeaseOutputRejected,
    outcome.phase != "active" or outcome.leaseToken >= 1,
  }

  // 8 個のシナリオ（比較モードでも各モードの定数に応じた期待振る舞いを検証するため全モードで pass する）
  run conflictWithoutTakeoverTest = init.then(setOutcome(evaluateSequence(false, false, false, false))).expect(and {
    (outcome.lastError == "conflict") == REQUIRE_TAKEOVER_CONFIRM,
    noImplicitTakeover == REQUIRE_TAKEOVER_CONFIRM,
  })

  run takeoverEntersReleasingTest = init.then(setOutcome(evaluateSequence(true, false, false, false))).expect(and {
    (outcome.phase == "releasing") == (WAIT_FOR_QUIESCE or WAIT_FOR_DRAIN),
    outcome.assignedClient == "vp",
    outcome.revision == 2,
  })

  run quiesceOnlyWaitTest = init.then(setOutcome(evaluateSequence(true, true, false, false))).expect(and {
    (outcome.phase == "releasing") == WAIT_FOR_DRAIN,
    handoffWaitsForDrain == WAIT_FOR_DRAIN,
  })

  run drainOnlyWaitTest = init.then(setOutcome(evaluateSequence(true, false, true, false))).expect(and {
    (outcome.phase == "releasing") == WAIT_FOR_QUIESCE,
    handoffWaitsForQuiesce == WAIT_FOR_QUIESCE,
  })

  run fullHandoffCompletesTest = init.then(setOutcome(evaluateSequence(true, true, true, false))).expect(and {
    outcome.phase == "active",
    outcome.assignedClient == "vp",
    outcome.leaseSession == "sess_vp",
    outcome.releasingTo == "",
    handoffWaitsForQuiesce == (WAIT_FOR_QUIESCE or WAIT_FOR_DRAIN),
    handoffWaitsForDrain == (WAIT_FOR_QUIESCE or WAIT_FOR_DRAIN),
  })

  run monotonicLeaseTokenTest = init.then(setOutcome(evaluateSequence(true, true, true, true))).expect(and {
    (outcome.leaseToken == 2) == MONOTONIC_LEASE_TOKEN,
    staleLeaseOutputRejected == MONOTONIC_LEASE_TOKEN,
  })

  run releasingKeepsOldLeaseTokenUntilCompleteTest = init.then(setOutcome(evaluateSequence(true, false, false, true))).expect(and {
    not(WAIT_FOR_QUIESCE and WAIT_FOR_DRAIN) or (outcome.phase == "releasing" and outcome.leaseToken == 1),
  })

  run currentDesignSatisfiesAllTest = init.then(setOutcome(evaluateSequence(true, true, true, true))).expect(and {
    allInvariants == MONOTONIC_LEASE_TOKEN,
  })
}

module naive {
  import gearHandoffModel(
    REQUIRE_TAKEOVER_CONFIRM=false,
    WAIT_FOR_QUIESCE=false,
    WAIT_FOR_DRAIN=false,
    MONOTONIC_LEASE_TOKEN=false
  ).*
}

module noTakeoverConfirm {
  import gearHandoffModel(
    REQUIRE_TAKEOVER_CONFIRM=false,
    WAIT_FOR_QUIESCE=true,
    WAIT_FOR_DRAIN=true,
    MONOTONIC_LEASE_TOKEN=true
  ).*
}

module skipQuiesceWait {
  import gearHandoffModel(
    REQUIRE_TAKEOVER_CONFIRM=true,
    WAIT_FOR_QUIESCE=false,
    WAIT_FOR_DRAIN=true,
    MONOTONIC_LEASE_TOKEN=true
  ).*
}

module skipDrainFence {
  import gearHandoffModel(
    REQUIRE_TAKEOVER_CONFIRM=true,
    WAIT_FOR_QUIESCE=true,
    WAIT_FOR_DRAIN=false,
    MONOTONIC_LEASE_TOKEN=true
  ).*
}

module reusableLeaseToken {
  import gearHandoffModel(
    REQUIRE_TAKEOVER_CONFIRM=true,
    WAIT_FOR_QUIESCE=true,
    WAIT_FOR_DRAIN=true,
    MONOTONIC_LEASE_TOKEN=false
  ).*
}

module lnxCurrent {
  import gearHandoffModel(
    REQUIRE_TAKEOVER_CONFIRM=true,
    WAIT_FOR_QUIESCE=true,
    WAIT_FOR_DRAIN=true,
    MONOTONIC_LEASE_TOKEN=true
  ).*
}
