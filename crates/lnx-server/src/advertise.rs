//! Bonjour 広告 — `_lnx._udp` で名乗り、iPad が LAN 上で LNX を見つけられるようにする
use std::collections::HashMap;
use std::sync::mpsc;
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

use mdns_sd::{DaemonEvent, RecvTimeoutError, ServiceDaemon, ServiceInfo};
use tracing::{Level, debug, info, warn};

use crate::SERVICE_TYPE;

/// 生きている間だけ広告する。drop で取り下げる。
/// mdns-sd の daemon は専用のスレッド（mdns-keeper）が持ち、出来事をログに出し、
/// IPv4 の IpDel を受けたら静かになってから作り直す（[`RebuildPlan`]、design 01）
pub struct Advertiser {
    fullname: String,
    commands: mpsc::Sender<Command>,
    keeper: Option<JoinHandle<()>>,
}

enum Command {
    /// いま作り直す（SIGUSR1）
    Rebuild,
    /// goodbye を出して止まる（drop）
    Stop,
}

impl Advertiser {
    pub fn start(instance: &str, port: u16, version: &str) -> anyhow::Result<Self> {
        let host = format!("{instance}.local.");
        let properties = txt_properties(instance, version);
        // ip は空 + addr_auto: 持っているアドレスを mdns-sd が自動で載せる
        let info = ServiceInfo::new(SERVICE_TYPE, instance, &host, "", port, properties)?
            .enable_addr_auto();
        let fullname = info.get_fullname().to_string();
        let daemon = ServiceDaemon::new()?;
        // 出来事は register の前に受け口を作る（最初の名乗りも拾う）
        let events = daemon.monitor()?;
        daemon.register(info.clone())?;
        info!("bonjour: {fullname} を広告（port {port}）");
        let (commands, inbox) = mpsc::channel();
        let held = daemon.clone();
        let keeper = match std::thread::Builder::new()
            .name("mdns-keeper".into())
            .spawn(move || keep(held, events, info, inbox))
        {
            Ok(keeper) => keeper,
            Err(e) => {
                // 取り下げる者がいないまま名乗り続けないよう、ここで畳む
                withdraw(&daemon, &fullname);
                return Err(e.into());
            }
        };
        Ok(Self {
            fullname,
            commands,
            keeper: Some(keeper),
        })
    }

    pub fn fullname(&self) -> &str {
        &self.fullname
    }

    /// いま作り直す（間は待たない）。試験と、メニューからの当座の手当て用
    pub fn rebuild_now(&self) {
        let _ = self.commands.send(Command::Rebuild);
    }
}

/// daemon を持ち続けるスレッド。出来事をログに出し、作り直しの時が来たら作り直し、Stop で畳む
fn keep(
    mut daemon: ServiceDaemon,
    mut events: mdns_sd::Receiver<DaemonEvent>,
    info: ServiceInfo,
    inbox: mpsc::Receiver<Command>,
) {
    let mut plan = RebuildPlan::default();
    loop {
        match events.recv_timeout(KEEP_TICK) {
            Ok(event) => {
                log_event(&event);
                plan.on_event(&event, Instant::now());
            }
            Err(RecvTimeoutError::Timeout) => {}
            // daemon のスレッドが思いがけず止まった。作り直しに回す（すぐ戻る recv で空回りしないよう間を置く）
            Err(RecvTimeoutError::Disconnected) => {
                if plan.lost(Instant::now()) {
                    warn!("mdns: daemon が止まっている。作り直す");
                }
                std::thread::sleep(KEEP_TICK);
            }
        }
        match inbox.try_recv() {
            Ok(Command::Rebuild) => plan.request(),
            Ok(Command::Stop) | Err(mpsc::TryRecvError::Disconnected) => {
                withdraw(&daemon, info.get_fullname());
                return;
            }
            Err(mpsc::TryRecvError::Empty) => {}
        }
        let now = Instant::now();
        if !plan.due(now) {
            continue;
        }
        // 新しい daemon を先に用意する。作れなければ古いまま続ける
        let (fresh, fresh_events) = match fresh_daemon() {
            Ok(fresh) => fresh,
            Err(e) => {
                warn!("mdns: Bonjour を作り直せない（古いまま続ける。あとでもう一度）: {e}");
                plan.failed(now);
                continue;
            }
        };
        // 古いほうを止め（goodbye が出る）、すぐ新しいほうで名乗る
        stop(&daemon);
        daemon = fresh;
        events = fresh_events;
        match announce_again(&daemon, &info, plan.probe_on_rebuild()) {
            Ok(()) => {
                warn!("mdns: Bonjour を作り直した（multicast の参加を張り直した）");
                plan.rebuilt(now);
            }
            Err(e) => {
                warn!("mdns: Bonjour を作り直したが名乗れない（あとでもう一度）: {e}");
                plan.failed(now);
            }
        }
    }
}

/// 作り直しに使う新しい daemon と、その出来事の受け口
fn fresh_daemon() -> anyhow::Result<(ServiceDaemon, mdns_sd::Receiver<DaemonEvent>)> {
    let daemon = ServiceDaemon::new()?;
    match daemon.monitor() {
        Ok(events) => Ok((daemon, events)),
        Err(e) => {
            // 受け口が無いまま持つと出来事が見えない。スレッドを残さないよう止めて捨てる
            stop(&daemon);
            Err(e.into())
        }
    }
}

/// 作り直した daemon で名乗る。一瞬前まで同じ名前を持っていたので、ふだんは probe（約 0.75 秒）を飛ばす。
/// 古い daemon の goodbye は「1 秒後に消す」なので、それより先にこのアナウンスが届けば、LAN のキャッシュから
/// 記録は消えない（試験では goodbye の 2〜3 ms 後に出て、dns-sd -B に Rmv は出なかった。design 01）。
/// ただし一度でも改名していたら probe する（[`RebuildPlan::probe_on_rebuild`]）
fn announce_again(daemon: &ServiceDaemon, info: &ServiceInfo, probe: bool) -> anyhow::Result<()> {
    let mut info = info.clone();
    info.set_requires_probe(probe);
    daemon.register(info)?;
    Ok(())
}

/// daemon を止める（mdns-sd は shutdown で名乗っているものの goodbye を出す）。止まり終えるまで待つ
fn stop(daemon: &ServiceDaemon) {
    if let Ok(done) = daemon.shutdown() {
        let _ = done.recv_timeout(STOP_WAIT);
    }
}

/// 取り下げて止める。goodbye（TTL 0）を出し終えるまで待つ。待たずにプロセスが抜けると送られず、幽霊が残る。
/// mdns-sd 0.21 は goodbye を一度出し、+120ms に再送を予約してから OK を返す。shutdown は予約を捨てるので、
/// 再送が出るまで置いてから止める（Wi-Fi の multicast は落ちることがある）
fn withdraw(daemon: &ServiceDaemon, fullname: &str) {
    if let Ok(done) = daemon.unregister(fullname)
        && done.recv_timeout(STOP_WAIT).is_ok()
    {
        std::thread::sleep(GOODBYE_RESEND_WAIT);
    }
    stop(daemon);
}

/// 作り直すまで静かであってほしい間。mdns-sd の IP check（5 秒）と同じで、一つの NIC の出入りで続けて出る
/// IpDel を一回の作り直しにまとめる
pub const REBUILD_QUIET: Duration = Duration::from_secs(5);

/// 作り直し同士の最小の間。NIC がばたついても作り直しの嵐にしない
pub const REBUILD_MIN_GAP: Duration = Duration::from_secs(30);

/// いつ作り直すか（純粋）。消えた IPv4 で multicast から抜けると、XNU は別の NIC の membership を外し、
/// mdns-sd は気づかない（2026-11-06 の観測）。IPv4 の IpDel を受けたら、[`REBUILD_QUIET`] だけ静かになってから、
/// 前の作り直しから [`REBUILD_MIN_GAP`] 以上空けて作り直す。IPv6 は index で抜けるので対象外
#[derive(Debug, Default)]
pub struct RebuildPlan {
    /// 待っている引き金（IPv4 の IpDel を最後に受けたとき / daemon が止まっていると気づいたとき）
    last_trigger: Option<Instant>,
    /// 前に作り直したとき（できなかったときも含む）
    last_attempt: Option<Instant>,
    requested: bool,
    lost: bool,
    /// 名前がぶつかって改名したことがある（NameChange）
    renamed: bool,
}

impl RebuildPlan {
    pub fn on_event(&mut self, event: &DaemonEvent, now: Instant) {
        match event {
            DaemonEvent::IpDel(ip) if ip.is_ipv4() => self.last_trigger = Some(now),
            DaemonEvent::NameChange(_) => self.renamed = true,
            _ => {}
        }
    }

    /// 作り直しで probe するか。mdns-sd は probe 中の名前しかぶつかりを見ず、改名の結果は daemon ごとに持つ。
    /// 改名したことがあるのに probe を飛ばすと、元の名前で cache-flush 付きに名乗り、LAN にいる同じ名前の相手の
    /// 記録を押しのける。なので一度でも改名したら、このプロセスの間は probe する（そのぶん答えない間が延びる。design 01）
    pub fn probe_on_rebuild(&self) -> bool {
        self.renamed
    }

    /// 手で頼まれた（間は待たない）
    pub fn request(&mut self) {
        self.requested = true;
    }

    /// daemon が止まっている（受け口が閉じた）。初めて気づいたときだけ true（ログを一度だけ出すため）。
    /// 受け口は毎回すぐ閉じたと返すので、引き金の時刻は数え直さない
    pub fn lost(&mut self, now: Instant) -> bool {
        self.last_trigger.get_or_insert(now);
        !std::mem::replace(&mut self.lost, true)
    }

    pub fn due(&self, now: Instant) -> bool {
        if self.requested {
            return true;
        }
        let Some(trigger) = self.last_trigger else {
            return false;
        };
        let quiet = now.saturating_duration_since(trigger) >= REBUILD_QUIET;
        let spaced = self
            .last_attempt
            .is_none_or(|tried| now.saturating_duration_since(tried) >= REBUILD_MIN_GAP);
        quiet && spaced
    }

    pub fn rebuilt(&mut self, now: Instant) {
        self.last_trigger = None;
        self.requested = false;
        self.lost = false;
        self.last_attempt = Some(now);
    }

    /// 作り直せなかった。引き金は残し、[`REBUILD_MIN_GAP`] おいてもう一度（手で頼まれた分も、連打はしない）
    pub fn failed(&mut self, now: Instant) {
        self.requested = false;
        self.last_trigger.get_or_insert(now);
        self.last_attempt = Some(now);
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

/// 出来事を一件、tracing に出す
fn log_event(event: &DaemonEvent) {
    match describe_event(event) {
        Some((Level::WARN, text)) => warn!("{text}"),
        Some((Level::INFO, text)) => info!("{text}"),
        Some((_, text)) => debug!("{text}"),
        None => {}
    }
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
        // goodbye を出して止まるのは keeper の仕事。出し終えるまで待つ（最長でおよそ 2.5 秒）
        let _ = self.commands.send(Command::Stop);
        if let Some(keeper) = self.keeper.take() {
            let _ = keeper.join();
        }
    }
}

/// 取り下げと停止のそれぞれを待つ上限（mdns-sd の daemon は別スレッドで、ふつうは数 ms で返る）
const STOP_WAIT: Duration = Duration::from_secs(1);

/// goodbye の再送（mdns-sd が +120ms に予約する）が出るまで置く間
const GOODBYE_RESEND_WAIT: Duration = Duration::from_millis(200);

/// keeper が出来事を待つ一回の長さ（Stop / Rebuild に気づく遅れの上限）
const KEEP_TICK: Duration = Duration::from_millis(200);
