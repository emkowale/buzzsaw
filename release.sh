#!/usr/bin/env bash
set -euo pipefail

# === CHANGE ONLY THESE FOR A NEW PLUGIN ======================================
OWNER="emkowale"
REPO="buzzsaw"
PLUGIN_SLUG="buzzsaw"
MAIN_FILE="buzzsaw.php"
# ============================================================================

REMOTE_URL="git@github.com:${OWNER}/${REPO}.git"

C0=$'\033[0m'; C1=$'\033[1;36m'; C2=$'\033[1;32m'; C3=$'\033[1;33m'; C4=$'\033[1;31m'
step(){ printf "${C1}🔷 %s${C0}\n" "$*"; }
ok(){   printf "${C2}✅ %s${C0}\n" "$*"; }
warn(){ printf "${C3}⚠ %s${C0}\n" "$*"; }
die(){  printf "${C4}❌ %s${C0}\n" "$*"; exit 1; }
trap 'printf "${C4}❌ Failed at line %s${C0}\n" "$LINENO"' ERR

BUMP="${1:-patch}"; [[ "$BUMP" =~ ^(major|minor|patch)$ ]] || die "Usage: ./release.sh {major|minor|patch}"
command -v git >/dev/null || die "git not found"; command -v php >/dev/null || die "php not found"; command -v zip >/dev/null || die "zip not found"

# Locate repo root
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; cd "$ROOT"
[[ -d ".git" ]] || { [[ -d "../.git" ]] && cd .. || true; }

# --- AUTO INIT IF NEEDED ------------------------------------------------------
if [[ ! -d ".git" ]]; then
  step "Initializing new git repo"
  git init
  git add .
  git commit -m "chore: initial import" >/dev/null 2>&1 || true
  git branch -M main
  git remote add origin "$REMOTE_URL" || git remote set-url origin "$REMOTE_URL"
  ( git push -u origin main >/dev/null 2>&1 && ok "Pushed initial main" ) || warn "Initial push skipped (may be empty/no remote)"
fi

# Detect paths
if [[ -f "${PLUGIN_SLUG}/${MAIN_FILE}" ]]; then SRC_DIR="${PLUGIN_SLUG}"; MAIN_PATH="${PLUGIN_SLUG}/${MAIN_FILE}"
elif [[ -f "${MAIN_FILE}" ]]; then SRC_DIR="."; MAIN_PATH="${MAIN_FILE}"
else die "Cannot find ${MAIN_FILE}"; fi

# Git prep
step "Prepare git"
git rebase --abort >/dev/null 2>&1 || true; git merge --abort >/dev/null 2>&1 || true; git reset --merge >/dev/null 2>&1 || true
git show-ref --verify --quiet refs/heads/main || git branch main >/dev/null 2>&1 || true
git switch -C main >/dev/null
git remote set-url origin "$REMOTE_URL" >/dev/null 2>&1 || true
git rev-parse --abbrev-ref --symbolic-full-name @{u} >/dev/null 2>&1 || git branch --set-upstream-to=origin/main main >/dev/null 2>&1 || true
git fetch origin main --tags >/dev/null 2>&1 || true
git merge -s ours --no-edit origin/main >/dev/null 2>&1 || true
ok "Git ready"

# Read current version
step "Read version"
readver=$(cat <<'PHP'
$path=$argv[1]; $src=@file_get_contents($path)?:''; $v=[];
if(preg_match_all('/(?mi)^\s*(?:\*\s*)?Version\s*:\s*([0-9]+\.[0-9]+\.[0-9]+)/',$src,$m)) $v=array_merge($v,$m[1]);
if(preg_match_all("/define\\(\\s*'([A-Z0-9_]+_VERSION)'\\s*,\\s*'([0-9]+\\.[0-9]+\\.[0-9]+)'\\s*\\)\\s*;/",$src,$m)) foreach($m[2] as $x)$v[]=$x;
echo $v?end(usort($v,'version_compare')?:$v):'0.0.0';
PHP
)
BASE="$(php -r "$readver" "$MAIN_PATH")"; [[ -n "$BASE" ]] || BASE="0.0.0"
latest="$(git tag | sed -n 's/^v\([0-9]\+\.[0-9]\+\.[0-9]\+\)$/\1/p' | sort -V | tail -n1 || true)"
ver_ge(){ printf '%s\n%s\n' "$1" "$2" | sort -V -r | head -n1 | grep -qx "$1"; }
[[ -n "$latest" && $(ver_ge "$latest" "$BASE" && echo 1 || echo 0) -eq 1 ]] && BASE="$latest"
IFS=. read -r MA MI PA <<<"$BASE"; case "$BUMP" in major) ((MA++)); MI=0; PA=0;; minor) ((MI++)); PA=0;; patch) ((PA++)); esac
NEXT="${MA}.${MI}.${PA}"; while git rev-parse -q --verify "refs/tags/v$NEXT" >/dev/null 2>&1; do ((PA++)); NEXT="${MA}.${MI}.${PA}"; done
ok "Next: v${NEXT}"

# Bump in main file (header Version + *_VERSION define)
step "Bump ${MAIN_PATH}"
fix=$(cat <<'PHP'
$path=$argv[1]; $ver=$argv[2]; $slug=$argv[3];
$src=file_get_contents($path); $src=preg_replace("/\r\n?/", "\n", $src);
$lines=explode("\n",$src); $s=-1;$e=-1; for($i=0;$i<min(400,count($lines));$i++){ if(preg_match("/^\s*\/\*/",$lines[$i])){$s=$i;break;} }
if($s>=0){ for($j=$s;$j<min($s+120,count($lines));$j++){ if(preg_match("/\*\//",$lines[$j])){$e=$j;break;} } }
if($s<0||$e<0){ array_splice($lines,0,0,["/*"," * Version: $ver"," */"]); }
else{ for($k=$s;$k<=$e;$k++){ if(preg_match("/^\s*(?:\*\s*)?Version\s*:/i",$lines[$k]))$lines[$k]=null; }
      $t=[]; foreach($lines as $ln){ if($ln!==null)$t[]=$ln; } $lines=$t; array_splice($lines,$s+1,0," * Version: $ver"); }
$src=implode("\n",$lines);
if(preg_match("/^\\s*define\\(\\s*'([A-Z0-9_]+_VERSION)'\\s*,\\s*'[^']*'\\s*\\)\\s*;/m",$src,$m))
  $src=preg_replace("/^\\s*define\\(\\s*'".$m[1]."'\\s*,\\s*'[^']*'\\s*\\)\\s*;/m","define('".$m[1]."','$ver');",$src,1);
else{
  $const=strtoupper(preg_replace('/[^A-Za-z0-9]+/','_',$slug))."_VERSION";
  $src=preg_replace("/(defined\\(\\s*'ABSPATH'\\s*\\).*?exit;\\s*)/s","$1\n\ndefine('".$const."','$ver');\n",$src,1);
}
file_put_contents($path,$src);
PHP
)
php -r "$fix" "$MAIN_PATH" "$NEXT" "$PLUGIN_SLUG"
ok "Bumped to v${NEXT}"

# Simple changelog
step "Update CHANGELOG.md"
TODAY="$(date +%Y-%m-%d)"; touch CHANGELOG.md
grep -q "## \[${NEXT}\]" CHANGELOG.md || sed -i "1s/^/# Changelog\n\n## [${NEXT}] - ${TODAY}\n\n### Changes\n* Release ${NEXT}\n\n/" CHANGELOG.md
git add CHANGELOG.md "$MAIN_PATH"

# Commit / tag / push
step "Commit & tag"
git commit -m "chore(release): v${NEXT}" >/dev/null 2>&1 || warn "Nothing to commit"
git tag -f "v${NEXT}"
step "Push"
git push origin main || { warn "Retry push"; git fetch origin main --tags || true; git push origin main || true; }
git push -f origin "v${NEXT}" || warn "Tag push skipped"

# Build zip
step "Build zip"
ART="artifacts"; PKG="package/${PLUGIN_SLUG}"; ZIP="${PLUGIN_SLUG}-v${NEXT}.zip"
rm -rf "$ART" "$PKG"; mkdir -p "$ART" "$PKG"
EXC=(--exclude ".git/" --exclude "artifacts/" --exclude "package/" --exclude ".github/" --exclude ".DS_Store")
[[ "$SRC_DIR" == "." ]] && rsync -a "${EXC[@]}" ./ "$PKG/" || rsync -a "${EXC[@]}" "${SRC_DIR}/" "$PKG/"
( cd package && zip -qr "../${ART}/${ZIP}" "${PLUGIN_SLUG}" )
ok "Built ${ART}/${ZIP}"

# GitHub release (optional)
if command -v gh >/dev/null 2>&1; then
  step "GitHub release v${NEXT}"
  gh release view "v${NEXT}" >/dev/null 2>&1 && gh release upload "v${NEXT}" "${ART}/${ZIP}" --clobber >/dev/null \
    || gh release create "v${NEXT}" "${ART}/${ZIP}" -t "v${NEXT}" -n "Release ${NEXT}" >/dev/null
  ok "Published"
else
  warn "gh not installed; skipped GitHub release"
fi

printf "${C2}🎉 Done: artifacts/${ZIP}${C0}\n"
