#!/usr/bin/env bash
# bundle-create.sh — normalize → signed local bundle
#
# Creates a signed ClawXiv bundle from a normalized project directory.
# Local only: no network access, safe to run at any time.
# Writes bundle_root back into project.yaml and provenance.json.
# Auto-detects root_tex from src/ if project.yaml has none or is stale.
#
# Usage:
#   src/bundle-create.sh <project-dir> [--skip-compile] [--dry-run]
#
# <project-dir> must contain:
#   src/            source files including root .tex
#   project.yaml    canonical metadata
#
# Output written to <project-dir>/out/:
#   bundle.zip          signed bundle (does NOT include private keys)
#   clawxiv_log.jsonl   local event log
#
# Key lookup (in order of precedence):
#   CLAWXIV_KEYS_DIR env var         — must contain author.priv.pem
#   <project-dir>/keys/              — for public key fallback only
#   ~/.clawxiv/keys/                 — default
#
# Requires: python3 (with cryptography), pdflatex (unless --skip-compile)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAWXIV_PY="${SCRIPT_DIR}/clawxiv.py"

# ── Arguments ────────────────────────────────────────────────────────────────
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <project-dir> [--skip-compile] [--dry-run]" >&2
    exit 1
fi

PROJ_DIR="$(cd "$1" && pwd)"
shift

SKIP_COMPILE=false
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        --skip-compile) SKIP_COMPILE=true ;;
        --dry-run)      DRY_RUN=true ;;
        *) echo "Unknown option: $arg" >&2; exit 1 ;;
    esac
done

run() {
    if $DRY_RUN; then echo "  [dry-run] $*"; else "$@"; fi
}

# ── Locate keys ───────────────────────────────────────────────────────────────
# Private key: CLAWXIV_KEYS_DIR, then ~/.clawxiv/keys
# Public key:  same dir as private key, then project keys/, then ~/.clawxiv/keys
PRIV_KEYS_DIR="${CLAWXIV_KEYS_DIR:-${HOME}/.clawxiv/keys}"
PRIV_KEY="${PRIV_KEYS_DIR}/author.priv.pem"

if [[ ! -f "$PRIV_KEY" ]]; then
    echo "Private key not found: $PRIV_KEY" >&2
    echo "Set CLAWXIV_KEYS_DIR to the directory containing author.priv.pem" >&2
    exit 1
fi

# Look for public key alongside private key first, then in project keys/
if [[ -f "${PRIV_KEYS_DIR}/author.pub.pem" ]]; then
    PUB_KEY="${PRIV_KEYS_DIR}/author.pub.pem"
elif [[ -f "${PROJ_DIR}/keys/author.pub.pem" ]]; then
    PUB_KEY="${PROJ_DIR}/keys/author.pub.pem"
else
    echo "Public key not found (checked ${PRIV_KEYS_DIR}/ and ${PROJ_DIR}/keys/)" >&2
    exit 1
fi

# ── Read project.yaml ─────────────────────────────────────────────────────────
SRC_DIR="${PROJ_DIR}/src"
OUT_DIR="${PROJ_DIR}/out"
YAML="${PROJ_DIR}/project.yaml"
PROV="${PROJ_DIR}/provenance.json"
LOG_JSONL="${OUT_DIR}/clawxiv_log.jsonl"
BUNDLE_ZIP="${OUT_DIR}/bundle.zip"

[[ -f "$YAML" ]] || { echo "Not found: $YAML" >&2; exit 1; }
[[ -d "$SRC_DIR" ]] || { echo "Not found: $SRC_DIR" >&2; exit 1; }
mkdir -p "$OUT_DIR"

# Extract fields from project.yaml
SLUG=$(grep    '^slug:'     "$YAML" | head -1 | sed "s/slug: *//;s/'//g")
ROOT_TEX=$(grep '^root_tex:' "$YAML" | head -1 | sed "s/root_tex: *//;s/'//g")

# ── Auto-detect root_tex if missing or stale ──────────────────────────────────
# If the file named in project.yaml doesn't exist in src/, find the newest .tex
# with \documentclass and update project.yaml automatically.
if [[ -z "$ROOT_TEX" || ! -f "${SRC_DIR}/${ROOT_TEX}" ]]; then
    DETECTED=$(grep -rl '\\documentclass' "${SRC_DIR}"/*.tex 2>/dev/null \
        | xargs ls -t 2>/dev/null | head -1)
    if [[ -n "$DETECTED" ]]; then
        ROOT_TEX="$(basename "$DETECTED")"
        echo "  auto-detected root_tex: $ROOT_TEX (updating project.yaml)"
        python3 - << PYEOF
import re
path = "$YAML"
val  = "$ROOT_TEX"
content = open(path).read()
content = re.sub(r"^root_tex:.*$", f"root_tex: '{val}'", content, flags=re.MULTILINE)
open(path, 'w').write(content)
PYEOF
    else
        echo "  WARNING: no root_tex found in src/ — skipping pdflatex"
    fi
fi

echo "=== bundle-create ==="
echo "  project : $PROJ_DIR"
echo "  slug    : $SLUG"
echo "  root_tex: $ROOT_TEX"
echo "  out     : $OUT_DIR"
echo "  priv_key: $PRIV_KEY"
echo "  pub_key : $PUB_KEY"

# ── Compile PDF ───────────────────────────────────────────────────────────────
if [[ -n "$ROOT_TEX" && -f "${SRC_DIR}/${ROOT_TEX}" ]]; then
    if $SKIP_COMPILE; then
        echo "  [skip] pdflatex"
    else
        echo "  running pdflatex (pass 1)..."
        run pdflatex -interaction=nonstopmode \
            -output-directory "$OUT_DIR" \
            "${SRC_DIR}/${ROOT_TEX}"
        # bibtex/biber only if a separate .bib file exists
        # (if bibliography is embedded in .tex, skip this block)
        if ls "${SRC_DIR}"/*.bib &>/dev/null; then
            JOBNAME="${ROOT_TEX%.tex}"
            echo "  running bibtex..."
            run bibtex "${OUT_DIR}/${JOBNAME}" || true
        fi
        echo "  running pdflatex (pass 2)..."
        run pdflatex -interaction=nonstopmode \
            -output-directory "$OUT_DIR" \
            "${SRC_DIR}/${ROOT_TEX}"
        echo "  PDF compiled"
    fi
else
    echo "  [skip] pdflatex (no root_tex in src/)"
fi

# ── Copy PDF into src/ so it is included in the bundle ───────────────────────
PDF_NAME="${ROOT_TEX%.tex}.pdf"
if [[ -f "${OUT_DIR}/${PDF_NAME}" ]]; then
    run cp "${OUT_DIR}/${PDF_NAME}" "${SRC_DIR}/${PDF_NAME}"
    echo "  copied PDF to src/"
fi

# ── Safety check: private key must not be inside src/ ────────────────────────
if [[ "$PRIV_KEY" == "${SRC_DIR}"/* ]]; then
    echo "ERROR: private key is inside src/ and would be included in the bundle!" >&2
    echo "Move it outside src/ before running bundle-create." >&2
    exit 1
fi

# ── Create bundle ─────────────────────────────────────────────────────────────
echo "  creating bundle..."
BUNDLE_OUTPUT=$(run python3 "$CLAWXIV_PY" bundle-create \
    --root-dir   "$SRC_DIR" \
    --out-bundle "$BUNDLE_ZIP" \
    --private-key "$PRIV_KEY" \
    --public-key  "$PUB_KEY" \
    --engine pdflatex)

if $DRY_RUN; then
    BUNDLE_ROOT="(dry-run)"
else
    echo "$BUNDLE_OUTPUT"
    BUNDLE_ROOT=$(echo "$BUNDLE_OUTPUT" | grep '^bundle_root=' | cut -d= -f2)
fi

echo "  bundle_root: $BUNDLE_ROOT"

# ── Write bundle_root back into project.yaml and provenance.json ──────────────
if ! $DRY_RUN && [[ -n "$BUNDLE_ROOT" ]]; then
    python3 - << PYEOF
import re
path = "$YAML"
root = "$BUNDLE_ROOT"
content = open(path).read()
content = re.sub(r"^bundle_root:.*$", f"bundle_root: '{root}'", content, flags=re.MULTILINE)
open(path, 'w').write(content)
print("  updated bundle_root in project.yaml")
PYEOF

    python3 - << PYEOF
import json
path = "$PROV"
root = "$BUNDLE_ROOT"
try:
    d = json.loads(open(path).read())
    d['bundle_root'] = root
    open(path, 'w').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
    print("  updated bundle_root in provenance.json")
except Exception as e:
    print(f"  warning: could not update provenance.json: {e}")
PYEOF
fi

# ── Log the create event ──────────────────────────────────────────────────────
PAYLOAD="{\"slug\":\"${SLUG}\",\"bundle_root\":\"${BUNDLE_ROOT}\",\"action\":\"bundle-create\"}"
run python3 "$CLAWXIV_PY" log-append \
    --log "$LOG_JSONL" \
    --type "bundle-create" \
    --payload-json "$PAYLOAD" \
    --signer-priv "$PRIV_KEY"

echo "=== done ==="
echo "  bundle : $BUNDLE_ZIP"
echo "  log    : $LOG_JSONL"
echo ""
echo "  To publish: src/bundle-push.sh $PROJ_DIR"
