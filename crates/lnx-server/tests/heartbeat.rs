//! 心拍 — 常駐の生存証明。seq と起動からの経過ミリ秒
use lnx_server::heartbeat::Heartbeat;
use std::time::Duration;

#[test]
fn 心拍は_seq_と_uptime_ms_を持つ() {
    let hb = Heartbeat {
        seq: 3,
        uptime: Duration::from_millis(1234),
    };
    let v = hb.to_value();
    assert_eq!(v["seq"], 3);
    assert_eq!(v["uptime_ms"], 1234);
}
