# key

`key` is a small macOS Keychain-backed secret CLI for local tools, shell scripts,
and coding agents.

It stores generic Keychain password items addressed by:

```text
<service> <account>
```

Secrets are never accepted as command-line arguments. `key set` reads from
stdin, and `key import-op` reads a scoped `op://` reference through the
1Password CLI.

## Install

From source:

```bash
git clone https://github.com/xiaotianxt/key.git
cd key
make install-local
```

`make install-local` installs `key` to `~/.local/bin/key`.

## Usage

Store a secret from stdin:

```bash
printf '%s' "$MINERU_API_TOKEN" | key set codex.mineru credential
```

Read a secret for command substitution:

```bash
MINERU_API_TOKEN="$(key get codex.mineru credential)" ocr-doc file.pdf --engine mineru-api --allow-cloud
```

Check whether a secret exists:

```bash
key check codex.mineru credential
```

Delete a secret:

```bash
key delete codex.mineru credential
```

Import a secret from 1Password without printing it:

```bash
key import-op codex.mineru credential 'op://Private/MinerU API/credential'
```

Run diagnostics:

```bash
key doctor
key doctor --roundtrip
```

`key doctor --roundtrip` writes, reads, and deletes a temporary Keychain item.
macOS may ask for Keychain access approval.

## Command Contract

- `key get` writes only the secret bytes to stdout, with no trailing newline.
- `key set`, `key delete`, and `key import-op` write status messages to stderr.
- `key check` writes `present` or `missing` to stdout and exits nonzero when
  missing.
- Secrets are not printed by diagnostics, errors, docs, or release scripts.

## Scope

`key` is intentionally narrow:

- macOS Keychain generic password items only.
- No cloud sync.
- No password-manager UI.
- No secret values in argv.

Use 1Password for vault management. Use `key` for local-only API keys that
scripts and agents need to read on this Mac.
