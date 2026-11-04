//! 立ち上げ方 — 常駐（SMAppService）の plist は ~ を展開しないので、ログの置き場と設定の置き場はサーバが決める
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

fn temp_dir(tag: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("lnx-startup-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    dir
}

/// path の中身に needle が現れるまで待つ
fn wait_for(path: &std::path::Path, needle: &str) -> String {
    let deadline = Instant::now() + Duration::from_secs(20);
    loop {
        let text = std::fs::read_to_string(path).unwrap_or_default();
        if text.contains(needle) {
            return text;
        }
        assert!(
            Instant::now() < deadline,
            "{} に {needle:?} が出ない:\n{text}",
            path.display()
        );
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn stop(child: &mut Child) {
    let _ = Command::new("kill")
        .args(["-TERM", &child.id().to_string()])
        .status();
    let deadline = Instant::now() + Duration::from_secs(5);
    while child.try_wait().unwrap().is_none() {
        assert!(Instant::now() < deadline, "止まらない");
        std::thread::sleep(Duration::from_millis(50));
    }
}

fn spawn(args: &[&str], home: &std::path::Path) -> Child {
    Command::new(env!("CARGO_BIN_EXE_lnx-server"))
        .args(["--addr", "[::1]:0", "--local-addr", "[::1]:0", "--no-mdns"])
        .args(args)
        .env("RUST_LOG", "info")
        .env("HOME", home)
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .expect("lnx-server を起動できない")
}

#[test]
fn log_file_に_stdout_と_stderr_を書く() {
    let home = temp_dir("log");
    let state = home.join("state");
    // ~/ は自分で家に展開する（launchd の plist では展開されない）
    let mut child = spawn(
        &[
            "--state-dir",
            state.to_str().unwrap(),
            "--log-file",
            "~/Library/Logs/lnx-server.log",
        ],
        &home,
    );
    let log = home.join("Library/Logs/lnx-server.log");
    wait_for(&log, "で待ち受け");
    stop(&mut child);
    let text = wait_for(&log, "SIGTERM を受けたので止める");
    assert!(
        text.contains("ペアリング URL: lnx://pair"),
        "println の行も入る:\n{text}"
    );
    assert!(!text.contains('\u{1b}'), "色の制御文字を入れない:\n{text}");
    let _ = std::fs::remove_dir_all(&home);
}

#[test]
fn config_が無ければ_state_dir_の設定を読む() {
    let home = temp_dir("config");
    let state = home.join("state");
    std::fs::create_dir_all(&state).unwrap();
    std::fs::write(
        state.join("lnx-server.toml"),
        "name = \"lnx-startup-test\"\n",
    )
    .unwrap();
    let log = home.join("server.log");
    let mut child = spawn(
        &[
            "--state-dir",
            state.to_str().unwrap(),
            "--log-file",
            log.to_str().unwrap(),
        ],
        &home,
    );
    let text = wait_for(&log, "で待ち受け");
    stop(&mut child);
    assert!(
        text.contains("名乗り \"lnx-startup-test\""),
        "state dir の設定を読んでいない:\n{text}"
    );
    let _ = std::fs::remove_dir_all(&home);
}

#[test]
fn 名乗りの指定があれば作る設定もその名乗りにする() {
    // `--name lnx-mac` で一度立てたら、あとで --name 無しで立てても lnx-mac のまま（iPad の pin が外れない）
    let home = temp_dir("name");
    let state = home.join("state");
    let log = home.join("server.log");
    let mut child = spawn(
        &[
            "--state-dir",
            state.to_str().unwrap(),
            "--log-file",
            log.to_str().unwrap(),
            "--name",
            "lnx-given",
        ],
        &home,
    );
    wait_for(&log, "で待ち受け");
    stop(&mut child);
    let saved = std::fs::read_to_string(state.join("lnx-server.toml")).unwrap();
    assert!(
        saved.contains("name = \"lnx-given\""),
        "作った設定:\n{saved}"
    );
    let _ = std::fs::remove_dir_all(&home);
}
