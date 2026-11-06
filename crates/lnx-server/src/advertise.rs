//! Bonjour 広告 — `_lnx._udp` で名乗り、iPad が LAN 上で LNX を見つけられるようにする
use std::collections::HashMap;
use std::time::Duration;

use mdns_sd::{DaemonEvent, ServiceDaemon, ServiceInfo};
use tracing::{Level, debug, info, warn};

use crate::SERVICE_TYPE;

/// 生きている間だけ広告する。drop で取り下げる
pub struct Advertiser {
    daemon: ServiceDaemon,
    fullname: String,
}

impl Advertiser {
    pub fn start(instance: &str, port: u16, version: &str) -> anyhow::Result<Self> {
        let daemon = ServiceDaemon::new()?;
        let host = format!("{instance}.local.");
        let properties = txt_properties(instance, version);
        // ip は空 + addr_auto: 持っているアドレスを mdns-sd が自動で載せる
        let info = ServiceInfo::new(SERVICE_TYPE, instance, &host, "", port, properties)?
            .enable_addr_auto();
        let fullname = info.get_fullname().to_string();
        // 出来事は register の前に受け口を作る（最初の名乗りも拾う）
        log_events(daemon.monitor()?)?;
        daemon.register(info)?;
        info!("bonjour: {fullname} を広告（port {port}）");
        Ok(Self { daemon, fullname })
    }

    pub fn fullname(&self) -> &str {
        &self.fullname
    }
}

/// TXT の中身。`name` は名乗り（= QR の name）。Bonjour のインスタンス名は同じ名前が LAN に二つあると
/// 「lnx-mac (2)」のように改名されるので、アプリは pin の鍵にこちらを使う
pub fn txt_properties(name: &str, version: &str) -> HashMap<String, String> {
    HashMap::from([
        ("name".to_string(), name.to_string()),
        ("version".to_string(), version.to_string()),
        ("protocol".to_string(), "unison".to_string()),
    ])
}

/// mdns-sd の出来事を、専用のスレッドで tracing に出し続ける。daemon が止まって受信が切れたら抜ける。
/// mdns-sd は monitor へ try_send で送るので、取りこぼさないよう受け続ける
fn log_events(events: mdns_sd::Receiver<DaemonEvent>) -> anyhow::Result<()> {
    std::thread::Builder::new()
        .name("mdns-events".into())
        .spawn(move || {
            while let Ok(event) = events.recv() {
                match describe_event(&event) {
                    Some((Level::WARN, text)) => warn!("{text}"),
                    Some((Level::INFO, text)) => info!("{text}"),
                    Some((_, text)) => debug!("{text}"),
                    None => {}
                }
            }
        })?;
    Ok(())
}

/// mdns-sd の出来事 →（レベル、ログの文）。LAN 側で答えなくなったとき、ログだけで
/// (a) ローカルネットワークの許可（出来事が無いまま黙る）/ (b) XNU の巻き添え（直前に IPv4 の IpDel）/
/// (ii) 改名（NameChange）を見分けるため（design 01「事故のときログで何を見るか」）。
/// 問い合わせのたびに出る Respond と、知らない出来事は出さない
pub fn describe_event(event: &DaemonEvent) -> Option<(Level, String)> {
    let family = |ip: &std::net::IpAddr| if ip.is_ipv4() { "IPv4" } else { "IPv6" };
    match event {
        DaemonEvent::IpAdd(ip) => Some((
            Level::INFO,
            format!("mdns: アドレスが増えた {ip}（{}）", family(ip)),
        )),
        // 消えた IPv4 で multicast から抜けると、XNU は別の NIC の membership を外すことがある（2026-11-06 の観測）
        DaemonEvent::IpDel(ip) if ip.is_ipv4() => Some((
            Level::WARN,
            format!(
                "mdns: アドレスが消えた {ip}（IPv4）。この後どこかの NIC で名乗りに答えなくなったら、XNU の巻き添えを疑う"
            ),
        )),
        DaemonEvent::IpDel(ip) => Some((
            Level::INFO,
            format!("mdns: アドレスが消えた {ip}（{}）", family(ip)),
        )),
        DaemonEvent::NameChange(change) => Some((
            Level::WARN,
            format!(
                "mdns: 名前がぶつかって改名した {} → {}（{}、{}）",
                change.original, change.new_name, change.rr_type, change.intf_name
            ),
        )),
        DaemonEvent::Error(e) => Some((Level::WARN, format!("mdns: {e}"))),
        DaemonEvent::Announce(name, detail) => {
            Some((Level::INFO, format!("mdns: 名乗った {name}（{detail}）")))
        }
        _ => None,
    }
}

impl Drop for Advertiser {
    fn drop(&mut self) {
        // goodbye（TTL 0）を出し終えるまで待つ。待たずにプロセスが抜けると送られず、幽霊が残る。
        // mdns-sd 0.21 は goodbye を一度出し、+120ms に再送を予約してから OK を返す。shutdown は予約を捨てるので、
        // 再送が出るまで置いてから止める（Wi-Fi の multicast は落ちることがある）
        if let Ok(done) = self.daemon.unregister(&self.fullname)
            && done.recv_timeout(STOP_WAIT).is_ok()
        {
            std::thread::sleep(GOODBYE_RESEND_WAIT);
        }
        if let Ok(done) = self.daemon.shutdown() {
            let _ = done.recv_timeout(STOP_WAIT);
        }
    }
}

/// 取り下げと停止のそれぞれを待つ上限（mdns-sd の daemon は別スレッドで、ふつうは数 ms で返る）
const STOP_WAIT: Duration = Duration::from_secs(1);

/// goodbye の再送（mdns-sd が +120ms に予約する）が出るまで置く間
const GOODBYE_RESEND_WAIT: Duration = Duration::from_millis(200);
