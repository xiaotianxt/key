use std::io::{self, Read, Write};
use std::process::ExitCode;

use anyhow::{bail, Context, Result};
use clap::{Args, Parser, Subcommand};

use crate::keychain::{Keychain, Target};

#[derive(Debug, Parser)]
#[command(
    name = "key",
    version,
    about = "Store and retrieve local secrets in macOS Keychain",
    long_about = "A small macOS Keychain-backed secret CLI for shell scripts and agents.\n\nSecrets are never accepted as command-line arguments. Use stdin for `set`, or a scoped 1Password reference for `import-op`."
)]
struct Cli {
    #[command(subcommand)]
    command: Command,
}

#[derive(Debug, Subcommand)]
enum Command {
    /// Print a secret to stdout without a trailing newline.
    Get(TargetArgs),
    /// Store a secret from stdin.
    Set(TargetArgs),
    /// Delete a secret.
    Delete(TargetArgs),
    /// Check whether a secret exists.
    Check(TargetArgs),
    /// Read a 1Password op:// reference and store it in Keychain.
    ImportOp(ImportOpArgs),
    /// Print local diagnostics.
    Doctor(DoctorArgs),
}

#[derive(Debug, Args)]
struct TargetArgs {
    /// Keychain generic-password service name.
    service: String,
    /// Keychain generic-password account name.
    account: String,
}

#[derive(Debug, Args)]
struct ImportOpArgs {
    /// Keychain generic-password service name.
    service: String,
    /// Keychain generic-password account name.
    account: String,
    /// 1Password secret reference, such as op://Private/Service/credential.
    op_ref: String,
}

#[derive(Debug, Args)]
struct DoctorArgs {
    /// Perform a real Keychain write/read/delete roundtrip with a temporary item.
    #[arg(long)]
    roundtrip: bool,
}

pub fn run() -> Result<ExitCode> {
    let cli = Cli::parse();
    let keychain = Keychain::new();

    match cli.command {
        Command::Get(args) => get(&keychain, args),
        Command::Set(args) => set(&keychain, args),
        Command::Delete(args) => delete(&keychain, args),
        Command::Check(args) => check(&keychain, args),
        Command::ImportOp(args) => import_op(&keychain, args),
        Command::Doctor(args) => doctor(&keychain, args),
    }
}

fn get(keychain: &Keychain, args: TargetArgs) -> Result<ExitCode> {
    let target = target(args)?;
    let secret = keychain
        .get(&target)
        .with_context(|| format!("failed to read {}", target.display()))?;
    io::stdout()
        .write_all(&secret)
        .context("failed to write secret to stdout")?;
    Ok(ExitCode::SUCCESS)
}

fn set(keychain: &Keychain, args: TargetArgs) -> Result<ExitCode> {
    let target = target(args)?;
    let secret = read_secret_from_stdin()?;
    keychain
        .set(&target, &secret)
        .with_context(|| format!("failed to store {}", target.display()))?;
    eprintln!("stored {}", target.display());
    Ok(ExitCode::SUCCESS)
}

fn delete(keychain: &Keychain, args: TargetArgs) -> Result<ExitCode> {
    let target = target(args)?;
    keychain
        .delete(&target)
        .with_context(|| format!("failed to delete {}", target.display()))?;
    eprintln!("deleted {}", target.display());
    Ok(ExitCode::SUCCESS)
}

fn check(keychain: &Keychain, args: TargetArgs) -> Result<ExitCode> {
    let target = target(args)?;
    if keychain.exists(&target)? {
        println!("present");
        Ok(ExitCode::SUCCESS)
    } else {
        println!("missing");
        Ok(ExitCode::FAILURE)
    }
}

fn import_op(keychain: &Keychain, args: ImportOpArgs) -> Result<ExitCode> {
    if !args.op_ref.starts_with("op://") {
        bail!("op-ref must start with op://");
    }
    let target = Target::new(args.service, args.account)?;
    let mut secret = crate::op::read(&args.op_ref)?;
    normalize_secret(&mut secret);
    if secret.is_empty() {
        bail!("refusing to store an empty secret from op");
    }
    keychain
        .set(&target, &secret)
        .with_context(|| format!("failed to store {}", target.display()))?;
    eprintln!("stored {} from 1Password reference", target.display());
    Ok(ExitCode::SUCCESS)
}

fn doctor(keychain: &Keychain, args: DoctorArgs) -> Result<ExitCode> {
    println!("platform: {}", std::env::consts::OS);
    println!("op: {}", crate::op::status());
    if args.roundtrip {
        let target = Target::new(
            "dev.xiaotianxt.key.doctor".to_string(),
            format!("probe-{}", std::process::id()),
        )?;
        let secret = b"key-doctor";
        keychain.set(&target, secret)?;
        let stored = keychain.get(&target)?;
        if stored != secret {
            let _ = keychain.delete(&target);
            bail!("Keychain roundtrip returned unexpected bytes");
        }
        keychain.delete(&target)?;
        println!("keychain-roundtrip: ok");
    } else {
        println!("keychain-roundtrip: skipped");
    }
    Ok(ExitCode::SUCCESS)
}

fn target(args: TargetArgs) -> Result<Target> {
    Target::new(args.service, args.account)
}

fn read_secret_from_stdin() -> Result<Vec<u8>> {
    let mut secret = Vec::new();
    io::stdin()
        .read_to_end(&mut secret)
        .context("failed to read secret from stdin")?;
    normalize_secret(&mut secret);
    if secret.is_empty() {
        bail!("refusing to store an empty secret");
    }
    Ok(secret)
}

fn normalize_secret(secret: &mut Vec<u8>) {
    if secret.ends_with(b"\n") {
        secret.pop();
        if secret.ends_with(b"\r") {
            secret.pop();
        }
    }
}

#[cfg(test)]
mod tests {
    use super::normalize_secret;

    #[test]
    fn trims_one_lf() {
        let mut value = b"secret\n".to_vec();
        normalize_secret(&mut value);
        assert_eq!(value, b"secret");
    }

    #[test]
    fn trims_one_crlf() {
        let mut value = b"secret\r\n".to_vec();
        normalize_secret(&mut value);
        assert_eq!(value, b"secret");
    }

    #[test]
    fn preserves_internal_and_extra_newlines() {
        let mut value = b"line1\nline2\n\n".to_vec();
        normalize_secret(&mut value);
        assert_eq!(value, b"line1\nline2\n");
    }
}
