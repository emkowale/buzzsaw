#!/usr/bin/env bash
set -euo pipefail

# Always operate from this script’s directory (works from SSHFS, cron, etc.)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# =========================
# Config (edit per project)
# =========================
OWNER="emkowale"
REPO="buzzsaw"
PLUGIN_SLUG="buzzsaw"
MAIN_FILE="${PLUGIN_SLUG}.php"
REMOTE_URL="git@github.com:${OWNER}/${REPO}.git"

BUMP_TYPE="${1:-}"
[[ -z "$BUMP_TYPE" ]] && { echo "Usage: ./release {major|minor|patch}"; exit 1; }

say()  { printf "\033[1;36m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m%s\033[0m\n" "$*"; }
err()  { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || { err "Missing '$1'"; exit 1; } }
require_cmd git
[[ -f "$MAIN_FILE" ]] || { err "Missing $MAIN_FILE in $(pwd)"; exit 1; }

# ---------- Version helpers ----------
read_version() {
  grep -Eim1 '^[[:space:][:punct:]]*Version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+' "$MAIN_FILE" \
    | sed -E 's/.*Version:[[:space:]]*([0-9]+\.[0-9]+\.[0-9]+).*/\1/' || true
}

write_version() {
  local new="$1"
  # Update "Version:" header (first match)
  sed -i.bak -E "0,/^[[:space:][:punct:]]*Version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+/s//Version: ${new}/" "$MAIN_FILE" || true
  # Update constant define('BUZZSAW_VERSION', 'x.y.z')
  sed -i.bak -E "s/(define\('BUZZSAW_VERSION',[[:space:]]*')[^']+(')/\1${new}\2/" "$MAIN_FILE" || true
  rm -f "${MAIN_FILE}.bak"
}

bump_version() {
  local current vmaj vmin vpatch new
  current="$(read_version)"
  [[ -z "$current" ]] && { err "Could not read Version from $MAIN_FILE"; exit 1; }
  IFS='.' read -r vmaj vmin vpatch <<< "$current"
  case "$BUMP_TYPE" in
    major) vmaj=$((vmaj+1)); vmin=0; vpatch=0;;
    minor) vmin=$((vmin+1)); vpatch=0;;
    patch) vpatch=$((vpatch+1));;
    *) err "Unknown bump type: $BUMP_TYPE"; exit 1;;
  esac
  new="${vmaj}.${vmin}.${vpatch}"
  write_version "$new"
  printf "%s" "$new"
}

clean_zip_build() {
  local tag="$1" out="../${PLUGIN_SLUG}-${tag}.zip"
  say "Building clean ZIP via git archive → ${out}"
  git archive --format=zip --prefix="${PLUGIN_SLUG}/" "$tag" -o "$out"
  say "ZIP ready: $out"
}

create_release() {
  local tag="$1" zip="../${PLUGIN_SLUG}-${tag}.zip"
  if command -v gh >/dev/null 2>&1; then
    say "Creating GitHub Release with gh"
    gh release delete "$tag" -y >/dev/null 2>&1 || true
    gh release create "$tag" "$zip" -t "${REPO} ${tag}" -n "$(sed -n '1,200p' CHANGELOG.md 2>/dev/null || echo "Release ${tag}")"
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    say "Creating GitHub Release via API"
    UPLOAD_URL=$(curl -fsSL -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${OWNER}/${REPO}/releases" \
      -d "{\"tag_name\":\"${tag}\",\"name\":\"${REPO} ${tag}\",\"body\":\"$(printf %s "$(sed -n '1,200p' CHANGELOG.md 2>/dev/null || echo "Release ${tag}")" | sed 's/\"/\\\"/g')\"}" \
      | python3 - <<'PY'
import sys,json
print(json.load(sys.stdin).get('upload_url','').split('{')[0])
PY
    )
    [[ -n "$UPLOAD_URL" ]] && \
      curl -fsSL -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/zip" \
      --data-binary @"${zip}" "${UPLOAD_URL}?name=$(basename "$zip")" >/dev/null 2>&1 || true
  else
    warn "No gh and no GITHUB_TOKEN; skipping release creation."
  fi
}

# =========================
# Git bootstrap & sync
# =========================
if [[ ! -d .git ]]; then
  say "Initializing git repo (main)"
  git init >/dev/null
  git branch -M main
fi

if ! git remote | grep -q '^origin$'; then
  say "Adding origin $REMOTE_URL"
  git remote add origin "$REMOTE_URL"
fi

git fetch origin main >/dev/null 2>&1 || true
LOCAL_HASH="$(git rev-parse HEAD 2>/dev/null || echo 'none')"
REMOTE_HASH="$(git rev-parse origin/main 2>/dev/null || echo 'none')"

# Fresh local + remote exists → force local as truth (avoids “untracked would be overwritten”)
if [[ "$LOCAL_HASH" == "none" && "$REMOTE_HASH" != "none" ]]; then
  warn "Fresh local folder & remote has history → forcing local sync."
  git add -A
  git commit -m "init: import working copy" >/dev/null 2>&1 || true
  git push --force origin main
else
  # If we have local changes/untracked files, prefer local as truth
  if ! git diff --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
    warn "Untracked/modified files present; using local as source of truth."
    git add -A
    git commit -m "sync: local working copy" >/dev/null 2>&1 || true
    git push --force origin main
  else
    # Try a clean rebase if nothing to lose
    if [[ "$REMOTE_HASH" != "none" ]]; then
      say "Syncing with remote (rebase)…"
      git pull --rebase origin main || { warn "Rebase failed; forcing local state."; git add -A; git commit -m "sync: local working copy" >/dev/null 2>&1 || true; git push --force origin main; }
    else
      say "No remote main found; pushing new main."
      git add -A
      git commit -m "init: import working copy" >/dev/null 2>&1 || true
      git push -u origin main
    fi
  fi
fi

# =========================
# Version bump & changelog
# =========================
NEW_VER="$(bump_version)"
TAG="v${NEW_VER}"
say "Bumped version → ${NEW_VER}"

DATE_UTC="$(date -u +%F)"
if [[ -f CHANGELOG.md ]]; then
  tmp="$(mktemp)"; {
    echo "# Changelog"; echo
    echo "## [${NEW_VER}] - ${DATE_UTC}"
    echo "- Release ${NEW_VER}."
    echo
    sed '1{/^# Changelog$/d}' CHANGELOG.md
  } > "$tmp"
  mv "$tmp" CHANGELOG.md
else
  {
    echo "# Changelog"; echo
    echo "## [${NEW_VER}] - ${DATE_UTC}"
    echo "- Release ${NEW_VER}."
    echo
  } > CHANGELOG.md
fi

git add -A
git commit -m "chore(release): v${NEW_VER}" >/dev/null 2>&1 || true
git push origin main --force

# =========================
# Tag, ZIP, Release
# =========================
say "Tagging ${TAG}"
git tag -d "${TAG}" >/dev/null 2>&1 || true
git push origin ":refs/tags/${TAG}" >/dev/null 2>&1 || true
git tag -a "${TAG}" -m "Release ${TAG}"
git push origin "${TAG}"

clean_zip_build "${TAG}"
create_release "${TAG}"

say "✅ Done. Pushed main, created ${TAG}, built ZIP and (if configured) published release."
