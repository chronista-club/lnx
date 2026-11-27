//! ログ出力用の文字列整形ヘルパ（純粋）。
pub fn printable(s: &str) -> String {
    s.chars()
        .flat_map(|c| {
            let escaped: Vec<char> = if c.is_control() {
                c.escape_default().collect()
            } else {
                vec![c]
            };
            escaped
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;
    use std::sync::{Arc, Mutex};

    #[derive(Clone, Default)]
    struct SharedBuf(Arc<Mutex<Vec<u8>>>);

    impl Write for SharedBuf {
        fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
            self.0.lock().unwrap().extend_from_slice(buf);
            Ok(buf.len())
        }
        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    #[test]
    fn printable_escapes_control_characters_and_keeps_utf8() {
        assert_eq!(printable("vp\n\x1b[31m"), "vp\\n\\u{1b}[31m");
        assert_eq!(printable("dev→app"), "dev→app");
    }

    /// Mac 版 lnx creare の GearLogLines.swift が読む本番フォーマット契約（target 付き・ANSI なし）
    #[test]
    fn log_and_trace_format_contract_includes_target_and_structured_fields() {
        let buf = SharedBuf::default();
        let writer = buf.clone();
        let subscriber = tracing_subscriber::fmt()
            .with_env_filter("info")
            .with_ansi(false)
            .with_writer(move || writer.clone())
            .finish();
        tracing::subscriber::with_default(subscriber, || {
            tracing::info!("roto: lease granted to vp");
            crate::gear::trace::marker(true);
            crate::gear::trace::port_line(
                "dev→app",
                "lpd8",
                "vp",
                "LPD8 mk2",
                "FWD",
                &[0xb7, 0x4f, 0x1f],
            );
            crate::gear::trace::send_line(
                "roto",
                "vp",
                "SendMidi",
                "SENT",
                &[0xf0, 0x7d, 0x01, 0xf7],
            );
            crate::gear::trace::overflow("keystage", "ladyland");
            crate::gear::trace::bridge_open(
                "lpd8",
                "vp",
                "boot:1",
                &["Lnx/vp/boot:1/1 | LPD8 mk2".into()],
                &["Lnx/vp/boot:1/2 | LPD8 mk2".into()],
            );
            crate::gear::trace::bridge_close("lpd8", "boot:1");
            crate::gear::trace::marker(false);
        });
        let output = String::from_utf8(buf.0.lock().unwrap().clone()).unwrap();
        let lines: Vec<&str> = output.lines().collect();
        assert_eq!(lines.len(), 8);
        assert!(
            lines[0].contains("INFO lnx_server::gear::logging::tests: roto: lease granted to vp")
        );
        assert!(lines[1].contains("INFO lnx_trace: ---- MIDI trace on ----"));
        assert!(lines[2].contains(
            r#"INFO lnx_trace: FWD | B7 4F 1F dir="dev→app" device=lpd8 app=vp port=LPD8 mk2 kind="cc""#
        ));
        assert!(lines[3].contains(
            r#"INFO lnx_trace: SENT | F0 7D 01 F7 dir="svc→dev" device=roto app=vp via="SendMidi" kind="sysex""#
        ));
        assert!(lines[4].contains(
            r#"INFO lnx_trace: OVERFLOW queue full; lease stopped dir="app→svc" device=keystage app=ladyland"#
        ));
        assert!(
            lines[5].contains("INFO lnx_trace: OPEN bridge | in [\"Lnx/vp/boot:1/1 | LPD8 mk2\"]")
        );
        assert!(lines[6].contains("INFO lnx_trace: CLOSE bridge device=lpd8 token=boot:1"));
        assert!(lines[7].contains("INFO lnx_trace: ---- MIDI trace off ----"));
    }
}
