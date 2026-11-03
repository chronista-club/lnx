//! Bonjour 広告 — `_lnx._udp` で名乗り、iPad が LAN 上で LNX を見つけられるようにする
use std::collections::HashMap;

use mdns_sd::{ServiceDaemon, ServiceInfo};
use tracing::info;

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

impl Drop for Advertiser {
    fn drop(&mut self) {
        let _ = self.daemon.unregister(&self.fullname);
        let _ = self.daemon.shutdown();
    }
}
