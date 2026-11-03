//! サーバの身元 — 自己署名の証明書を一度だけ作って保存し、以後はそれを使う。
//!
//! アプリは証明書を pin する（QR ペアリング）。起動のたびに作り直すと pin が外れるので、
//! `<dir>/cert.pem` と `<dir>/key.pem` に置いて使い続ける。消せば次の起動で作り直し、
//! アプリはペアリングし直しになる。
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use base64::Engine;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use unison::network::CertSource;

pub struct ServerIdentity {
    cert_path: PathBuf,
    key_path: PathBuf,
    cert_der: Vec<u8>,
}

impl ServerIdentity {
    /// `dir` に証明書があれば読み、無ければ作って保存する
    pub fn load_or_create(dir: &Path) -> Result<Self> {
        let cert_path = dir.join("cert.pem");
        let key_path = dir.join("key.pem");
        if !(cert_path.exists() && key_path.exists()) {
            create(dir, &cert_path, &key_path)?;
        }
        let pem = std::fs::read(&cert_path)
            .with_context(|| format!("証明書 {} を読めない", cert_path.display()))?;
        let cert = rustls_pemfile::certs(&mut pem.as_slice())
            .next()
            .context("証明書が空")?
            .context("証明書の PEM を読めない")?;
        Ok(Self {
            cert_path,
            key_path,
            cert_der: cert.as_ref().to_vec(),
        })
    }

    /// leaf 証明書の DER（アプリが pin する値）
    pub fn cert_der(&self) -> &[u8] {
        &self.cert_der
    }

    /// TLS の cert source（保存したファイルを読む）
    pub fn cert_source(&self) -> CertSource {
        CertSource::FromFile {
            cert_path: self.cert_path.clone(),
            key_path: self.key_path.clone(),
        }
    }

    pub fn cert_path(&self) -> &Path {
        &self.cert_path
    }
}

fn create(dir: &Path, cert_path: &Path, key_path: &Path) -> Result<()> {
    std::fs::create_dir_all(dir).with_context(|| format!("{} を作れない", dir.display()))?;
    // pin は DER のバイト一致だけを見る（SAN は見ない）。SAN は loopback だけで足りる
    let sans = vec![
        "localhost".to_string(),
        "::1".to_string(),
        "127.0.0.1".to_string(),
    ];
    let generated = rcgen::generate_simple_self_signed(sans).context("自己署名証明書を作れない")?;
    write_private(key_path, generated.signing_key.serialize_pem().as_bytes())?;
    std::fs::write(cert_path, generated.cert.pem())
        .with_context(|| format!("{} に書けない", cert_path.display()))?;
    Ok(())
}

/// 鍵は本人だけが読めるように作る
fn write_private(path: &Path, bytes: &[u8]) -> Result<()> {
    use std::io::Write;
    let mut options = std::fs::OpenOptions::new();
    options.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        options.mode(0o600);
    }
    let mut file = options
        .open(path)
        .with_context(|| format!("{} に書けない", path.display()))?;
    file.write_all(bytes)?;
    Ok(())
}

/// 既定の置き場（macOS なら ~/Library/Application Support/club.chronista.lnx-server）
pub fn default_dir() -> Option<PathBuf> {
    directories::ProjectDirs::from("club", "chronista", "lnx-server")
        .map(|d| d.data_dir().to_path_buf())
}

/// ペアリング用の URL。ios lane と合意した契約:
/// `lnx://pair?v=1&name=<Bonjour のインスタンス名>&cert=<leaf DER の base64url、padding なし>`
pub fn pairing_url(name: &str, cert_der: &[u8]) -> String {
    format!(
        "lnx://pair?v=1&name={}&cert={}",
        percent_encode(name),
        URL_SAFE_NO_PAD.encode(cert_der)
    )
}

/// RFC 3986 の unreserved 以外を %XX に
fn percent_encode(s: &str) -> String {
    let mut out = String::new();
    for b in s.bytes() {
        if b.is_ascii_alphanumeric() || matches!(b, b'-' | b'.' | b'_' | b'~') {
            out.push(b as char);
        } else {
            out.push_str(&format!("%{b:02X}"));
        }
    }
    out
}

/// ターミナルに出す QR（白黒反転しても読めるよう、半角ブロックで縦 2 段を 1 行に）
pub fn render_qr(text: &str) -> Result<String> {
    let code = qrcode::QrCode::new(text.as_bytes()).context("QR を作れない")?;
    Ok(code
        .render::<qrcode::render::unicode::Dense1x2>()
        .dark_color(qrcode::render::unicode::Dense1x2::Light)
        .light_color(qrcode::render::unicode::Dense1x2::Dark)
        .quiet_zone(true)
        .build())
}
