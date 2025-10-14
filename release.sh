#!/usr/bin/env bash
set -euo pipefail

# Always run from this script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OWNER="emkowale"
REPO="buzzsaw"
PLUGIN_SLUG="buzzsaw"
MAIN_FILE="${PLUGIN_SLUG}.php"
REMOTE_URL="git@github.com:${OWNER}/${REPO}.git"

BUMP_TYPE="${1:-}"
[[ -z "$BUMP_TYPE" ]] && { echo "Usage: ./release {major|minor|patch}"; exit 1; }

say(){ printf "\033[1;36m%s\033[0m\n" "$*"; }
warn(){ printf "\033[1;33m%s\033[0m\n" "$*"; }
err(){ printf "\033[1;31m%s\033[0m\n" "$*" >&2; }

[[ -f "$MAIN_FILE" ]] || { err "Missing $MAIN_FILE in $(pwd)"; exit 1; }

read_version() {
  awk 'BEGIN{IGNORECASE=1}
       /Version:/ && match($0,/Version:[ \t]*([0-9]+\.[0-9]+\.[0-9]+)/,m){print m[1]; exit}' "$MAIN_FILE" | tr -d '\r' || true
}

fallback_constant() {
  awk 'BEGIN{IGNORECASE=1}
       /BUZZSAW_VERSION/ && match($0,/[\"\x27]([0-9]+\.[0-9]+\.[0-9]+)[\"\x27]/,v){print v[1]; exit}' "$MAIN_FILE" | tr -d '\r' || true
}

write_version() {
  local new="$1"
  sed -i 's/\r$//' "$MAIN_FILE" 2>/dev/null || true
  # Update header (first match), case-insensitive
  sed -i -E "0,/^[[:space:][:punct:]]*[Vv]ersion:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+/s//Version: ${new}/" "$MAIN_FILE" || true
  # Update constant
  sed -i -E "s/(define\('BUZZSAW_VERSION',[[:space:]]*')[^']+(')/\1${new}\2/" "$MAIN_FILE" || true
}

bump_version() {
  local current vmaj vmin vpatch new
  current="$(read_version)"; [[ -z "$current" ]] && current="$(fallback_constant)"
  [[ -z "$current" || ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && current="0.0.0"
  IFS='.' read -r vmaj vmin vpatch <<<"$current"
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

# Git bootstrap & sync (always prefer local working copy as truth)
if [[ ! -d .git ]]; then git init >/dev/null; git branch -M main; fi
git remote | grep -q '^origin$' || git remote add origin "$REMOTE_URL"
git fetch origin main >/dev/null 2>&1 || true
if [[ -n "$(git ls-files --others --exclude-standard)" || -n "$(git status --porcelain)" ]]; then
  warn "Using local working copy as source of truth."
  git add -A; git commit -m "sync: local working copy" >/dev/null 2>&1 || true
  git push --force origin main || true
else
  git pull --rebase origin main || true
fi

NEW_VER="$(bump_version)"; TAG="v${NEW_VER}"
DATE_UTC="$(date -u +%F)"
say "Version → ${NEW_VER}"

# Prepend CHANGELOG entry (idempotent)
{ echo "# Changelog"; echo; echo "## [${NEW_VER}] - ${DATE_UTC}"; echo "- Release ${NEW_VER}."; echo; sed '1{/^# Changelog$/d}' CHANGELOG.md 2>/dev/null; } > .CL.tmp && mv .CL.tmp CHANGELOG.md
# Never put a version in README title (prevents drift)
sed -i -E '1s/\s*\(v[0-9.]+\)//' README.md 2>/dev/null || true

git add -A
git commit -m "chore(release): v${NEW_VER}" >/dev/null 2>&1 || true
git push origin main --force

# Tag, archive with proper root, and release
git tag -d "${TAG}" >/dev/null 2>&1 || true
git push origin ":refs/tags/${TAG}" >/dev/null 2>&1 || true
git tag -a "${TAG}" -m "Release ${TAG}"
git push origin "${TAG}"

ZIP="../${PLUGIN_SLUG}-${TAG}.zip"
say "Building ZIP → ${ZIP}"
git archive --format=zip --prefix="${PLUGIN_SLUG}/" "${TAG}" -o "${ZIP}"

if command -v gh >/dev/null 2>&1; then
  gh release delete "${TAG}" -y >/dev/null 2>&1 || true
  gh release create "${TAG}" "${ZIP}" -t "Buzzsaw ${TAG}" -n "Release ${NEW_VER}"
elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
  UPLOAD_URL=$(curl -fsSL -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${OWNER}/${REPO}/releases" \
    -d "{\"tag_name\":\"${TAG}\",\"name\":\"Buzzsaw ${TAG}\",\"body\":\"Release ${NEW_VER}\"}" \
    | python3 -c "import sys,json;print(json.load(sys.stdin).get('upload_url','').split('{')[0])")
  [[ -n "$UPLOAD_URL" ]] && \
  curl -fsSL -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Content-Type: application/zip" \
    --data-binary @"${ZIP}" "${UPLOAD_URL}?name=$(basename "${ZIP}")" >/dev/null 2>&1 || true
else
  warn "No gh and no GITHUB_TOKEN; release created without asset."
fi

say "✅ Done: pushed main, tagged ${TAG}, built ZIP, published release."
