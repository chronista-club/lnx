//! lnx-server — 起動して待ち受ける（常駐プロセスの本体）
use std::io::IsTerminal;
use std::path::PathBuf;
use std::sync::Arc;

use anyhow::Result;
use clap::Parser;
use tokio::signal::unix::{SignalKind, signal};
use tracing::{info, warn};

use lnx_server::advertise::Advertiser;
use lnx_server::config::{self, ServerConfig};
use lnx_server::identity::{self, ServerIdentity};
use lnx_server::{DEFAULT_LOCAL_ADDR, DEFAULT_PORT, log_file, serve};

#[derive(Parser, Debug)]
#[command(
    name = "lnx-server",
    about = "LNX サーバ — lnx creare が常時つなぐ窓口（Unison / QUIC）"
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
    /// 証明書と鍵の置き場（既定は ~/Library/Application Support/club.chronista.lnx-server）。
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
        .with_target(false)
        // 常駐（launchd）のログはファイルに出る。端末でなければ色の制御文字を入れない
        .with_ansi(std::io::stdout().is_terminal())
        .init();

    // 止める合図は最初に受け口を作る（待ち受けの前に届いても、落ちずに畳む）
    let mut sigterm = signal(SignalKind::terminate())?;
    let mut sigint = signal(SignalKind::interrupt())?;

    // 証明書と設定の置き場（server:run も常駐も同じ既定の置き場）
    let state_dir = cli
        .state_dir
        .clone()
        .or_else(identity::default_dir)
        .ok_or_else(|| anyhow::anyhow!("証明書の置き場を決められない（--state-dir で指定）"))?;

    let mut cfg = match &cli.config {
        Some(path) => ServerConfig::load(path)?,
        None => {
            // 作るときの名乗りは、--name があればそれ（一度 --name lnx-mac で立てたら、あとで外しても lnx-mac のまま）
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

    let port: u16 = cli
        .addr
        .rsplit(':')
        .next()
        .and_then(|p| p.parse().ok())
        .unwrap_or(DEFAULT_PORT);
    let _advertiser = if cli.no_mdns {
        None
    } else {
        match Advertiser::start(&cfg.name, port, serve::VERSION) {
            Ok(a) => Some(a),
            Err(e) => {
                warn!("bonjour を始められない（続行）: {e}");
                None
            }
        }
    };

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
    let _local = Arc::new(local)
        .listener(&cli.local_addr)
        .cert(id.cert_source())
        .spawn()
        .await?;
    info!("手元用（ペアリング）: {}", cli.local_addr);

    let server = serve::build(cfg).await?;
    info!("{} で待ち受け", cli.addr);
    // ここで待つ（常駐の本体）。保存した自己署名証明書で LAN に開く。
    // launchd（bootout / kickstart -k）は SIGTERM、端末の Ctrl-C は SIGINT で止める。
    // どちらも畳んで抜け、Advertiser の drop で Bonjour の goodbye を出す（落ちると幽霊が残る）
    let listen = Arc::new(server)
        .listener(&cli.addr)
        .cert(id.cert_source())
        .run();
    tokio::select! {
        result = listen => result?,
        _ = sigterm.recv() => info!("SIGTERM を受けたので止める"),
        _ = sigint.recv() => info!("SIGINT を受けたので止める"),
    }
    Ok(())
}

/// この機械の名前（既定の名乗りの元）。macOS は LocalHostName（Bonjour の名前で、ネットワークで変わらない）、
/// 取れなければ hostname
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
