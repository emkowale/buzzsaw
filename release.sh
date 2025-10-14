#!/usr/bin/env bash
set -euo pipefail

OWNER="emkowale"
REPO="buzzsaw"
PLUGIN_SLUG="buzzsaw"
REMOTE_URL="git@github.com:${OWNER}/${REPO}.git"

BUMP_TYPE="${1:-}"
FORCE=false

if [[ -z "$BUMP_TYPE" ]]; then
  echo "Usage: ./release {major|minor|patch} [--force]"
  exit 1
fi

if [[ "${2:-}" == "--force" ]]; then
  FORCE=true
fi

if [[ ! -d .git ]]; then
  git init
  git branch -M main
fi

if ! git remote | grep -q origin; then
  git remote add origin "$REMOTE_URL"
fi

git fetch origin main || true

LOCAL_HASH=$(git rev-parse HEAD 2>/dev/null || echo "none")
REMOTE_HASH=$(git rev-parse origin/main 2>/dev/null || echo "none")

if [[ "$REMOTE_HASH" != "$LOCAL_HASH" ]]; then
  if [[ "$FORCE" == true ]]; then
    git push --force origin main || true
  else
    git pull --rebase origin main || true
  fi
fi

CURRENT=$(grep -Eo 'Version: [0-9]+' "$PLUGIN_SLUG.php" | awk '{print $2}')
IFS='.' read -r MAJ MIN PAT <<< "$CURRENT"

case "$BUMP_TYPE" in
  major) ((MAJ+=1)); MIN=0; PAT=0;;
  minor) ((MIN+=1)); PAT=0;;
  patch) ((PAT+=1));;
  *) echo "Unknown bump type: $BUMP_TYPE"; exit 1;;
esac

NEW_VERSION="${MAJ}.${MIN}.${PAT}"
TAG="v${NEW_VERSION}"

sed -i.bak -E "s/(Version: )[0-9]+\.[0-9]+\.[0-9]+/\1${NEW_VERSION}/" "$PLUGIN_SLUG.php"
sed -i.bak "s/define('BUZZSAW_VERSION', '[0-9.]*')/define('BUZZSAW_VERSION', '${NEW_VERSION}')/" "$PLUGIN_SLUG.php"
rm -f *.bak

git add .
git commit -m "chore(release): v${NEW_VERSION}" || true
git branch -M main

if [[ "$FORCE" == true ]]; then
  git push --force origin main
else
  git push origin main
fi

git tag -d "$TAG" 2>/dev/null || true
git push origin ":refs/tags/$TAG" 2>/dev/null || true

git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"

git archive --format=zip --prefix="${PLUGIN_SLUG}/" "$TAG" -o "../${PLUGIN_SLUG}-${TAG}.zip"
echo "✅ Release complete: $TAG"
