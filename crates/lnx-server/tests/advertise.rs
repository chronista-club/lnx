//! Bonjour の広告 — TXT に名乗り（name）を載せる。Bonjour が「lnx-mac (2)」に改名しても、アプリは TXT の name で pin を引く
use lnx_server::advertise::txt_properties;

#[test]
fn txt_に_name_と_version_と_protocol_を載せる() {
    let txt = txt_properties("lnx-mac", "0.1.0");
    assert_eq!(txt.get("name").map(String::as_str), Some("lnx-mac"));
    assert_eq!(txt.get("version").map(String::as_str), Some("0.1.0"));
    assert_eq!(txt.get("protocol").map(String::as_str), Some("unison"));
}
