//! サーバの身元 — 一度作った証明書を保存して使い続け、ペアリング用の URL を出す
use lnx_server::identity::{ServerIdentity, pairing_url};

fn tmpdir(tag: &str) -> std::path::PathBuf {
    let dir = std::env::temp_dir().join(format!("lnx-identity-{tag}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    dir
}

#[test]
fn 無ければ作って保存し_次は同じ証明書を読む() {
    let dir = tmpdir("persist");
    let first = ServerIdentity::load_or_create(&dir).unwrap();
    assert!(dir.join("cert.pem").exists());
    assert!(dir.join("key.pem").exists());
    assert!(!first.cert_der().is_empty());

    let second = ServerIdentity::load_or_create(&dir).unwrap();
    assert_eq!(
        first.cert_der(),
        second.cert_der(),
        "起動し直しても同じ証明書"
    );
    std::fs::remove_dir_all(&dir).unwrap();
}

#[cfg(unix)]
#[test]
fn 鍵は本人だけが読める() {
    use std::os::unix::fs::PermissionsExt;
    let dir = tmpdir("perm");
    ServerIdentity::load_or_create(&dir).unwrap();
    let mode = std::fs::metadata(dir.join("key.pem"))
        .unwrap()
        .permissions()
        .mode();
    assert_eq!(mode & 0o777, 0o600);
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn 保存した証明書で_tls_の_cert_source_が組める() {
    let dir = tmpdir("source");
    let id = ServerIdentity::load_or_create(&dir).unwrap();
    let key = id.cert_source().resolve().unwrap();
    assert_eq!(key.cert[0].as_ref(), id.cert_der());
    std::fs::remove_dir_all(&dir).unwrap();
}

#[test]
fn ペアリング_url_は_lnx_pair_v1_の形() {
    let url = pairing_url("lnx-mac", &[0xfb, 0xff, 0x01]);
    // base64url（+ / の代わりに - _）、padding なし
    assert_eq!(url, "lnx://pair?v=1&name=lnx-mac&cert=-_8B");
}

#[test]
fn 名前の空白や記号は_percent_エンコードする() {
    let url = pairing_url("studio mac&1", &[0]);
    assert_eq!(url, "lnx://pair?v=1&name=studio%20mac%261&cert=AA");
}
