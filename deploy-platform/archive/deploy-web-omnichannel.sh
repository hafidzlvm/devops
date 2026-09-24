#!/bin/bash
set -euo pipefail

# ============================================================
# deploy-web-omnichannel.sh — Sync Omnichannel BE ke Monorepo
# ============================================================
# Flow:
#   1. Developer commit + push di pesan-pintar-be-omnichannel
#   2. Release pakai ./deploy.sh di BE repo (git flow + tag)
#   3. Jalankan script ini di monorepo untuk subtree pull
#
# Usage:
#   ./deploy-web-omnichannel.sh          # pull latest main
#   ./deploy-web-omnichannel.sh develop  # pull develop (saat testing)
#   ./deploy-web-omnichannel.sh v1.0.0   # pull specific tag
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

# ── 1. Paths ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BE_REPO="$SCRIPT_DIR/../pesan-pintar-be-omnichannel"

SUBTREE_PREFIX="web/omnichannel/app"
REMOTE_NAME="origin/web/omnichannel"
SOURCE_BRANCH="${1:-main}"

cd "$SCRIPT_DIR"

# ── 2. Pre-flight checks ──────────────────────────────────
[[ -z "$(git status --porcelain)" ]] || err "Working directory not clean. Commit or stash first."

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$CURRENT_BRANCH" == "develop" ]] || warn "Not on 'develop' branch. Current: $CURRENT_BRANCH"

# ── 3. Verify remote exists ──────────────────────────────
if ! git remote get-url "$REMOTE_NAME" >/dev/null 2>&1; then
  err "Remote '$REMOTE_NAME' not found. Add it with:
       git remote add $REMOTE_NAME git@github.com:developer-pim/pesan-pintar-be-omnichannel.git"
fi

log "Remote: $(git remote get-url "$REMOTE_NAME")"
log "Subtree prefix: $SUBTREE_PREFIX"
log "Source branch: $SOURCE_BRANCH"

# ── 4. Fetch latest from BE remote ────────────────────────
log "Fetching latest from $REMOTE_NAME..."
git fetch "$REMOTE_NAME" "$SOURCE_BRANCH"

# ── 5. Show what's new ────────────────────────────────────
log "Changes since last subtree pull:"
git log --oneline HEAD..FETCH_HEAD -- 2>/dev/null || echo "  (no new commits or first pull)"

# ── 6. Subtree pull ───────────────────────────────────────
log "Pulling subtree $REMOTE_NAME/$SOURCE_BRANCH → $SUBTREE_PREFIX..."
git subtree pull \
  --prefix="$SUBTREE_PREFIX" \
  "$REMOTE_NAME" \
  "$SOURCE_BRANCH" \
  --squash

# ── 7. Done ───────────────────────────────────────────────
log "✅ Subtree pull complete!"
log "   BE source: $REMOTE_NAME/$SOURCE_BRANCH"
log "   Local path: $SUBTREE_PREFIX"
log ""
log "   Next: review changes, then:"
log "     git push origin develop"