#!/usr/bin/env bash
set -euo pipefail

REPO_SLUG="${REPO_SLUG:-xiaotianxt/key}"
WORKFLOW="${WORKFLOW:-release.yml}"
WATCH_RELEASE=1
BUMP_KIND="patch"
VERSION_OVERRIDE=""

usage() {
  cat <<'USAGE'
Usage: scripts/release.sh [options]

Create a key release. If the current Cargo version is already tagged on another
commit, bump it with cargo-release first.

Options:
  --bump LEVEL       Bump level when the current version is already tagged on
                     another commit. One of: patch, minor, major. Default: patch.
  --version VERSION  Release this exact x.y.z version, updating Cargo files with
                     cargo-release first.
  --no-watch         Push the tag but do not wait for the release workflow.
  -h, --help         Show this help.

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

local_tag_commit() {
  git rev-parse -q --verify "refs/tags/${1}^{}" 2>/dev/null || true
}

remote_tag_commit() {
  local tag="$1"
  local sha

  sha="$(git ls-remote --tags origin "refs/tags/${tag}^{}" | awk '{print $1}')"
  if [[ -z "$sha" ]]; then
    sha="$(git ls-remote --tags origin "refs/tags/${tag}" | awk '{print $1}')"
  fi

  printf '%s' "$sha"
}

tag_commit() {
  local tag="$1"
  local sha

  sha="$(local_tag_commit "$tag")"
  if [[ -z "$sha" ]]; then
    sha="$(remote_tag_commit "$tag")"
  fi

  printf '%s' "$sha"
}

cargo_release_version() {
  local level_or_version="$1"

  cargo release "$level_or_version" \
    --execute \
    --no-confirm \
    --no-publish \
    --no-tag \
    --no-push
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bump)
      [[ $# -ge 2 ]] || die "--bump requires patch, minor, or major"
      BUMP_KIND="$2"
      case "$BUMP_KIND" in
        patch|minor|major) ;;
        *) die "--bump must be one of: patch, minor, major" ;;
      esac
      shift
      ;;
    --version)
      [[ $# -ge 2 ]] || die "--version requires a version"
      VERSION_OVERRIDE="$2"
      [[ "$VERSION_OVERRIDE" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "--version must be x.y.z"
      shift
      ;;
    --no-watch)
      WATCH_RELEASE=0
      ;;
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
need_cmd cargo-release
need_cmd git
need_cmd gh

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

[[ -z "$(git status --porcelain)" ]] || die "working tree is dirty; commit changes before release"

log "fetching origin/main and tags"
git fetch origin main --tags

head_sha="$(git rev-parse HEAD)"
origin_main_sha="$(git rev-parse origin/main)"
if [[ "$head_sha" != "$origin_main_sha" ]]; then
  if git merge-base --is-ancestor origin/main HEAD; then
    log "current HEAD is ahead of origin/main"
  else
    die "current HEAD is not origin/main and cannot fast-forward it"
  fi
fi

current_version="$(package_version)"
[[ -n "$current_version" ]] || die "Cargo.toml version not found"
current_tag="v${current_version}"
current_tag_sha="$(tag_commit "$current_tag")"

if [[ -n "$VERSION_OVERRIDE" && "$VERSION_OVERRIDE" != "$current_version" ]]; then
  log "bumping Cargo version ${current_version} -> ${VERSION_OVERRIDE} with cargo-release"
  cargo_release_version "$VERSION_OVERRIDE"
elif [[ -n "$current_tag_sha" && "$current_tag_sha" != "$head_sha" ]]; then
  log "current version ${current_version} is already tagged; bumping ${BUMP_KIND} with cargo-release"
  cargo_release_version "$BUMP_KIND"
else
  log "using Cargo version ${current_version}"
fi

[[ -z "$(git status --porcelain -- Cargo.toml Cargo.lock)" ]] || die "cargo-release left uncommitted Cargo version changes"

version="$(package_version)"
[[ -n "$version" ]] || die "Cargo.toml version not found"
tag="v${version}"
tag_sha="$(tag_commit "$tag")"
head_sha="$(git rev-parse HEAD)"
if [[ -n "$tag_sha" && "$tag_sha" != "$head_sha" ]]; then
  die "tag ${tag} points to ${tag_sha}, not HEAD ${head_sha}; choose a different version"
fi

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
if [[ "$WATCH_RELEASE" -eq 0 ]]; then
  log "not waiting for release workflow"
  exit 0
fi
run_id=""
for _ in {1..20}; do
  run_id="$(gh run list --repo "$REPO_SLUG" --workflow "$WORKFLOW" --branch "$tag" --json databaseId --jq '.[0].databaseId')"
  if [[ -n "$run_id" && "$run_id" != "null" ]]; then
    break
  fi
  sleep 3
done
[[ -n "$run_id" && "$run_id" != "null" ]] || die "release workflow run not found for ${tag}"
gh run watch "$run_id" --repo "$REPO_SLUG" --exit-status
