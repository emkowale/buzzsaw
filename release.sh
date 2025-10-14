#!/usr/bin/env bash
set -euo pipefail

# =========================
# Config (edit per project)
# =========================
OWNER="emkowale"
REPO="buzzsaw"
PLUGIN_SLUG="buzzsaw"
MAIN_FILE="${PLUGIN_SLUG}.php"
REMOTE_URL="git@github.com:${OWNER}/${REPO}.git"

# Usage: ./release {major|minor|patch}
BUMP_TYPE="${1:-}"
[[ -z "$BUMP_TYPE" ]] && { echo "Usage: ./release {major|minor|patch}"; exit 1; }

# =========================
# Helpers
# =========================
say() { printf "\033[1;36m%s\033[0m\n" "$*"; }
warn() { printf "\033[1;33m%s\033[0m\n" "$*"; }
err() { printf "\033[1;31m%s\033[0m\n" "$*" >&2; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { err "Missing '$1'"; exit 1; }
}

bump_version() {
  local current vmaj vmin vpatch new
  current="$(grep -Eo 'Version:\s*[0-9]+\.[0-9]+\.[0-9]+' "$MAIN_FILE" | awk '{print $2}')"
  [[ -z "$current" ]] && { err "Could not read Version: from $MAIN_FILE"; exit 1; }
  IFS='.' read -r vmaj vmin vpatch <<<"$current"
  case "$BUMP_TYPE" in
    major) vmaj=$((vmaj+1)); vmin=0; vpatch=0;;
    minor) vmin=$((vmin+1)); vpatch=0;;
    patch) vpatch=$((vpatch+1));;
    *) err "Unknown bump type: $BUMP_TYPE"; exit 1;;
  esac
  new="${vmaj}.${vmin}.${vpatch}"
  # Update header and constant
  sed -i.bak -E "s/(Version:\s*)[0-9]+\.[0-9]+\.[0-9]+/\1${new}/" "$MAIN_FILE"
  sed -i.bak -E "s/(define\('BUZZSAW_VERSION',\s*')[^']+(')/\1${new}\2/" "$MAIN_FILE"
  rm -f "${MAIN_FILE}.bak"
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
    say "Creating GitHub Release with gh CLI"
    gh release delete "$tag" -y >/dev/null 2>&1 || true
    gh release create "$tag" "$zip" -t "${REPO} ${tag}" -n "$(sed -n '1,200p' CHANGELOG.md 2>/dev/null || echo "Release ${tag}")"
  else
    [[ -z "${GITHUB_TOKEN:-}" ]] && { warn "gh not found and GITHUB_TOKEN not set. Skipping Release creation."; return; }
    say "Creating GitHub Release via API"
    UPLOAD_URL=$(curl -fsSL -X POST \
      -H "Authorization: token ${GITHUB_TOKEN}" \
      -H "Accept: application/vnd.github+json" \
      "https://api.github.com/repos/${OWNER}/${REPO}/releases" \
      -d "{\"tag_name\":\"${tag}\",\"name\":\"${REPO} ${tag}\",\"body\":\"$(printf %s "$(sed -n '1,200p' CHANGELOG.md 2>/dev/null || echo "Release ${tag}")" | sed 's/"/\\"/g')\"}" \
      | python3 -c "import sys,json;print(json.loads(sys.stdin.read()).get('upload_url','').split('{')[0])")
    [[ -z "$UPLOAD_URL" ]] && { warn "Release POST may have failed (or already exists). Trying upload anyway."; }
    curl -fsSL -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/zip" \
      --data-binary @"${zip}" "${UPLOAD_URL}?name=$(basename "$zip")" >/dev/null 2>&1 || true
  fi
}

# =========================
# Pre-flight
# =========================
require_cmd git
[[ -f "$MAIN_FILE" ]] || { err "Missing $MAIN_FILE in $(pwd)"; exit 1; }

# Ensure repo
if [[ ! -d .git ]]; then
  say "Initializing git repo (main)"
  git init >/dev/null
  git branch -M main
fi

# Ensure origin
if ! git remote | grep -q '^origin$'; then
  say "Adding origin $REMOTE_URL"
  git remote add origin "$REMOTE_URL"
fi

# Fetch remote info (if exists)
git fetch origin main >/dev/null 2>&1 || true
LOCAL_HASH="$(git rev-parse HEAD 2>/dev/null || echo 'none')"
REMOTE_HASH="$(git rev-parse origin/main 2>/dev/null || echo 'none')"

# Fresh local working copy + remote has commits → force-push path
if [[ "$LOCAL_HASH" == "none" && "$REMOTE_HASH" != "none" ]]; then
  warn "Fresh local folder detected & remote has history → forcing sync."
  git add -A
  git commit -m "init: import working copy" >/dev/null 2>&1 || true
  git push --force origin main
else
  # Try to rebase if remote exists
  if [[ "$REMOTE_HASH" != "none" ]]; then
    say "Syncing with remote (rebase)…"
    # If pull would overwrite untracked files, skip pull and force push local truth
    if ! git diff --quiet || [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
      warn "Untracked/modified files present; using local as source of truth."
      git add -A
      git commit -m "sync: local working copy" >/dev/null 2>&1 || true
      git push --force origin main
    else
      git pull --rebase origin main || { warn "Rebase failed; forcing local state."; git add -A; git commit -m "sync: local working copy" >/dev/null 2>&1 || true; git push --force origin main; }
    fi
  else
    say "No remote main found; will push new main."
    git add -A
    git commit -m "init: import working copy" >/dev/null 2>&1 || true
    git push -u origin main
  fi
fi

# =========================
# Version bump & commit
# =========================
NEW_VER="$(bump_version)"
TAG="v${NEW_VER}"
say "Bumped version → ${NEW_VER}"

# Update CHANGELOG (prepend minimal entry if not present)
DATE_UTC="$(date -u +%F)"
if [[ -f CHANGELOG.md ]]; then
  tmp="$(mktemp)"; {
    echo "# Changelog"; echo
    echo "## [${NEW_VER}] - ${DATE_UTC}"
    echo "- Release ${NEW_VER}."
    echo
    awk 'NR>1{print prev} {prev=$0}' CHANGELOG.md
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
# Tag & push
# =========================
say "Tagging ${TAG}"
git tag -d "${TAG}" >/dev/null 2>&1 || true
git push origin ":refs/tags/${TAG}" >/dev/null 2>&1 || true
git tag -a "${TAG}" -m "Release ${TAG}"
git push origin "${TAG}"

# =========================
# Build ZIP & Release
# =========================
clean_zip_build "${TAG}"
create_release "${TAG}"

say "✅ Done. Pushed main, created ${TAG}, built ZIP and published release."
