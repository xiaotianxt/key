#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-xiaotianxt/key}"
WORKFLOW="${WORKFLOW:-release.yml}"

usage() {
  cat <<'USAGE'
Usage: scripts/release.sh

Verify, commit-ready check, push main, tag v<Cargo.toml version>, and let GitHub
Actions publish the darwin-arm64 release asset.

Environment:
  REPO_SLUG   GitHub repo slug. Default: xiaotianxt/key
  WORKFLOW    Release workflow file/name. Default: release.yml
USAGE
}

log() {
  printf '==> %s\n' "$*"
}

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

package_version() {
  sed -nE 's/^version[[:space:]]*=[[:space:]]*"([^"]+)".*/\1/p' Cargo.toml | head -1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

need_cmd cargo
need_cmd git
need_cmd gh

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty; commit changes before release"

version="$(package_version)"
[[ -n "$version" ]] || die "Cargo.toml version not found"
tag="v${version}"

log "verifying"
cargo fmt --all -- --check
cargo clippy --all-targets -- -D warnings
cargo test
cargo build --release
cargo run --release -- --help >/dev/null

log "pushing main"
git push origin HEAD:main

if git rev-parse -q --verify "refs/tags/${tag}" >/dev/null; then
  log "tag ${tag} already exists locally"
else
  log "creating tag ${tag}"
  git tag -a "$tag" -m "$tag"
fi

if git ls-remote --tags origin "refs/tags/${tag}" | grep -q .; then
  log "tag ${tag} already exists on origin"
else
  log "pushing tag ${tag}"
  git push origin "$tag"
fi

log "watching release workflow"
run_id="$(gh run list --repo "$REPO_SLUG" --workflow "$WORKFLOW" --branch "$tag" --json databaseId --jq '.[0].databaseId')"
[[ -n "$run_id" && "$run_id" != "null" ]] || die "release workflow run not found for ${tag}"
gh run watch "$run_id" --repo "$REPO_SLUG" --exit-status
