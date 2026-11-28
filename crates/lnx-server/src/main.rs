//! lnx-server — 起動して待ち受ける（常駐 Signal Hub + Router の本体）
use std::io::IsTerminal;
use std::path::PathBuf;
use std::sync::{
    Arc,
    atomic::{AtomicBool, Ordering},
};

use anyhow::Result;
use clap::Parser;
use tokio::signal::unix::{SignalKind, signal};
use tracing::{info, warn};

use lnx_protocol::Broker;
use lnx_server::advertise::Advertiser;
use lnx_server::config::{self, ServerConfig};
use lnx_server::gear::{
    inventory::PROFILES,
    runtime::Runtime,
    service::Service as GearService,
    settings::{RuntimeLock, SettingsStore, atomic_write},
};
use lnx_server::identity::{self, ServerIdentity};
use lnx_server::{DEFAULT_LOCAL_ADDR, DEFAULT_PORT, log_file, serve};

#[derive(Parser, Debug)]
#[command(
    name = "lnx-server",
    about = "lnx サーバ — Signal Hub + Router（Unison / QUIC、Gear 管理）"
)]
struct Cli {
    /// 待ち受けアドレス（UDP / QUIC）
    #[arg(long, env = "LNX_SERVER_ADDR", default_value_t = format!("[::]:{DEFAULT_PORT}"))]
    addr: String,
    /// 設定ファイル（TOML）。無ければ証明書の置き場の lnx-server.toml を読む
    /// （それも無ければ、名乗り lnx-<ホスト名>・既知サーバ無しで作って保存する）
    #[arg(long, env = "LNX_SERVER_CONFIG")]
    config: Option<PathBuf>,
    /// 名乗りを上書き
    #[arg(long)]
    name: Option<String>,
    /// Bonjour で名乗らない
    #[arg(long)]
    no_mdns: bool,
    /// 証明書と設定・endpoint.json の置き場（既定は ~/Library/Application Support/tech.anycreative.lnx-server）。
    /// 消すと次の起動で作り直し、アプリはペアリングし直しになる
    #[arg(long, env = "LNX_SERVER_STATE")]
    state_dir: Option<PathBuf>,
    /// ターミナルにもペアリング用の QR を出す（ふだんは Mac 版 lnx creare が窓に出す。URL の一行は常に出す）
    #[arg(long)]
    qr: bool,
    /// 手元用の待ち受け（ループバックだけ）。Mac 版 lnx creare がここでペアリング URL を取る
    #[arg(long, env = "LNX_SERVER_LOCAL_ADDR", default_value = DEFAULT_LOCAL_ADDR)]
    local_addr: String,
    /// ログを書くファイル（追記）。stdout / stderr をここへ向ける。先頭の ~/ は家に展開する
    /// （常駐の SMAppService の plist は ~ を展開しないので、置き場をここで渡す）
    #[arg(long, env = "LNX_SERVER_LOG")]
    log_file: Option<PathBuf>,
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    // 何かを書く前に出力を向ける（色の判定も、最初の行もファイル側になる）
    if let Some(path) = &cli.log_file {
        let home = std::env::var_os("HOME").map(PathBuf::from);
        log_file::redirect_stdio(&log_file::expand_home(path, home.as_deref()))?;
    }

    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        // 常駐（launchd）のログはファイルに出る。端末でなければ色の制御文字を入れない
        .with_ansi(std::io::stdout().is_terminal())
        .init();

    // 止める合図は最初に受け口を作る（待ち受けの前に届いても、落ちずに畳む）
    let mut sigterm = signal(SignalKind::terminate())?;
    let mut sigint = signal(SignalKind::interrupt())?;
    // SIGUSR1 は Bonjour の作り直し（試験と、名乗りに答えなくなったときの当座の手当て。design 01）
    let mut sigusr1 = signal(SignalKind::user_defined1())?;

    // 証明書と設定の置き場（server:run も常駐も同じ既定の置き場）
    let state_dir = cli
        .state_dir
        .clone()
        .or_else(identity::default_dir)
        .ok_or_else(|| anyhow::anyhow!("証明書の置き場を決められない（--state-dir で指定）"))?;

    // 同一 state_dir の単一起動を保証する（endpoint.json や settings.json の競合を防ぐ）
    let _runtime_lock = RuntimeLock::acquire(&state_dir)?;

    let mut cfg = match &cli.config {
        Some(path) => ServerConfig::load(path)?,
        None => {
            let default = || {
                cli.name
                    .clone()
                    .unwrap_or_else(|| config::default_name(local_host_name().as_deref()))
            };
            let (cfg, created) = ServerConfig::load_or_create(&state_dir, default)?;
            let path = state_dir.join(config::CONFIG_FILE);
            if created {
                info!(
                    "設定を作った: {}（名乗り \"{}\"。iPad はこの名前で pin を引くので変えない）",
                    path.display(),
                    cfg.name
                );
            } else {
                info!("設定: {}", path.display());
            }
            cfg
        }
    };
    if let Some(name) = cli.name {
        cfg.name = name;
    }
    info!(
        "lnx-server {}: 名乗り \"{}\"、既知サーバ {} 件",
        serve::VERSION,
        cfg.name,
        cfg.servers.len()
    );

    // 身元: 一度作った自己署名証明書を使い続ける（アプリはこれを pin する）
    let id = ServerIdentity::load_or_create(&state_dir)?;
    info!("証明書: {}", id.cert_path().display());
    let url = identity::pairing_url(&cfg.name, id.cert_der());
    if cli.qr {
        println!(
            "\nlnx creare でこの QR を読むとペアリングする:\n{}",
            identity::render_qr(&url)?
        );
    }
    println!("ペアリング URL: {url}\n");

    // 手元用: ループバックにだけ bind し、ペアリング URL を返す（Mac 版が QR を出す）
    serve::loopback_only(&cli.local_addr)?;
    let local = serve::build_local(&cfg.name, &id).await?;
    let local_listening = Arc::new(local)
        .listener(&cli.local_addr)
        .cert(id.cert_source())
        .spawn()
        .await?;
    info!("手元用（ペアリング）: {}", cli.local_addr);

    // 本体: 保存した自己署名証明書で LAN に開く（spawn は bind を済ませてから返る）
    let name = cfg.name.clone();
    let server = serve::build(cfg).await?;
    let listening = Arc::new(server)
        .listener(&cli.addr)
        .cert(id.cert_source())
        .spawn()
        .await?;
    let bound = listening.local_addr();

    // Gear Runtime（どのアプリがどの Gear を使うか）を立ち上げ、state_dir に endpoint.json を書く。
    // 「で待ち受け」を出す前に完了させることで、待ち受けログを見た側は即 endpoint.json を読める
    lnx_server::gear::trace::refresh(&state_dir);
    let mut broker = Broker::new(uuid::Uuid::new_v4().to_string());
    for (profile_id, gear_name) in PROFILES {
        broker.add_gear(profile_id, profile_id, false);
        broker.gears.get_mut(*profile_id).expect("registered").name = (*gear_name).into();
    }
    let gear_runtime = Runtime::new(broker, SettingsStore::new(&state_dir))?;
    let gear_service = GearService::start(gear_runtime).await?;
    atomic_write(
        &state_dir,
        "endpoint.json",
        &serde_json::to_vec_pretty(&gear_service.endpoint)?,
    )?;
    info!(
        "Gear Hub（loopback）: 127.0.0.1:{} / [::1]:{}",
        gear_service.endpoint.port, gear_service.endpoint.port
    );

    let running = Arc::new(AtomicBool::new(true));
    let worker_running = running.clone();
    let shared = gear_service.runtime.clone();
    let trace_dir = state_dir.clone();
    #[cfg(target_os = "macos")]
    let setup_worker = {
        // 最初の CoreMIDI 呼び出しより前に通知用 run loop スレッドを起こす
        lnx_server::gear::native::start_notify_thread();
        let setups = gear_service.runtime.clone();
        let setup_running = running.clone();
        let backup_dir = state_dir.join("roto-backup");
        Some(
            std::thread::Builder::new()
                .name("roto-setup".into())
                .spawn(move || {
                    while setup_running.load(Ordering::Acquire) {
                        let (job, taken) = {
                            let mut r = setups.lock().expect("runtime mutex poisoned");
                            r.plan_setup_switches();
                            let job = r.next_setup_job();
                            // 誰かの席（画面の再ロードで経由しない index）
                            let taken: Vec<u8> = job
                                .as_ref()
                                .map(|j| {
                                    r.setup_owners(&j.gear_id)
                                        .into_values()
                                        .flatten()
                                        .collect()
                                })
                                .unwrap_or_default();
                            (job, taken)
                        };
                        if let Some(job) = job {
                            use lnx_server::gear::runtime::SetupAction;
                            let result = match &job.action {
                                SetupAction::Select => {
                                    lnx_server::gear::roto_admin::select_setup(job.setup)
                                }
                                SetupAction::Apply(desired) => {
                                    lnx_server::gear::roto_admin::apply_setup(
                                        job.setup,
                                        desired,
                                        &taken,
                                        &backup_dir,
                                    )
                                    .map(|a| {
                                        let reload = match a.reloaded_via {
                                            Some(via) => {
                                                format!(", screen reloaded via setup {via}")
                                            }
                                            None => String::new(),
                                        };
                                        info!(
                                            "{}: setup {} written: {} op(s), port open {} ms, {} requests{}, backup {}",
                                            job.gear_id,
                                            job.setup,
                                            a.ops,
                                            a.port_open_ms,
                                            a.requests,
                                            reload,
                                            a.backup.display()
                                        );
                                    })
                                }
                            }
                            .map_err(|e| e.to_string());
                            setups
                                .lock()
                                .expect("runtime mutex poisoned")
                                .finish_setup_job(&job, result);
                        } else {
                            std::thread::sleep(std::time::Duration::from_millis(50));
                        }
                    }
                })?,
        )
    };
    #[cfg(not(target_os = "macos"))]
    let setup_worker: Option<std::thread::JoinHandle<()>> = None;

    let worker = std::thread::spawn(move || {
        #[cfg(target_os = "macos")]
        {
            let mut native = lnx_server::gear::native::NativeRuntime::new(shared);
            let mut ticks: u32 = 0;
            while worker_running.load(Ordering::Acquire) {
                native.poll();
                ticks = ticks.wrapping_add(1);
                if ticks.is_multiple_of(20) {
                    lnx_server::gear::trace::refresh(&trace_dir);
                }
                std::thread::sleep(std::time::Duration::from_millis(50));
            }
        }
        #[cfg(not(target_os = "macos"))]
        {
            let _ = (worker_running, shared, trace_dir);
        }
    });

    info!("{bound} で待ち受け");

    // 名乗りはすべての待ち受けを確保してから
    let advertiser = if cli.no_mdns {
        None
    } else {
        match Advertiser::start(&name, bound.port(), serve::VERSION) {
            Ok(a) => Some(a),
            Err(e) => {
                warn!("bonjour を始められない（続行）: {e}");
                None
            }
        }
    };

    // 常駐の本体
    let mut watch = tokio::time::interval(LISTEN_WATCH);
    let signal = loop {
        tokio::select! {
            _ = sigterm.recv() => break Some("SIGTERM"),
            _ = sigint.recv() => break Some("SIGINT"),
            _ = sigusr1.recv() => match &advertiser {
                Some(advertiser) => {
                    info!("SIGUSR1 を受けたので Bonjour を作り直す");
                    advertiser.rebuild_now();
                }
                None => info!("SIGUSR1 を受けたが、Bonjour で名乗っていない（--no-mdns）"),
            },
            _ = watch.tick() => if listening.is_finished() { break None },
        }
    };

    if let Some(signal) = signal {
        info!("{signal} を受けたので止める");
    }

    // 先に endpoint.json を消して新規接続を止め、Gear RPC を閉じてから worker / setup_worker の完了を待つ
    let _ = std::fs::remove_file(state_dir.join("endpoint.json"));
    let _ = gear_service.shutdown().await;
    running.store(false, Ordering::Release);
    let _ = tokio::task::spawn_blocking(move || {
        let _ = worker.join();
        if let Some(setup_worker) = setup_worker {
            let _ = setup_worker.join();
        }
    })
    .await;
    let _ = tokio::time::timeout(SHUTDOWN_WAIT, local_listening.shutdown()).await;

    match signal {
        Some(_) => match tokio::time::timeout(SHUTDOWN_WAIT, listening.shutdown()).await {
            Ok(Ok(())) => {}
            Ok(Err(e)) => warn!("待ち受けを畳むときのエラー: {e}"),
            Err(_) => warn!("待ち受けを {SHUTDOWN_WAIT:?} で畳めない（そのまま抜ける）"),
        },
        None => {
            let result = listening.shutdown().await;
            anyhow::bail!(
                "待ち受けが思いがけず終わった（{result:?}）。立て直しは launchd に任せる"
            );
        }
    }
    Ok(())
}

/// 待ち受けのタスクが終わっていないかを見る間（ServerHandle は終わりを待つ口を持たない）
const LISTEN_WATCH: std::time::Duration = std::time::Duration::from_secs(1);

/// 止める合図のあと、待ち受けを畳むのを待つ上限（launchd の止める待ちより十分短く）
const SHUTDOWN_WAIT: std::time::Duration = std::time::Duration::from_secs(2);

/// この機械の名前（既定の名乗りの元）
fn local_host_name() -> Option<String> {
    #[cfg(target_os = "macos")]
    if let Ok(out) = std::process::Command::new("scutil")
        .args(["--get", "LocalHostName"])
        .output()
        && out.status.success()
    {
        let name = String::from_utf8_lossy(&out.stdout).trim().to_string();
        if !name.is_empty() {
            return Some(name);
        }
    }
    let mut buf = [0u8; 256];
    // SAFETY: buf の長さを渡し、gethostname は NUL 終端で書く
    if unsafe { libc::gethostname(buf.as_mut_ptr().cast(), buf.len()) } != 0 {
        return None;
    }
    let end = buf.iter().position(|&b| b == 0).unwrap_or(buf.len());
    let name = String::from_utf8_lossy(&buf[..end]).trim().to_string();
    (!name.is_empty()).then_some(name)
}
