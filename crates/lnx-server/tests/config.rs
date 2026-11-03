//! 設定ファイル（TOML）— 名前と、知っているサーバの一覧
use lnx_server::config::{ServerConfig, ServerEntry};

#[test]
fn toml_から名前と既知サーバを読む() {
    let toml = r#"
        name = "lnx-mac"

        [[servers]]
        id = "ladyland.field"
        name = "Ladyland Field"
        kind = "field"
        host = "mako-mac.local"
        port = 7879
    "#;
    let cfg = ServerConfig::from_toml(toml).unwrap();
    assert_eq!(cfg.name, "lnx-mac");
    assert_eq!(
        cfg.servers,
        vec![ServerEntry {
            id: "ladyland.field".into(),
            name: "Ladyland Field".into(),
            kind: "field".into(),
            host: "mako-mac.local".into(),
            port: 7879,
        }]
    );
}

#[test]
fn 既定は名前_lnx_で既知サーバ無し() {
    let cfg = ServerConfig::default();
    assert_eq!(cfg.name, "lnx");
    assert!(cfg.servers.is_empty());
}

#[test]
fn 壊れた_toml_はエラーになる() {
    assert!(ServerConfig::from_toml("name = ").is_err());
}
