//! Bonjour の広告 — TXT に名乗り（name）を載せる。Bonjour が「lnx-mac (2)」に改名しても、アプリは TXT の name で pin を引く
use lnx_server::advertise::txt_properties;

#[test]
fn txt_に_name_と_version_と_protocol_を載せる() {
    let txt = txt_properties("lnx-mac", "0.1.0");
    assert_eq!(txt.get("name").map(String::as_str), Some("lnx-mac"));
    assert_eq!(txt.get("version").map(String::as_str), Some("0.1.0"));
    assert_eq!(txt.get("protocol").map(String::as_str), Some("unison"));
}

// mdns-sd の出来事をログに出す（G）。LAN 側で答えなくなったとき、ログだけで
// (a) ローカルネットワークの許可 / (b) XNU の巻き添え / (ii) 改名 を見分けられるように（design 01）
mod events {
    use std::net::IpAddr;

    use lnx_server::advertise::describe_event;
    use mdns_sd::{DaemonEvent, DnsNameChange, Error, RRType};
    use tracing::Level;

    fn ip(s: &str) -> IpAddr {
        s.parse().unwrap()
    }

    #[test]
    fn アドレスが増えたら_info() {
        let (level, text) = describe_event(&DaemonEvent::IpAdd(ip("192.168.68.117"))).unwrap();
        assert_eq!(level, Level::INFO);
        assert!(
            text.contains("192.168.68.117") && text.contains("IPv4"),
            "{text}"
        );
    }

    #[test]
    fn ipv4_のアドレスが消えたら_warn() {
        // 消えた IPv4 で multicast から抜けると、XNU は別の NIC の membership を外すことがある（2026-11-06 の観測）
        let (level, text) = describe_event(&DaemonEvent::IpDel(ip("192.168.234.1"))).unwrap();
        assert_eq!(level, Level::WARN);
        assert!(
            text.contains("192.168.234.1") && text.contains("IPv4"),
            "{text}"
        );
    }

    #[test]
    fn ipv6_のアドレスが消えたら_info() {
        let (level, text) = describe_event(&DaemonEvent::IpDel(ip("fe80::1"))).unwrap();
        assert_eq!(level, Level::INFO);
        assert!(text.contains("fe80::1") && text.contains("IPv6"), "{text}");
    }

    #[test]
    fn 改名したら_warn_で元と新と_nic_を出す() {
        let change = DnsNameChange {
            original: "lnx-mac.local.".into(),
            new_name: "lnx-mac-2.local.".into(),
            rr_type: RRType::A,
            intf_name: "en0".into(),
        };
        let (level, text) = describe_event(&DaemonEvent::NameChange(change)).unwrap();
        assert_eq!(level, Level::WARN);
        for part in ["lnx-mac.local.", "lnx-mac-2.local.", "en0"] {
            assert!(text.contains(part), "{part} が無い: {text}");
        }
    }

    #[test]
    fn エラーは_warn() {
        let (level, text) = describe_event(&DaemonEvent::Error(Error::Msg("boom".into()))).unwrap();
        assert_eq!(level, Level::WARN);
        assert!(text.contains("boom"), "{text}");
    }

    #[test]
    fn 名乗ったら_info() {
        let event =
            DaemonEvent::Announce("lnx-mac._lnx._udp.local.".into(), "[192.168.68.117]".into());
        let (level, text) = describe_event(&event).unwrap();
        assert_eq!(level, Level::INFO);
        assert!(text.contains("lnx-mac._lnx._udp.local."), "{text}");
    }

    #[test]
    fn 応答は出さない() {
        // 問い合わせのたびに出て多すぎる
        assert!(describe_event(&DaemonEvent::Respond("en0".into())).is_none());
    }
}

// 作り直し（A）。消えた IPv4 で multicast から抜けると XNU は別の NIC の membership を外し、mdns-sd は気づかない。
// IPv4 の IpDel を受けたら、静かになってから ServiceDaemon を作り直して membership を張り直す（design 01）
mod rebuild {
    use std::net::IpAddr;
    use std::time::{Duration, Instant};

    use lnx_server::advertise::{REBUILD_MIN_GAP, REBUILD_QUIET, RebuildPlan};
    use mdns_sd::{DaemonEvent, DnsNameChange, RRType};

    fn del(s: &str) -> DaemonEvent {
        DaemonEvent::IpDel(s.parse::<IpAddr>().unwrap())
    }

    #[test]
    fn 間は_ip_check_と同じ_5_秒で_作り直し同士は_30_秒空ける() {
        assert_eq!(REBUILD_QUIET, Duration::from_secs(5));
        assert_eq!(REBUILD_MIN_GAP, Duration::from_secs(30));
    }

    #[test]
    fn ipv4_の_ipdel_だけが引き金() {
        let t0 = Instant::now();
        let later = t0 + REBUILD_QUIET * 2;
        for event in [
            del("fe80::1"),
            DaemonEvent::IpAdd("192.168.234.1".parse().unwrap()),
            DaemonEvent::Announce("x".into(), "y".into()),
        ] {
            let mut plan = RebuildPlan::default();
            plan.on_event(&event, t0);
            assert!(!plan.due(later), "{event:?} で作り直した");
        }
        let mut plan = RebuildPlan::default();
        plan.on_event(&del("192.168.234.1"), t0);
        assert!(plan.due(later));
    }

    #[test]
    fn 静かになるまで待つ() {
        let t0 = Instant::now();
        let mut plan = RebuildPlan::default();
        plan.on_event(&del("192.168.234.1"), t0);
        assert!(!plan.due(t0 + REBUILD_QUIET - Duration::from_millis(1)));
        // 続けて来たら、最後の一つから数え直す（一つの NIC の出入りで出る IpDel を一回にまとめる）
        plan.on_event(&del("192.168.68.117"), t0 + Duration::from_secs(3));
        assert!(!plan.due(t0 + REBUILD_QUIET));
        assert!(plan.due(t0 + Duration::from_secs(3) + REBUILD_QUIET));
    }

    #[test]
    fn 作り直したら次の引き金まで作り直さない() {
        let t0 = Instant::now();
        let mut plan = RebuildPlan::default();
        plan.on_event(&del("192.168.234.1"), t0);
        let done = t0 + REBUILD_QUIET;
        plan.rebuilt(done);
        assert!(!plan.due(done + REBUILD_MIN_GAP * 2));
    }

    #[test]
    fn 作り直し同士は_30_秒空ける() {
        // NIC がばたついても作り直しの嵐にしない
        let t0 = Instant::now();
        let mut plan = RebuildPlan::default();
        plan.on_event(&del("192.168.234.1"), t0);
        let first = t0 + REBUILD_QUIET;
        plan.rebuilt(first);
        plan.on_event(&del("192.168.234.1"), first + Duration::from_secs(1));
        assert!(!plan.due(first + Duration::from_secs(1) + REBUILD_QUIET));
        assert!(plan.due(first + REBUILD_MIN_GAP));
    }

    #[test]
    fn 手で頼まれたらすぐ作り直す() {
        // SIGUSR1（試験と、メニューからの当座の手当て）。間は待たない
        let t0 = Instant::now();
        let mut plan = RebuildPlan::default();
        plan.request();
        assert!(plan.due(t0));
    }

    #[test]
    fn 作り直せなかったら_30_秒おいてもう一度() {
        // 引き金からでも手で頼まれてからでも、失敗したら諦めず、間を空けて試し直す（連打はしない）
        let t0 = Instant::now();
        let mut by_trigger = RebuildPlan::default();
        by_trigger.on_event(&del("192.168.234.1"), t0);
        let mut by_hand = RebuildPlan::default();
        by_hand.request();
        for mut plan in [by_trigger, by_hand] {
            let tried = t0 + REBUILD_QUIET;
            plan.failed(tried);
            assert!(!plan.due(tried));
            assert!(!plan.due(tried + REBUILD_MIN_GAP - Duration::from_millis(1)));
            assert!(plan.due(tried + REBUILD_MIN_GAP));
        }
    }

    #[test]
    fn daemon_が止まっていたら静かな間をおいて作り直す() {
        // 止まった daemon の受け口は毎回すぐ Disconnected を返す。そのたびに数え直すと、いつまでも作り直さない
        let t0 = Instant::now();
        let mut plan = RebuildPlan::default();
        assert!(plan.lost(t0), "初めて気づいたとき");
        assert!(
            !plan.lost(t0 + Duration::from_secs(2)),
            "二度目からは気づき済み"
        );
        assert!(!plan.due(t0 + REBUILD_QUIET - Duration::from_millis(1)));
        assert!(plan.due(t0 + REBUILD_QUIET));
    }

    #[test]
    fn daemon_が止まっていても作り直し同士は_30_秒空ける() {
        let t0 = Instant::now();
        let mut plan = RebuildPlan::default();
        plan.failed(t0);
        plan.lost(t0 + Duration::from_secs(1));
        assert!(!plan.due(t0 + Duration::from_secs(1) + REBUILD_QUIET));
        assert!(plan.due(t0 + REBUILD_MIN_GAP));
    }

    #[test]
    fn 改名したことがあれば_作り直しでも_probe_する() {
        // mdns-sd は probe 中の名前しかぶつかりを見ず、改名の結果は daemon ごとに持つ。probe を飛ばすと元の名前に戻り、
        // LAN にいる同じ名前の相手の記録を cache-flush で押しのける（Moody Blues の指摘）
        let t0 = Instant::now();
        let mut plan = RebuildPlan::default();
        assert!(
            !plan.probe_on_rebuild(),
            "ぶつかっていなければ飛ばす（記録を途切れさせない）"
        );
        let change = DnsNameChange {
            original: "lnx-mac._lnx._udp.local.".into(),
            new_name: "lnx-mac (2)._lnx._udp.local.".into(),
            rr_type: RRType::SRV,
            intf_name: "en0".into(),
        };
        plan.on_event(&DaemonEvent::NameChange(change), t0);
        assert!(plan.probe_on_rebuild());
        assert!(
            !plan.due(t0 + REBUILD_MIN_GAP),
            "改名は作り直しの引き金ではない"
        );
        plan.request();
        plan.rebuilt(t0);
        assert!(
            plan.probe_on_rebuild(),
            "作り直しても覚えている（相手はまだ LAN にいるかもしれない）"
        );
    }
}
