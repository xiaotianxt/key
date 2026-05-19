#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

cargo build --release
mkdir -p "${HOME}/.local/bin"
cp target/release/key "${HOME}/.local/bin/key"
printf 'installed: %s\n' "${HOME}/.local/bin/key"
