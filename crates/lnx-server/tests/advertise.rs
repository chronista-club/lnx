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
