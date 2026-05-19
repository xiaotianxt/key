use std::process::Command;

use anyhow::{bail, Context, Result};

pub fn read(op_ref: &str) -> Result<Vec<u8>> {
    let output = Command::new("op")
        .arg("read")
        .arg(op_ref)
        .output()
        .context("failed to launch 1Password CLI `op`")?;

    if !output.status.success() {
        bail!("op read failed; verify the op:// reference and 1Password CLI auth state");
    }

    Ok(output.stdout)
}

pub fn status() -> &'static str {
    match Command::new("op").arg("--version").output() {
        Ok(output) if output.status.success() => "available",
        Ok(_) => "installed-but-failing",
        Err(_) => "missing",
    }
}
