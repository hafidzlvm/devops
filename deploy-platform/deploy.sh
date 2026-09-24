#!/bin/bash
set -euo pipefail

# ============================================================
# deploy.sh — Automated Git Flow Release + Deploy
# ============================================================
# Usage:
#   ./deploy.sh                     # auto-bump patch
#   ./deploy.sh minor               # bump minor
#   ./deploy.sh major               # bump major
#   ./deploy.sh 0.9.9               # explicit version
#
# Prerequisites:
#   - git-flow (apt install git-flow / brew install git-flow-avh)
#   - Git branch: develop (where releases branch from)
#   - Toolchain sesuai stack (node/bun, go, cargo) hanya jika dipakai
#
# Stack detection (otomatis via file penanda, urutan pertama menang):
#   Cargo.toml -> rust | go.mod -> go | tsconfig.json -> node-ts
#   package.json -> node | requirements.txt/pyproject.toml -> python
#
# Overrides (untuk kasus aneh tanpa ubah script):
#   STACK=go ./deploy.sh minor
#   BUILD_CHECK="make verify" ./deploy.sh
#   VERSION_FILE=VERSION ./deploy.sh 0.9.9
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── 1. Determine paths ───────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR"

cd "$SCRIPT_DIR"

# ── 2. Pre-flight checks ─────────────────────────────────
[[ -z "$(git status --porcelain)" ]] || err "Working directory not clean. Commit or stash first."

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$CURRENT_BRANCH" == "develop" ]] || err "Must be on 'develop' branch. Current: $CURRENT_BRANCH"

command -v git-flow >/dev/null 2>&1 || err "git-flow not installed. Run: apt install git-flow"

# ── 3. Sync main & develop from remote ──────────────────
log "Syncing branches from remote..."

if git show-ref --verify --quiet refs/heads/main; then
  log "Local main exists, syncing with origin/main..."
  git switch main
  git fetch origin main
  git reset --hard origin/main
else
  log "Local main not found, creating from origin/main..."
  git checkout -b main origin/main
fi

log "Switching back to develop..."
git switch develop
log "Syncing develop with origin/develop..."
git fetch origin develop
if git merge-base --is-ancestor HEAD origin/develop; then
  git merge --ff-only origin/develop
elif git merge-base --is-ancestor origin/develop HEAD; then
  log "develop is ahead of origin/develop, skipping pull."
else
  warn "develop has diverged from origin/develop."
  warn "Proceeding with local develop as base for release."
fi

# ── 4. Determine version (stack-agnostic) ────────────
get_version() {
  if [[ -n "${VERSION_FILE:-}" ]]; then
    [[ -f "$VERSION_FILE" ]] || err "VERSION_FILE=$VERSION_FILE not found."
    cat "$VERSION_FILE"
  elif [[ -f "$APP_DIR/package.json" ]]; then
    node -p "require('$APP_DIR/package.json').version"
  elif [[ -f "$APP_DIR/VERSION" ]]; then
    cat "$APP_DIR/VERSION"
  else
    err "No version source: pass explicit version, or add package.json / VERSION file (or set VERSION_FILE)."
  fi
}

set_version() {
  local v="$1"
  if [[ -n "${VERSION_FILE:-}" ]] || [[ ! -f "$APP_DIR/package.json" ]]; then
    local f="${VERSION_FILE:-$APP_DIR/VERSION}"
    echo "$v" > "$f"
    log "version file ($f) set to $v"
  else
    node -e "
      const pkg = require('$APP_DIR/package.json');
      pkg.version = '$v';
      require('fs').writeFileSync('$APP_DIR/package.json', JSON.stringify(pkg, null, 2) + '\n');
    "
    log "package.json bumped to $v"
  fi
}

CURRENT_VERSION=$(get_version)
log "Current version: $CURRENT_VERSION"

VERSION_ARG="${1:-patch}"

if [[ "$VERSION_ARG" == "patch" || "$VERSION_ARG" == "minor" || "$VERSION_ARG" == "major" ]]; then
  NEW_VERSION=$(node -e "
    const parts = '$CURRENT_VERSION'.split('.').map(Number);
    if ('$VERSION_ARG' === 'major') { parts[0]++; parts[1]=0; parts[2]=0; }
    else if ('$VERSION_ARG' === 'minor') { parts[1]++; parts[2]=0; }
    else { parts[2]++; }
    console.log(parts.join('.'));
  ")
else
  NEW_VERSION="$VERSION_ARG"
fi

# NEW_VERSION_GIT=$NEW_VERSION-dev
# NEW_VERSION_GIT=$NEW_VERSION-prod <choose the suffix you want>
NEW_VERSION_GIT=$NEW_VERSION

log "Target version app: $NEW_VERSION"
log "Target version git: $NEW_VERSION_GIT"

# ── 5. Build check — gagalkan lebih awal kalau build error ──
detect_stack() {
  if [[ -n "${STACK:-}" ]]; then echo "$STACK"; return; fi
  if [[ -f "$APP_DIR/Cargo.toml" ]]; then echo "rust"
  elif [[ -f "$APP_DIR/go.mod" ]]; then echo "go"
  elif [[ -f "$APP_DIR/tsconfig.json" ]]; then echo "node-ts"
  elif [[ -f "$APP_DIR/package.json" ]]; then echo "node"
  elif [[ -f "$APP_DIR/requirements.txt" || -f "$APP_DIR/pyproject.toml" ]]; then echo "python"
  else echo "unknown"; fi
}

run_build_check() {
  if [[ -n "${BUILD_CHECK:-}" ]]; then
    log "Running custom BUILD_CHECK..."
    (cd "$APP_DIR" && bash -c "$BUILD_CHECK")
    return
  fi
  case "$STACK" in
    node-ts)
      log "Running type check (source files only)..."
      TSC_OUTPUT=$(cd "$APP_DIR" && npx tsc --noEmit 2>&1) || true
      SRC_ERRORS=$(echo "$TSC_OUTPUT" | grep "error TS" | grep -v "node_modules/" || true)
      if [[ -n "$SRC_ERRORS" ]]; then
        echo ""
        echo "$SRC_ERRORS"
        echo ""
        err "TypeScript errors in source code. Perbaiki sebelum release."
      fi
      ;;
    node)
      log "Running production build (node)..."
      (cd "$APP_DIR" && (bun run build || npm run build))
      ;;
    go)
      log "Running go vet + build..."
      (cd "$APP_DIR" && go vet ./... && go build ./...)
      ;;
    rust)
      log "Running cargo check..."
      (cd "$APP_DIR" && cargo check --locked)
      ;;
    python)
      log "Running python compile check..."
      (cd "$APP_DIR" && python3 -m compileall -q .)
      ;;
    *)
      warn "Unknown stack, skipping build check."
      ;;
  esac
}

STACK=$(detect_stack)
log "Detected stack: $STACK"
run_build_check
log "Build check passed."

# ── 6. (dihapus: build production duplikat — sudah dicover step 5) ──

# ── 7. Git flow release start ────────────────────────────
log "Starting release $NEW_VERSION_GIT..."
git flow release start "$NEW_VERSION_GIT"

# ── 8. Bump version ──────────────────────────────
set_version "$NEW_VERSION"

# ── 9. Commit version bump ───────────────────────────────
if [[ -n "${VERSION_FILE:-}" ]] || [[ ! -f "$APP_DIR/package.json" ]]; then
  git add "${VERSION_FILE:-$APP_DIR/VERSION}"
else
  git add "$APP_DIR/package.json"
fi
git commit -m "Bump version to $NEW_VERSION" || warn "Nothing to commit (version unchanged)"

# ── 10. Git flow release finish ───────────────────────────
log "Finishing release $NEW_VERSION..."
GIT_MERGE_AUTOEDIT=no git flow release finish "$NEW_VERSION_GIT" -m "$NEW_VERSION_GIT"

# ── 11. Push everything ───────────────────────────────────
log "Pushing to origin..."
git push origin main develop --follow-tags

# ── 12. Done ─────────────────────────────────────────────
log "✅ Release $NEW_VERSION completed and pushed!"
log "   CI/CD will auto-deploy tag $NEW_VERSION to development."