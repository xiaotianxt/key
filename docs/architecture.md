# Architecture

`key` is a thin command-line boundary around macOS Keychain generic password
items.

## Data Model

A secret is addressed by two strings:

```text
service account
```

Those map directly to the Keychain generic-password `service` and `account`
attributes. Both must be non-empty because macOS Keychain APIs reject empty
identifiers.

## Secret Flow

`key set` reads secret bytes from stdin and strips one trailing newline or CRLF.
This supports common shell usage such as `pbpaste | key set ...` while keeping
secret values out of process arguments.

`key get` writes the stored bytes directly to stdout and does not append a
newline. This keeps command substitution predictable:

```bash
API_TOKEN="$(key get service account)" command
```

All status and error output goes to stderr unless stdout is the command's data
contract.

## 1Password Import

`key import-op` accepts only `op://...` references. It executes:

```bash
op read <op-ref>
```

and stores stdout directly into Keychain after the same one-newline normalization
used by `set`. It does not print the secret or write it to disk.

## Failure Behavior

Missing Keychain entries are handled explicitly:

- `check` prints `missing` and exits with code 1.
- `get` and `delete` return an error.

Other Keychain failures are surfaced without retry loops. macOS may require user
approval for Keychain access, and that prompt is intentionally left to the OS.

## Dependencies

The implementation depends directly on `security-framework` instead of a broader
cross-platform keyring abstraction. The product is macOS-specific, so the direct
dependency keeps build time and transitive surface smaller.
