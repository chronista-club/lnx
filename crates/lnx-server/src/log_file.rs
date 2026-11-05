//! ログの置き場 — 常駐（SMAppService）の plist は `~` を展開せず、StandardOutPath に家のパスを書けない。
//! `--log-file` の `~/` は自分で展開し、stdout / stderr をそのファイルへ向ける（launchd の StandardOutPath と同じ効き）
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};

/// 先頭の `~/`（と `~` だけ）を家に展開する。家が分からなければそのまま
pub fn expand_home(path: &Path, home: Option<&Path>) -> PathBuf {
    match (path.strip_prefix("~"), home) {
        (Ok(rest), Some(home)) => home.join(rest),
        _ => path.to_path_buf(),
    }
}

/// stdout と stderr を path（追記）へ向ける。println の行も tracing も panic もここに入る。
/// 何かを書く前（tracing を始める前）に呼ぶ
pub fn redirect_stdio(path: &Path) -> Result<()> {
    use std::os::fd::AsRawFd;

    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).with_context(|| format!("{} を作れない", dir.display()))?;
    }
    let file = std::fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)
        .with_context(|| format!("ログ {} を開けない", path.display()))?;
    for target in [libc::STDOUT_FILENO, libc::STDERR_FILENO] {
        // SAFETY: どちらも開いている fd。dup2 は target を file の複製に置き換えるだけ
        if unsafe { libc::dup2(file.as_raw_fd(), target) } == -1 {
            return Err(std::io::Error::last_os_error())
                .with_context(|| format!("出力をログ {} へ向けられない", path.display()));
        }
    }
    Ok(())
}
