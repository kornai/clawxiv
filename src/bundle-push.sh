#!/usr/bin/env bash
# bundle-push.sh — publish a local bundle to the public archive
#
# This is the irreversible step: IPFS pin, IPNS update, GitHub push.
# Run only when the work is ready to be public.
# bundle-create.sh must have been run first (out/bundle.zip must exist).
#
# Usage:
#   src/bundle-push.sh <project-dir> [--skip-ipfs] [--skip-github] [--dry-run]
#
# Environment variables:
#   CLAWXIV_KEYS_DIR   directory containing author.priv.pem (required)
#   IPNS_KEY           IPFS key name (default: clawxiv)
#   GITHUB_REPO        GitHub repo slug (default: read from project.yaml)
#   CONVERSATION_URL   override conversation URL for log entry

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAWXIV_PY="${SCRIPT_DIR}/clawxiv.py"

# ── Arguments ────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <project-dir> [--skip-ipfs] [--skip-github] [--dry-run]" >&2
    exit 1
fi

PROJ_DIR="$(cd "$1" && pwd)"
shift

SKIP_IPFS=false
SKIP_GITHUB=false
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --skip-ipfs)    SKIP_IPFS=true ;;
        --skip-github)  SKIP_GITHUB=true ;;
        --dry-run)      DRY_RUN=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

run() {
    if $DRY_RUN; then echo "  [dry-run] $*"; else "$@"; fi
}

# ── Locate bundle ─────────────────────────────────────────────────────────────
OUT_DIR="${PROJ_DIR}/out"
BUNDLE_ZIP="${OUT_DIR}/bundle.zip"
LOG_JSONL="${OUT_DIR}/clawxiv_log.jsonl"
YAML="${PROJ_DIR}/project.yaml"

[[ -f "$BUNDLE_ZIP" ]] || {
    echo "Bundle not found: $BUNDLE_ZIP" >&2
    echo "Run src/bundle-create.sh first." >&2
    exit 1
}

# ── Locate keys ───────────────────────────────────────────────────────────────
PRIV_KEYS_DIR="${CLAWXIV_KEYS_DIR:-${HOME}/.clawxiv/keys}"
PRIV_KEY="${PRIV_KEYS_DIR}/author.priv.pem"

if [[ ! -f "$PRIV_KEY" ]]; then
    echo "Private key not found: $PRIV_KEY" >&2
    echo "Set CLAWXIV_KEYS_DIR to the directory containing author.priv.pem" >&2
    exit 1
fi

# Public key: alongside private key, then project keys/
if [[ -f "${PRIV_KEYS_DIR}/author.pub.pem" ]]; then
    PUB_KEY="${PRIV_KEYS_DIR}/author.pub.pem"
elif [[ -f "${PROJ_DIR}/keys/author.pub.pem" ]]; then
    PUB_KEY="${PROJ_DIR}/keys/author.pub.pem"
else
    echo "Public key not found (checked ${PRIV_KEYS_DIR}/ and ${PROJ_DIR}/keys/)" >&2
    exit 1
fi

# ── Read metadata ─────────────────────────────────────────────────────────────
SLUG=$(grep        '^slug:'        "$YAML" | head -1 | sed "s/slug: *//;s/'//g")
BUNDLE_ROOT=$(grep '^bundle_root:' "$YAML" | head -1 | sed "s/bundle_root: *//;s/'//g")
CONV_URL="${CONVERSATION_URL:-$(grep -A1 'conversation_urls:' "$YAML" | grep '^\s*-' | head -1 | sed "s/.*- *//;s/'//g")}"

[[ -n "$BUNDLE_ROOT" ]] || {
    echo "bundle_root is empty in project.yaml — run src/bundle-create.sh first." >&2
    exit 1
}

echo "=== bundle-push ==="
echo "  slug        : $SLUG"
echo "  bundle_root : $BUNDLE_ROOT"
echo "  bundle      : $BUNDLE_ZIP"

# ── Verify bundle before pushing ──────────────────────────────────────────────
echo "  verifying bundle integrity..."
run python3 "$CLAWXIV_PY" bundle-verify \
    --bundle "$BUNDLE_ZIP" \
    --public-key "$PUB_KEY"
echo "  bundle verified OK"

# ── IPFS pin ──────────────────────────────────────────────────────────────────
IPFS_CID=""
if $SKIP_IPFS; then
    echo "  [skip] IPFS"
else
    echo "  pinning to IPFS..."
    IPFS_OUT=$(run ipfs add -q "$BUNDLE_ZIP")
    IPFS_CID="$IPFS_OUT"
    echo "  IPFS CID: $IPFS_CID"

    IPNS_KEY="${IPNS_KEY:-clawxiv}"
    run ipfs name publish --key="$IPNS_KEY" "/ipfs/${IPFS_CID}"
    echo "  IPNS updated (key: $IPNS_KEY)"

    # Append to cid_history in out/
    if ! $DRY_RUN; then
        echo "${IPFS_CID}  $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${OUT_DIR}/cid_history.txt"
        echo "  appended CID to out/cid_history.txt"
    fi
fi

# ── GitHub sync ───────────────────────────────────────────────────────────────
# git-sync.sh handles the git repo separately (the git working tree is
# distinct from the ClawXiv project directory and requires explicit file
# copying and git mv/rm before committing).
if $SKIP_GITHUB; then
    echo "  [skip] GitHub"
else
    GIT_SYNC="${SCRIPT_DIR}/git-sync.sh"
    if [[ -x "$GIT_SYNC" ]]; then
        echo "  running git-sync.sh..."
        run "$GIT_SYNC" "$PROJ_DIR"
    else
        echo "  [skip] GitHub (git-sync.sh not found at ${GIT_SYNC})"
        echo "         Run manually: src/git-sync.sh $PROJ_DIR"
    fi
fi

# ── Log the push event ────────────────────────────────────────────────────────
PAYLOAD="{\"slug\":\"${SLUG}\",\"bundle_root\":\"${BUNDLE_ROOT}\",\"ipfs_cid\":\"${IPFS_CID}\",\"conversation_url\":\"${CONV_URL}\",\"action\":\"bundle-push\"}"
run python3 "$CLAWXIV_PY" log-append \
    --log "$LOG_JSONL" \
    --type "bundle-push" \
    --payload-json "$PAYLOAD" \
    --signer-priv "$PRIV_KEY"

echo "=== done ==="
echo "  bundle_root : $BUNDLE_ROOT"
[[ -n "$IPFS_CID" ]] && echo "  IPFS CID    : $IPFS_CID"
echo "  log         : $LOG_JSONL"
echo ""
echo "  Manual steps remaining:"
echo "    - lebadus.ai upload (if applicable)"
echo "    - arXiv submission (if applicable)"
