#!/usr/bin/env bash
# git-sync.sh — sync the ClawXiv working directory to the git repository
#
# The git repo (~/Sandbox/clawxiv by default) has a different structure
# from the working directory.  This script copies the right files, handles
# the post-cleanup structural changes (files moved into src/, attic/, out/),
# stages everything correctly, and commits.
#
# Usage:
#   src/git-sync.sh <project-dir> [--dry-run] [--skip-push]
#
# Environment variables:
#   CLAWXIV_GIT_DIR   path to the git working tree (default: ~/Sandbox/clawxiv)
#
# What goes into the git repo:
#   src/              all paper source and toolchain scripts
#   keys/             public keys only (never private keys)
#   out/bundle.zip    the signed bundle
#   out/clawxiv_log.jsonl
#   out/cid_history.txt  (if present)
#   project.yaml
#   README.md         (from src/ if present, else project root)
#   requirements.txt  (if present in project root)
#
# What does NOT go into the git repo:
#   keys/author.priv.pem  (private key — never)
#   out/*.aux, *.log, *.toc, *.out  (latex build artifacts)
#   attic/            (historical; too bulky, irrelevant to users)
#   out/paper_bundle.zip  (old v2 bundle — superseded by bundle.zip)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Arguments ─────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <project-dir> [--dry-run] [--skip-push]" >&2
    exit 1
fi

PROJ_DIR="$(cd "$1" && pwd)"
shift

DRY_RUN=false
SKIP_PUSH=false
for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY_RUN=true ;;
        --skip-push)  SKIP_PUSH=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

run() {
    if $DRY_RUN; then echo "  [dry-run] $*"; else "$@"; fi
}

cp_to() {
    # cp_to <src-file> <dst-dir>  — copy if src exists, report either way
    local src="$1" dst_dir="$2"
    if [[ -f "$src" ]]; then
        run mkdir -p "$dst_dir"
        run cp "$src" "$dst_dir/"
        echo "  cp $(basename "$src") -> ${dst_dir}/"
    else
        echo "  [skip] $(basename "$src") not found"
    fi
}

# ── Locate git repo ───────────────────────────────────────────────────────────
GIT_DIR="${CLAWXIV_GIT_DIR:-${HOME}/Sandbox/clawxiv}"

if [[ ! -d "$GIT_DIR/.git" ]]; then
    echo "Git repo not found: $GIT_DIR" >&2
    echo "Set CLAWXIV_GIT_DIR to your git working tree." >&2
    exit 1
fi

YAML="${PROJ_DIR}/project.yaml"
[[ -f "$YAML" ]] || { echo "Not found: $YAML" >&2; exit 1; }

SLUG=$(grep '^slug:' "$YAML" | head -1 | sed "s/slug: *//;s/'//g")
BUNDLE_ROOT=$(grep '^bundle_root:' "$YAML" | head -1 | sed "s/bundle_root: *//;s/'//g")

echo "=== git-sync ==="
echo "  project : $PROJ_DIR"
echo "  git repo: $GIT_DIR"
echo "  slug    : $SLUG"
echo "  bundle_root: ${BUNDLE_ROOT:0:16}..."

# ── Safety check: no private key in src/ ─────────────────────────────────────
if [[ -f "${PROJ_DIR}/src/author.priv.pem" ]]; then
    echo "ERROR: author.priv.pem found in src/ — remove it before syncing." >&2
    exit 1
fi

# ── Step 1: Copy src/ tree into git repo src/ ─────────────────────────────────
echo ""
echo "--- Syncing src/ ---"
run mkdir -p "${GIT_DIR}/src"
# rsync preserves structure, excludes .DS_Store and build artifacts
run rsync -av --delete \
    --exclude='.DS_Store' \
    --exclude='*.aux' --exclude='*.log' --exclude='*.toc' \
    --exclude='*.out' --exclude='*.bbl' --exclude='*.blg' \
    --exclude='*.fls' --exclude='*.fdb_latexmk' \
    --exclude='author.priv.pem' \
    "${PROJ_DIR}/src/" "${GIT_DIR}/src/"

# ── Step 2: Copy public keys ──────────────────────────────────────────────────
echo ""
echo "--- Syncing keys/ (public only) ---"
run mkdir -p "${GIT_DIR}/keys"
for f in author.pub.pem classifier.pub.pem claude_keyid.txt claude_pubkey.asc; do
    cp_to "${PROJ_DIR}/keys/${f}" "${GIT_DIR}/keys"
done
# Explicitly ensure private key is not copied
if [[ -f "${GIT_DIR}/keys/author.priv.pem" ]]; then
    echo "  WARNING: removing author.priv.pem from git repo (should not be there)"
    run rm "${GIT_DIR}/keys/author.priv.pem"
fi

# ── Step 3: Copy out/ artifacts ───────────────────────────────────────────────
echo ""
echo "--- Syncing out/ artifacts ---"
run mkdir -p "${GIT_DIR}/out"
cp_to "${PROJ_DIR}/out/bundle.zip"         "${GIT_DIR}/out"
cp_to "${PROJ_DIR}/out/clawxiv_log.jsonl"  "${GIT_DIR}/out"
cp_to "${PROJ_DIR}/out/cid_history.txt"    "${GIT_DIR}/out"
cp_to "${PROJ_DIR}/out/classification.json" "${GIT_DIR}/out"

# ── Step 4: Copy top-level metadata ──────────────────────────────────────────
echo ""
echo "--- Syncing top-level files ---"
cp_to "${PROJ_DIR}/project.yaml"   "${GIT_DIR}"
# README: prefer src/README.md, fall back to project root
if [[ -f "${PROJ_DIR}/src/README.md" ]]; then
    run cp "${PROJ_DIR}/src/README.md" "${GIT_DIR}/README.md"
    echo "  cp src/README.md -> README.md"
elif [[ -f "${PROJ_DIR}/README.md" ]]; then
    run cp "${PROJ_DIR}/README.md" "${GIT_DIR}/README.md"
    echo "  cp README.md -> README.md"
fi
cp_to "${PROJ_DIR}/requirements.txt" "${GIT_DIR}" 2>/dev/null || true

# ── Step 5: Remove stale top-level files from git repo ───────────────────────
# These were at the top level in the old structure but have moved or been retired.
echo ""
echo "--- Removing stale top-level files from git repo ---"
STALE=(
    ai_keygen.sh   # deprecated historical stub
    appendix_a.tex
    appendix.tex
    clawxiv.py
    clawxiv_publish_v2.sh
    clawxiv_whitepaper_v2.pdf
    clawxiv_whitepaper_v2.tex
    clawxiv_whitepaper.pdf
    gen_appendix_a.py
    log_prompt.sh
    manifest.json
    manifest.json.ai.sig
    manifest.json.ak.sig
    cid_history.txt
)
for f in "${STALE[@]}"; do
    if [[ -f "${GIT_DIR}/${f}" ]]; then
        echo "  git rm ${f}"
        run git -C "$GIT_DIR" rm -f "${GIT_DIR}/${f}" 2>/dev/null || \
            run rm "${GIT_DIR}/${f}"
    fi
done

# ── Step 6: Stage everything ──────────────────────────────────────────────────
echo ""
echo "--- Staging ---"
run git -C "$GIT_DIR" add -A
echo "  git add -A done"

# Show what will be committed
if ! $DRY_RUN; then
    echo ""
    echo "--- Staged changes ---"
    git -C "$GIT_DIR" status --short
fi

# ── Step 7: Commit ────────────────────────────────────────────────────────────
echo ""
COMMIT_MSG="clawxiv: sync ${SLUG} bundle_root=${BUNDLE_ROOT:0:12}"
run git -C "$GIT_DIR" commit -m "$COMMIT_MSG" || {
    echo "  (nothing to commit — git repo already up to date)"
}

# ── Step 8: Push ─────────────────────────────────────────────────────────────
if $SKIP_PUSH; then
    echo "  [skip] git push"
else
    echo ""
    echo "--- Pushing to GitHub ---"
    run git -C "$GIT_DIR" push
    echo "  pushed"
fi

echo ""
echo "=== done ==="
echo "  git repo: $GIT_DIR"
echo "  To push manually: git -C $GIT_DIR push"
