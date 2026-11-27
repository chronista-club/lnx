// mem_1ChTPJv4KqgX7AuML7cY5T
// lnx-protocol (Broker) のマルチステップ有限状態機械モデル。
// 「どのアプリがどの Gear を使うか」の設計規則（明示 takeover・Quiesce 待機・Drain フェンス・単調増加 Lease Token）を
// 1 つずつ外した比較モードで、状態遷移列から反例が見つかることを確かめる。
module gearHandoffModel {
  const REQUIRE_TAKEOVER_CONFIRM: bool
  const WAIT_FOR_QUIESCE: bool
  const WAIT_FOR_DRAIN: bool
  const MONOTONIC_LEASE_TOKEN: bool

  type BrokerState = {
    phase: str,
    assignedClient: str,
    revision: int,
    leaseSession: str,
    leaseToken: int,
    releasingTo: str,
    quiesced: bool,
    drained: bool,
    lastError: str,
    lastRequestHadTakeover: bool,
    previousToken: int,
    staleOutputAttempted: bool,
    staleOutputAccepted: bool,
  }

  var state: BrokerState

  pure def initialState: BrokerState = {
    phase: "active",
    assignedClient: "ladyland",
    revision: 1,
    leaseSession: "sess_ladyland",
    leaseToken: 1,
    releasingTo: "",
    quiesced: false,
    drained: false,
    lastError: "",
    lastRequestHadTakeover: false,
    previousToken: 1,
    staleOutputAttempted: false,
    staleOutputAccepted: false,
  }

  // 1. 他アプリ（vp）が SetEnabled(enabled=true, takeover=takeoverFlag) を送るステップ
  pure def applyRequest(s: BrokerState, takeoverFlag: bool): BrokerState = {
    if (s.phase == "releasing") {
      { ...s, lastError: "pending" }
    } else if (s.assignedClient == "vp") {
      s
    } else if (not(takeoverFlag) and REQUIRE_TAKEOVER_CONFIRM) {
      { ...s, lastError: "conflict" }
    } else {
      if (not(WAIT_FOR_QUIESCE) and not(WAIT_FOR_DRAIN)) {
        val nextTok = if (MONOTONIC_LEASE_TOKEN) s.leaseToken + 1 else s.leaseToken
        {
          ...s,
          phase: "active",
          assignedClient: "vp",
          revision: s.revision + 1,
          leaseSession: "sess_vp",
          leaseToken: nextTok,
          releasingTo: "",
          quiesced: false,
          drained: false,
          lastError: "",
          lastRequestHadTakeover: takeoverFlag,
          previousToken: s.leaseToken,
        }
      } else {
        {
          ...s,
          phase: "releasing",
          assignedClient: "vp",
          revision: s.revision + 1,
          releasingTo: "vp",
          quiesced: false,
          drained: false,
          lastError: "",
          lastRequestHadTakeover: takeoverFlag,
          previousToken: s.leaseToken,
        }
      }
    }
  }

  // 2. 旧オーナーから Quiesced が到着するステップ
  pure def applyQuiesce(s: BrokerState): BrokerState = {
    if (s.phase != "releasing") {
      { ...s, lastError: "stale_lease" }
    } else {
      val qNow = true
      val ready = qNow and (s.drained or not(WAIT_FOR_DRAIN))
      if (ready) {
        val nextTok = if (MONOTONIC_LEASE_TOKEN) s.leaseToken + 1 else s.leaseToken
        {
          ...s,
          phase: "active",
          leaseSession: "sess_vp",
          leaseToken: nextTok,
          releasingTo: "",
          quiesced: qNow,
          lastError: "",
        }
      } else {
        { ...s, quiesced: qNow, lastError: "" }
      }
    }
  }

  // 3. 物理 I/O アダプタから Drained が到着するステップ
  pure def applyDrain(s: BrokerState): BrokerState = {
    if (s.phase != "releasing") {
      { ...s, lastError: "pending" }
    } else if (WAIT_FOR_QUIESCE and not(s.quiesced)) {
      { ...s, lastError: "pending" }
    } else {
      val dNow = true
      val ready = (s.quiesced or not(WAIT_FOR_QUIESCE)) and dNow
      if (ready) {
        val nextTok = if (MONOTONIC_LEASE_TOKEN) s.leaseToken + 1 else s.leaseToken
        {
          ...s,
          phase: "active",
          leaseSession: "sess_vp",
          leaseToken: nextTok,
          releasingTo: "",
          drained: dNow,
          lastError: "",
        }
      } else {
        { ...s, drained: dNow, lastError: "" }
      }
    }
  }

  // 4. 引き継ぎ前の旧 lease token（previousToken）で遅延 SendMidi / Present を試みるステップ
  pure def applyStaleOutput(s: BrokerState): BrokerState = {
    if (s.phase == "active" and s.assignedClient == "vp") {
      {
        ...s,
        staleOutputAttempted: true,
        staleOutputAccepted: (s.leaseToken == s.previousToken),
      }
    } else {
      {
        ...s,
        staleOutputAttempted: true,
        staleOutputAccepted: false,
      }
    }
  }

  action init = all {
    state' = initialState
  }

  // マルチステップ状態遷移: 現在の state から非決定的に次のイベントを選ぶ
  action step = any {
    {
      nondet takeoverFlag = Set(false, true).oneOf()
      state' = applyRequest(state, takeoverFlag)
    },
    state' = applyQuiesce(state),
    state' = applyDrain(state),
    state' = applyStaleOutput(state),
  }

  // 状態変数から直接導出される不変条件
  val noImplicitTakeover =
    (state.assignedClient == "vp") implies state.lastRequestHadTakeover

  val handoffWaitsForQuiesce =
    (state.assignedClient == "vp" and state.phase == "active") implies state.quiesced

  val handoffWaitsForDrain =
    (state.assignedClient == "vp" and state.phase == "active") implies state.drained

  val staleLeaseOutputRejected =
    state.staleOutputAttempted implies not(state.staleOutputAccepted)

  val allInvariants = and {
    noImplicitTakeover,
    handoffWaitsForQuiesce,
    handoffWaitsForDrain,
    staleLeaseOutputRejected,
    state.phase != "active" or state.leaseToken >= 1,
  }

  // 8 個のシナリオ（全 6 モードで各モードの定数に応じた期待振る舞いを検証）
  run conflictWithoutTakeoverTest = init
    .then(all { state' = applyRequest(state, false) })
    .expect(and {
      (state.lastError == "conflict") == REQUIRE_TAKEOVER_CONFIRM,
      noImplicitTakeover == REQUIRE_TAKEOVER_CONFIRM,
    })

  run takeoverEntersReleasingTest = init
    .then(all { state' = applyRequest(state, true) })
    .expect(and {
      (state.phase == "releasing") == (WAIT_FOR_QUIESCE or WAIT_FOR_DRAIN),
      state.assignedClient == "vp",
      state.revision == 2,
    })

  run quiesceOnlyWaitTest = init
    .then(all { state' = applyRequest(state, true) })
    .then(all { state' = applyQuiesce(state) })
    .expect(and {
      (state.phase == "releasing") == WAIT_FOR_DRAIN,
      handoffWaitsForDrain == WAIT_FOR_DRAIN,
    })

  run drainBeforeQuiesceTest = init
    .then(all { state' = applyRequest(state, true) })
    .then(all { state' = applyDrain(state) })
    .expect(and {
      (state.phase == "releasing") == WAIT_FOR_QUIESCE,
      handoffWaitsForQuiesce == WAIT_FOR_QUIESCE,
    })

  run fullHandoffCompletesTest = init
    .then(all { state' = applyRequest(state, true) })
    .then(all { state' = applyQuiesce(state) })
    .then(all { state' = applyDrain(state) })
    .expect(and {
      state.phase == "active",
      state.assignedClient == "vp",
      state.leaseSession == "sess_vp",
      state.releasingTo == "",
      handoffWaitsForQuiesce == (WAIT_FOR_QUIESCE or WAIT_FOR_DRAIN),
      handoffWaitsForDrain == WAIT_FOR_DRAIN,
    })

  run monotonicLeaseTokenTest = init
    .then(all { state' = applyRequest(state, true) })
    .then(all { state' = applyQuiesce(state) })
    .then(all { state' = applyDrain(state) })
    .then(all { state' = applyStaleOutput(state) })
    .expect(and {
      (state.leaseToken == 2) == MONOTONIC_LEASE_TOKEN,
      staleLeaseOutputRejected == MONOTONIC_LEASE_TOKEN,
    })

  run releasingRejectsConcurrentRequestAndStaleOutputTest = init
    .then(all { state' = applyRequest(state, true) })
    .then(all { state' = applyRequest(state, true) })
    .then(all { state' = applyStaleOutput(state) })
    .expect(and {
      not(WAIT_FOR_QUIESCE or WAIT_FOR_DRAIN) or (state.phase == "releasing" and state.leaseToken == 1 and not(state.staleOutputAccepted)),
    })

  run currentDesignSatisfiesAllTest = init
    .then(all { state' = applyRequest(state, true) })
    .then(all { state' = applyQuiesce(state) })
    .then(all { state' = applyDrain(state) })
    .then(all { state' = applyStaleOutput(state) })
    .expect(and {
      allInvariants == (WAIT_FOR_DRAIN and MONOTONIC_LEASE_TOKEN),
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
