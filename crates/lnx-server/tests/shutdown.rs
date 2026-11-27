//! 止め方 — launchd（bootout / kickstart -k）も Ctrl-C も、シグナルで止める。
//! 落ちるのではなく畳んで抜ける（Bonjour の goodbye を出し、幽霊を残さない）
use std::io::{BufRead, BufReader};
use std::process::{Child, Command, Stdio};
use std::sync::mpsc;
use std::time::{Duration, Instant};

/// 空きポートで立て、待ち受けを始めたところまで待つ。待ち受けの行も返す
fn start_server(state_dir: &std::path::Path) -> (Child, String) {
    let mut child = Command::new(env!("CARGO_BIN_EXE_lnx-server"))
        .args(["--addr", "[::1]:0", "--local-addr", "[::1]:0", "--no-mdns"])
        .arg("--state-dir")
        .arg(state_dir)
        .env("RUST_LOG", "info")
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .expect("lnx-server を起動できない");

    let stdout = child.stdout.take().unwrap();
    let (tx, rx) = mpsc::channel();
    std::thread::spawn(move || {
        for line in BufReader::new(stdout).lines().map_while(Result::ok) {
            if line.contains("で待ち受け") {
                let _ = tx.send(line);
            }
        }
    });
    let line = rx
        .recv_timeout(Duration::from_secs(20))
        .expect("待ち受けを始めない");
    (child, line)
}

fn wait_exit(child: &mut Child, limit: Duration) -> std::process::ExitStatus {
    let deadline = Instant::now() + limit;
    loop {
        if let Some(status) = child.try_wait().unwrap() {
            return status;
        }
        if Instant::now() > deadline {
            let _ = child.kill();
            panic!("{limit:?} のうちに止まらない");
        }
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn send(signal: &str, child: &Child) {
    let ok = Command::new("kill")
        .args([signal, &child.id().to_string()])
        .status()
        .unwrap()
        .success();
    assert!(ok, "kill {signal} を送れない");
}

fn temp_state_dir(tag: &str) -> std::path::PathBuf {
    let dir =
        std::env::temp_dir().join(format!("lnx-server-shutdown-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    dir
}

#[test]
fn sigterm_で畳んで正常に抜ける() {
    let dir = temp_state_dir("term");
    let (mut child, _) = start_server(&dir);
    let endpoint_path = dir.join("endpoint.json");
    assert!(
        endpoint_path.exists(),
        "待ち受けログが出た時点で endpoint.json が書かれていること"
    );
    // 実プロセスの gear channel に接続し、maru を含む 11 種すべての PROFILES が登録されていることを確かめる
    let endpoint: lnx_protocol::wire::Endpoint =
        serde_json::from_slice(&std::fs::read(&endpoint_path).unwrap()).unwrap();
    let rt = tokio::runtime::Runtime::new().unwrap();
    rt.block_on(async {
        let (client, snapshot) = lnx_client::Client::connect(
            &endpoint,
            lnx_protocol::wire::Hello {
                protocol_version: lnx_protocol::PROTOCOL_VERSION,
                client_id: "shutdown-test".into(),
                display_name: "Shutdown Test".into(),
                auth_token: endpoint.auth_token.clone(),
                native_midi: false,
                initial_enabled_profiles: vec![],
            },
        )
        .await
        .expect("実プロセスの gear channel に接続できること");
        assert!(
            snapshot.gears.iter().any(|g| g.state.gear_id == "maru"),
            "maru が PROFILES に含まれていること"
        );
        assert!(snapshot.gears.len() >= 11);
        let _ = client.close().await;
    });
    send("-TERM", &child);
    let status = wait_exit(&mut child, Duration::from_secs(5));
    assert!(status.success(), "SIGTERM で正常に抜けない: {status:?}");
    assert!(
        !endpoint_path.exists(),
        "SIGTERM で畳んだあと endpoint.json が消えていること"
    );
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn sigint_でも畳んで正常に抜ける() {
    let dir = temp_state_dir("int");
    let (mut child, _) = start_server(&dir);
    send("-INT", &child);
    let status = wait_exit(&mut child, Duration::from_secs(5));
    assert!(status.success(), "SIGINT で正常に抜けない: {status:?}");
    let _ = std::fs::remove_dir_all(&dir);
}

#[test]
fn 端末でない先へのログに色の制御文字を入れない() {
    // 常駐（launchd）のログはファイルに出る。ESC が混ざると読めない
    let dir = temp_state_dir("ansi");
    let (mut child, line) = start_server(&dir);
    send("-TERM", &child);
    wait_exit(&mut child, Duration::from_secs(5));
    assert!(
        !line.contains('\u{1b}'),
        "ログに ESC が入っている: {line:?}"
    );
    let _ = std::fs::remove_dir_all(&dir);
}
