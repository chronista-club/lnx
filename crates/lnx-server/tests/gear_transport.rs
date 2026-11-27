// mem_1CfnVkncPrmfdQet3bNSmx — 実 QUIC、実保存領域。実機 MIDI は開かない。
use lnx_protocol::{Broker, PROTOCOL_VERSION, wire::*};
use lnx_server::gear::{runtime::Runtime, service::Service, settings::SettingsStore};
use unison::network::{ProtocolClient, QuicClient, TrustAnchors, channel::UnisonChannel};

async fn connect(service: &Service) -> (ProtocolClient, UnisonChannel) {
    let transport = QuicClient::builder()
        .trust_anchors(TrustAnchors::Custom(vec![
            service.endpoint.certificate_der.clone().into(),
        ]))
        .build()
        .unwrap();
    let client = ProtocolClient::new(transport);
    client
        .connect(&format!("https://localhost:{}", service.endpoint.port))
        .await
        .unwrap();
    let channel = client.open_channel(CHANNEL).await.unwrap();
    (client, channel)
}
fn hello(service: &Service, client: &str) -> Hello {
    Hello {
        protocol_version: PROTOCOL_VERSION,
        client_id: client.into(),
        display_name: client.into(),
        auth_token: service.endpoint.auth_token.clone(),
        native_midi: false,
        initial_enabled_profiles: vec![],
    }
}
async fn start(path: &std::path::Path) -> Service {
    let mut broker = Broker::new("test-epoch");
    broker.add_gear("nano", "nanokontrol", true);
    Service::start(Runtime::new(broker, SettingsStore::new(path)).unwrap())
        .await
        .unwrap()
}
#[tokio::test]
async fn unauthenticated_requests_and_wrong_token_cannot_observe_devices() {
    let dir = tempfile::tempdir().unwrap();
    let service = start(dir.path()).await;
    let (client, channel) = connect(&service).await;
    let reply: Reply = channel
        .request("Snapshot", &serde_json::json!({}))
        .await
        .unwrap();
    assert!(reply.snapshot.is_none());
    assert_eq!(reply.error.unwrap().code, "unauthenticated");
    let mut request = hello(&service, "ladyland");
    request.auth_token = "wrong".into();
    let reply: Reply = channel.request("Hello", &request).await.unwrap();
    assert!(reply.snapshot.is_none());
    assert_eq!(reply.error.unwrap().code, "unauthenticated");
    client.disconnect().await.unwrap();
}
#[tokio::test]
async fn native_clients_wait_for_driver_readiness_and_only_see_their_own_ports() {
    let dir = tempfile::tempdir().unwrap();
    let service = start(dir.path()).await;
    let (a, ca) = connect(&service).await;
    let (b, cb) = connect(&service).await;
    let mut request = hello(&service, "ladyland");
    request.native_midi = true;
    request.initial_enabled_profiles = vec!["nanokontrol".into()];
    let reply: Reply = ca.request("Hello", &request).await.unwrap();
    assert_eq!(
        reply.snapshot.unwrap().gears[0].state.phase,
        lnx_protocol::Phase::Waiting
    );
    {
        let mut runtime = service.runtime.lock().unwrap();
        let lease = runtime.broker.gears["nano"].lease.clone().unwrap();
        runtime.native_bindings.insert(
            "nano".into(),
            lnx_server::gear::runtime::NativeBinding {
                lease,
                ports: NativePorts {
                    inputs: vec!["owned source".into()],
                    outputs: vec![],
                },
            },
        );
    }
    let reply: Reply = ca
        .request("Snapshot", &serde_json::json!({}))
        .await
        .unwrap();
    let view = reply.snapshot.unwrap().gears.remove(0);
    assert_eq!(view.state.phase, lnx_protocol::Phase::Active);
    assert_eq!(view.native_ports.inputs, vec!["owned source"]);
    let reply: Reply = cb.request("Hello", &hello(&service, "vp")).await.unwrap();
    assert!(
        reply.snapshot.unwrap().gears[0]
            .native_ports
            .inputs
            .is_empty()
    );
    a.disconnect().await.unwrap();
    b.disconnect().await.unwrap();
    service.shutdown().await.unwrap();
}
#[tokio::test]
async fn rust_sdk_uses_pinned_endpoint_and_surfaces_protocol_errors() {
    let dir = tempfile::tempdir().unwrap();
    let service = start(dir.path()).await;
    let (client, snapshot) = lnx_client::Client::connect(&service.endpoint, hello(&service, "sdk"))
        .await
        .unwrap();
    assert_eq!(snapshot.server_epoch, service.endpoint.server_epoch);
    assert!(client.snapshot().await.unwrap().sequence > snapshot.sequence);
    let enabled = client
        .set_enabled(&SetEnabled {
            gear_id: "nano".into(),
            enabled: true,
            expected_revision: 0,
            takeover: false,
        })
        .await
        .unwrap();
    assert_eq!(
        enabled.gears[0].state.assignment.client_id.as_deref(),
        Some("sdk")
    );
    let error = client
        .set_enabled(&SetEnabled {
            gear_id: "nano".into(),
            enabled: false,
            expected_revision: 0,
            takeover: false,
        })
        .await
        .unwrap_err();
    assert!(error.to_string().contains("stale_revision"));
    let rejected = client
        .send_midi(&SendMidi {
            gear_id: "nano".into(),
            lease_token: "old".into(),
            port_name: "output".into(),
            bytes: vec![0x90, 60, 100],
        })
        .await
        .unwrap_err();
    assert!(rejected.to_string().contains("stale_lease"));
    let old = enabled.gears[0].state.lease.clone().unwrap();
    let (peer, cp) = connect(&service).await;
    let _: Reply = cp.request("Hello", &hello(&service, "peer")).await.unwrap();
    let _: Reply = cp
        .request(
            "SetEnabled",
            &SetEnabled {
                gear_id: "nano".into(),
                enabled: true,
                expected_revision: 1,
                takeover: true,
            },
        )
        .await
        .unwrap();
    tokio::time::timeout(std::time::Duration::from_secs(2), async {
        loop {
            if let Event::Quiesce { lease_token, .. } = client.recv_event().await.unwrap() {
                assert_eq!(lease_token, old.token);
                break;
            }
        }
    })
    .await
    .unwrap();
    assert_eq!(
        client.snapshot().await.unwrap().gears[0].state.phase,
        lnx_protocol::Phase::Releasing
    );
    assert!(!service.runtime.lock().unwrap().broker.is_quiescent("nano"));
    client
        .quiesced(&Quiesced {
            gear_id: "nano".into(),
            lease_token: old.token,
        })
        .await
        .unwrap();
    assert!(service.runtime.lock().unwrap().broker.is_quiescent("nano"));
    peer.disconnect().await.unwrap();
    client.close().await.unwrap();
    service.shutdown().await.unwrap();
}

#[tokio::test]
async fn output_reply_waits_for_physical_completion_and_rejects_old_lease() {
    let dir = tempfile::tempdir().unwrap();
    let service = start(dir.path()).await;
    let (client, channel) = connect(&service).await;
    let _: Reply = channel
        .request("Hello", &hello(&service, "sender"))
        .await
        .unwrap();
    let reply: Reply = channel
        .request(
            "SetEnabled",
            &SetEnabled {
                gear_id: "nano".into(),
                enabled: true,
                expected_revision: 0,
                takeover: false,
            },
        )
        .await
        .unwrap();
    let lease = reply.snapshot.unwrap().gears[0]
        .state
        .lease
        .clone()
        .unwrap();
    let (sender, receiver) = std::sync::mpsc::sync_channel(8);
    {
        let mut r = service.runtime.lock().unwrap();
        r.native_bindings.insert(
            "nano".into(),
            lnx_server::gear::runtime::NativeBinding {
                lease: lease.clone(),
                ports: NativePorts {
                    inputs: vec![],
                    outputs: vec!["native output".into()],
                },
            },
        );
        r.output_sinks.insert(
            "native output".into(),
            lnx_server::gear::io_fence::OutputSink {
                destination: 123,
                sender,
            },
        );
    }
    let request = SendMidi {
        gear_id: "nano".into(),
        lease_token: lease.token,
        port_name: "native output".into(),
        bytes: vec![0xf0, 0x7d, 1, 0xf7],
    };
    let channel = std::sync::Arc::new(channel);
    let send_channel = channel.clone();
    let send_request = request.clone();
    let reply = tokio::spawn(async move {
        send_channel
            .request::<_, Reply>("SendMidi", &send_request)
            .await
            .unwrap()
    });
    let command = tokio::task::spawn_blocking(move || {
        receiver.recv_timeout(std::time::Duration::from_secs(1))
    })
    .await
    .unwrap()
    .expect("driver receives output");
    assert_eq!(command.bytes, request.bytes);
    assert!(!reply.is_finished());
    command.completion.unwrap().send(Ok(())).unwrap();
    assert!(reply.await.unwrap().error.is_none());
    let stale = SendMidi {
        lease_token: "old".into(),
        ..request
    };
    let reply: Reply = channel.request("SendMidi", &stale).await.unwrap();
    assert_eq!(reply.error.unwrap().code, "stale_lease");
    client.disconnect().await.unwrap();
    service.shutdown().await.unwrap();
}
#[tokio::test]
async fn two_apps_must_confirm_takeover_and_stale_output_is_rejected() {
    let dir = tempfile::tempdir().unwrap();
    let service = start(dir.path()).await;
    let (a, ca) = connect(&service).await;
    let (b, cb) = connect(&service).await;
    for (channel, name) in [(&ca, "ladyland"), (&cb, "vp")] {
        let reply: Reply = channel
            .request("Hello", &hello(&service, name))
            .await
            .unwrap();
        assert!(reply.error.is_none());
    }
    let request = SetEnabled {
        gear_id: "nano".into(),
        enabled: true,
        expected_revision: 0,
        takeover: false,
    };
    let reply: Reply = ca.request("SetEnabled", &request).await.unwrap();
    let old = reply.snapshot.unwrap().gears[0]
        .state
        .lease
        .clone()
        .unwrap();
    let mut request = SetEnabled {
        expected_revision: 1,
        ..request
    };
    let reply: Reply = cb.request("SetEnabled", &request).await.unwrap();
    assert_eq!(reply.error.unwrap().code, "conflict");
    request.takeover = true;
    let reply: Reply = cb.request("SetEnabled", &request).await.unwrap();
    assert_eq!(
        reply.snapshot.unwrap().gears[0].state.phase,
        lnx_protocol::Phase::Releasing
    );
    let event = tokio::time::timeout(std::time::Duration::from_secs(2), async {
        loop {
            let message = ca.recv().await.unwrap();
            let event: Event = serde_json::from_value(message.payload_as_value().unwrap()).unwrap();
            if let Event::Quiesce { lease_token, .. } = event {
                break lease_token;
            }
        }
    })
    .await
    .expect("old owner receives cleanup request");
    assert_eq!(event, old.token);
    let reply: Reply = ca
        .request(
            "Present",
            &Present {
                gear_id: "nano".into(),
                lease_token: old.token.clone(),
                controls: vec![],
            },
        )
        .await
        .unwrap();
    assert_eq!(reply.error.unwrap().code, "stale_lease");
    assert!(
        service
            .runtime
            .lock()
            .unwrap()
            .broker
            .drained("nano")
            .is_err()
    );
    let reply: Reply = ca
        .request(
            "Quiesced",
            &Quiesced {
                gear_id: "nano".into(),
                lease_token: old.token,
            },
        )
        .await
        .unwrap();
    assert!(reply.error.is_none());
    assert_eq!(
        reply.snapshot.unwrap().gears[0].state.phase,
        lnx_protocol::Phase::Releasing
    );
    // 実機 adapter の完了境界をここではテストから明示的に進める。
    service
        .runtime
        .lock()
        .unwrap()
        .broker
        .drained("nano")
        .unwrap();
    let reply: Reply = cb
        .request("Snapshot", &serde_json::json!({}))
        .await
        .unwrap();
    let next = reply.snapshot.unwrap();
    assert_eq!(
        next.gears[0].state.lease.as_ref().unwrap().session_id,
        next.session_id
    );
    a.disconnect().await.unwrap();
    b.disconnect().await.unwrap();
    service.shutdown().await.unwrap();
}

/// サーバーは IPv6 と IPv4 の両方の loopback で待つ。Rust SDK は `localhost` に繋ぐが、
/// club-unison の client は名前解決の最初の候補しか試さないので、IPv6 の無いネットワークでは
/// 127.0.0.1 に向かう。どちらに向かっても届くこと（mem_1CfrJGkydLLAzFP4RnYwLV）。
#[tokio::test]
async fn service_listens_on_both_loopback_families() {
    let dir = tempfile::tempdir().unwrap();
    let service = start(dir.path()).await;
    for host in ["127.0.0.1", "[::1]"] {
        let transport = QuicClient::builder()
            .trust_anchors(TrustAnchors::Custom(vec![
                service.endpoint.certificate_der.clone().into(),
            ]))
            .build()
            .unwrap();
        let client = ProtocolClient::new(transport);
        tokio::time::timeout(
            std::time::Duration::from_secs(5),
            client.connect(&format!("https://{host}:{}", service.endpoint.port)),
        )
        .await
        .unwrap_or_else(|_| panic!("{host}: connect timed out"))
        .unwrap_or_else(|e| panic!("{host}: {e}"));
        let channel = client.open_channel(CHANNEL).await.unwrap();
        drop(channel);
        client.disconnect().await.unwrap();
    }
    service.shutdown().await.unwrap();
}

/// snapshot はサービス自身の版と実行ファイルのパスを持つ（design 05「常駐と配布」）。
/// メニューバーの app が「同梱版が動いているか、別のバイナリか」「.app を更新したが古い版のままか」を
/// 表示するために使う。入れ替えは人の操作なので、ここは事実を載せるだけ。
#[tokio::test]
async fn snapshot_reports_service_version_and_executable() {
    let dir = tempfile::tempdir().unwrap();
    let service = start(dir.path()).await;
    let (client, snapshot) =
        lnx_client::Client::connect(&service.endpoint, hello(&service, "menubar"))
            .await
            .unwrap();
    assert_eq!(snapshot.service.version, env!("CARGO_PKG_VERSION"));
    assert!(
        std::path::Path::new(&snapshot.service.executable).is_absolute(),
        "executable は絶対パス: {}",
        snapshot.service.executable
    );
    client.close().await.unwrap();
    service.shutdown().await.unwrap();
}

/// SetGearSetups / SetEnabled で ROTO の setup 自動切り替え（plan_setup_switches）が発火し、
/// SelectSetup / ApplyGearSetup / Present も SDK から往復できることを検証する。
#[tokio::test]
async fn sdk_roto_setup_rpcs_and_auto_switch_plan_work_over_quic() {
    let dir = tempfile::tempdir().unwrap();
    let mut broker = Broker::new("test-epoch");
    broker.add_gear("roto", "roto", true);
    let service = Service::start(Runtime::new(broker, SettingsStore::new(dir.path())).unwrap())
        .await
        .unwrap();
    let (client, _) = lnx_client::Client::connect(&service.endpoint, hello(&service, "ladyland"))
        .await
        .unwrap();

    // 1. SetGearSetups で ladyland 用の希望 setup=[3, 5] を登録
    let snap = client
        .set_gear_setups(&SetGearSetups {
            gear_id: "roto".into(),
            setups: vec![3, 5],
        })
        .await
        .unwrap();
    assert_eq!(
        snap.gears[0].setup_owners.get("ladyland"),
        Some(&vec![3, 5])
    );

    // 2. SetEnabled で roto を獲得すると、service::dispatch 内の plan_setup_switches() により
    //    configuring == true かつ setup ジョブキューに Select(3) が積まれる
    let snap = client
        .set_enabled(&SetEnabled {
            gear_id: "roto".into(),
            enabled: true,
            expected_revision: 0,
            takeover: false,
        })
        .await
        .unwrap();
    assert!(
        snap.gears[0].configuring,
        "SetEnabled 直後に plan_setup_switches が動いて configuring になること"
    );
    let lease_token = snap.gears[0].state.lease.as_ref().unwrap().token.clone();

    // 3. Present も SDK から往復でき、古い lease は stale_lease、現役 lease は adapter 境界まで到達する
    let stale_present = client
        .present(&Present {
            gear_id: "roto".into(),
            lease_token: "stale-token".into(),
            controls: vec![],
        })
        .await
        .unwrap_err();
    assert!(stale_present.to_string().contains("stale_lease"));
    let active_present = client
        .present(&Present {
            gear_id: "roto".into(),
            lease_token: lease_token.clone(),
            controls: vec![ControlPresentation {
                id: "knob:1".into(),
                name: Some("Cutoff".into()),
                value: Some(64.0),
                color: Some("amber".into()),
            }],
        })
        .await
        .unwrap_err();
    assert!(
        active_present
            .to_string()
            .contains("presentation adapter unavailable")
    );

    // 4. SelectSetup と ApplyGearSetup も RPC として受理され configuring になる
    let snap = client
        .select_setup(&SelectSetup {
            gear_id: "roto".into(),
            lease_token: lease_token.clone(),
            setup: 5,
        })
        .await
        .unwrap();
    assert!(snap.gears[0].configuring);

    let snap = client
        .apply_gear_setup(&ApplyGearSetup {
            gear_id: "roto".into(),
            lease_token,
            setup: 5,
            content: SetupContent {
                name: "LADYLAND".into(),
                knobs: vec![KnobConfig {
                    control: 0,
                    mode: ControlMode::Cc7,
                    channel: 1,
                    param: 74,
                    nrpn_address: 0,
                    min: 0,
                    max: 127,
                    name: "CUTOFF".into(),
                    color: 10,
                    haptics: KnobHaptics::CentreIndent,
                }],
                switches: vec![],
            },
        })
        .await
        .unwrap();
    assert!(snap.gears[0].configuring);
    assert!(
        service.runtime.lock().unwrap().next_setup_job().is_some(),
        "setup_jobs にジョブが積まれていること"
    );

    client.close().await.unwrap();
    service.shutdown().await.unwrap();
}
