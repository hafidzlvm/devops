#!/bin/bash
set -euo pipefail

# ============================================================
# deploy.sh — Monorepo Release + Subtree Sync + Deploy
# ============================================================
# Usage:
#   ./deploy.sh                                    # patch, no subtree
#   ./deploy.sh minor                              # minor, no subtree
#   ./deploy.sh major                              # major, no subtree
#   ./deploy.sh 0.9.9                              # explicit version, no subtree
#
#   ./deploy.sh web/omnichannel                    # patch + web subtree
#   ./deploy.sh web/omnichannel minor              # minor + web subtree
#   ./deploy.sh frontend/monitoring patch          # patch + frontend build
#   ./deploy.sh web/omnichannel frontend/monitoring major  # major + both
#
#   ./deploy.sh --all minor                        # all subtrees + frontend
#   ./deploy.sh --dry-run web/omnichannel          # simulate
#   ./deploy.sh --publish patch                    # patch + auto-publish Release + watch CD
#
# Flags:
#   --publish   → auto-create GitHub Release after push, sleep 5s, then follow the CD run
#                 (ignored with --dry-run; needs 'gh auth login')
#
# Subtree components:
#   web/omnichannel       → pull from origin/web/omnichannel
#   frontend/monitoring   → npm ci && npm run build
#   --all                 → both
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
err()  { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }

# ── 1. Parse args ──────────────────────────────────────────
DRY_RUN=false
PUBLISH=false
COMPONENTS=()
VERSION_ARG=""

for arg in "$@"; do
  case "$arg" in
    --dry-run)     DRY_RUN=true ;;
    --publish)     PUBLISH=true ;;
    --all|--subtree) COMPONENTS=("web/omnichannel" "frontend/monitoring") ;;
    web/*|frontend/*) COMPONENTS+=("$arg") ;;
    patch|minor|major) VERSION_ARG="$arg" ;;
    *)             [[ "$arg" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] && VERSION_ARG="$arg" || warn "Unknown arg: $arg" ;;
  esac
done

VERSION_ARG="${VERSION_ARG:-patch}"
$DRY_RUN && log "DRY RUN MODE — no git changes will be made"

# ── 2. Paths ───────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

declare -A SUBTREE_MAP=(
  ["web/omnichannel"]="web/omnichannel/app:origin/web/omnichannel:main"
)

FE_DIR="frontend/omnichannel/app"

# ── 3. Pre-flight checks ───────────────────────────────────
[[ -z "$(git status --porcelain)" ]] || err "Working directory not clean. Commit or stash first."

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$CURRENT_BRANCH" == "develop" ]] || err "Must be on 'develop' branch. Current: $CURRENT_BRANCH"

[[ "$DRY_RUN" == "true" ]] || command -v git-flow >/dev/null 2>&1 || err "git-flow not installed. Run: apt install git-flow"
[[ "$PUBLISH" != "true" || "$DRY_RUN" == "true" ]] || command -v gh >/dev/null 2>&1 || err "gh CLI not found. Install gh + 'gh auth login', or drop --publish."

# ── 4. Sync main & develop from remote ────────────────────
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
  warn "develop has diverged from origin/develop. Proceeding with local."
fi

# ── 5. Sync subtrees (opt-in via component args) ────────────
if [[ ${#COMPONENTS[@]} -gt 0 ]]; then
  log "Components selected: ${COMPONENTS[*]}"
fi

for comp in "${COMPONENTS[@]}"; do
  if [[ -n "${SUBTREE_MAP[$comp]:-}" ]]; then
    IFS=':' read -r PREFIX REMOTE BRANCH <<< "${SUBTREE_MAP[$comp]}"

    if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
      warn "Remote '$REMOTE' not found — skipping $comp"
      continue
    fi

    log "Syncing subtree: $comp ($PREFIX ← $REMOTE/$BRANCH)"
    git fetch "$REMOTE" "$BRANCH"

    BEHIND=$(git rev-list --count HEAD..FETCH_HEAD 2>/dev/null || echo 0)
    if [[ "$BEHIND" -gt 0 ]]; then
      info "  $BEHIND new commit(s)"
      git subtree pull --prefix="$PREFIX" "$REMOTE" "$BRANCH" --squash
    else
      info "  already up-to-date"
    fi
  elif [[ "$comp" == "frontend/monitoring" ]]; then
    if [[ -d "$FE_DIR" ]] && [[ -f "$FE_DIR/package.json" ]]; then
      log "Building frontend ($comp)..."
      if (cd "$FE_DIR" && npm ci --legacy-peer-deps && npm run build); then
        FE_NEW_VERSION=$(cd "$FE_DIR" && npm version "$VERSION_ARG" --no-git-tag-version)
        log "Frontend build OK — package.json bumped to ${FE_NEW_VERSION#v}"
      else
        warn "Frontend build failed — version not bumped, continuing"
      fi
    else
      warn "No package.json in $FE_DIR — skipping $comp"
    fi
  else
    warn "Unknown component: $comp — skipping"
  fi
done

# ── 6. Determine version ───────────────────────────────────
CURRENT_VERSION=$(git tag --sort=-v:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+(-dev)?$' | head -1 | sed 's/-dev//' || echo "0.0.0")
[[ -z "$CURRENT_VERSION" ]] && CURRENT_VERSION="0.0.0"
log "Current version: $CURRENT_VERSION"

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

log "Target version: $NEW_VERSION"

# ── 7. Build release tag message ────────────────────────────
if [[ ${#COMPONENTS[@]} -gt 0 ]]; then
  COMP_STR=$(IFS=';'; echo "${COMPONENTS[*]}")
  RELEASE_MSG="Release version $NEW_VERSION ($COMP_STR)"
else
  RELEASE_MSG="Release version $NEW_VERSION"
fi

# ── 8. Commit subtree + build changes ───────────────────────
if [[ -n "$(git status --porcelain)" ]]; then
  log "New changes detected (subtree/build). Committing..."
  git add -A
  git commit -m "chore: sync and build for v$NEW_VERSION"
else
  log "No new changes to commit."
fi

# ── 9. Dry-run exit ────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  log "Dry run complete. Would release: $RELEASE_MSG"
  exit 0
fi

# ── 10. Git flow release start ──────────────────────────────
log "Starting release $NEW_VERSION..."
git flow release start "$NEW_VERSION"

# ── 11. Git flow release finish ─────────────────────────────
log "Finishing release $NEW_VERSION..."
export GIT_MERGE_AUTOEDIT=no
git flow release finish "$NEW_VERSION" -m "$RELEASE_MSG"

# ── 12. Push ────────────────────────────────────────────────
log "Pushing to origin..."
git push origin main develop --follow-tags

# ── 13. Done ────────────────────────────────────────────────
log "✅ $RELEASE_MSG complete!"
log ""
if [[ ${#COMPONENTS[@]} -gt 0 ]]; then
  GH_RELEASE_CMD=(gh release create "v$NEW_VERSION" --target main --title "v$NEW_VERSION ($COMP_STR)" --generate-notes)
else
  GH_RELEASE_CMD=(gh release create "v$NEW_VERSION" --target main --generate-notes)
fi

if [[ "$PUBLISH" == "true" ]]; then
  log "Publishing GitHub Release to trigger CD pipeline:"
  log "     ${GH_RELEASE_CMD[*]}"
  "${GH_RELEASE_CMD[@]}"
  log "Waiting 5s for the workflow run to appear..."
  sleep 5
  RUN_ID="$(gh run list --workflow release.cd.yaml --limit 5 --json databaseId,status --jq '[.[] | select(.status == "queued" or .status == "in_progress" or .status == "waiting" or .status == "requested" or .status == "pending")][0].databaseId // empty' 2>/dev/null || echo "")"
  if [[ -n "$RUN_ID" ]]; then
    log "   Open in browser:"
    log "     https://github.com/developer-pim/pesan-pintar/actions/runs/$RUN_ID"
    gh run watch "$RUN_ID"
  else
    warn "New run not found yet — check the run list:"
    log "     https://github.com/developer-pim/pesan-pintar/actions"
    gh run watch
  fi
else
  log "   Next: publish GitHub Release to trigger CD pipeline:"
  log "     ${GH_RELEASE_CMD[*]}"
fi
log ""
log "   Monitor the CD run (needs 'gh auth login'):"
log "     gh run list --workflow release.cd.yaml --limit 5   # recent runs"
log "     gh run watch                                        # live-follow latest run"
log "     gh run view <run-id> --log                          # full logs of a run"
log ""
log "   Open in browser:"
log "     https://github.com/developer-pim/pesan-pintar/actions"