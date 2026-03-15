#!/usr/bin/env bash
# log_prompt.sh — append a prompt/response record to prompts.jsonl
#
# Usage (interactive):
#   ./log_prompt.sh
#
# Usage (scripted):
#   ./log_prompt.sh --prompt "text" --response "text" [--author "AK"]
#   ./log_prompt.sh --prompt-file p.txt --response-file r.txt
#   ./log_prompt.sh --from-stdin   # reads JSON record from stdin
#
# The prompts.jsonl file is the authoritative record of the human-AI
# dialogue that produced this bundle. It is included in the bundle and
# rendered as Appendix A in the compiled PDF via gen_appendix_a.py.
#
# Record format (one JSON object per line):
# {
#   "seq": 1,
#   "timestamp": "2026-03-09T14:23:00Z",
#   "author": "AK",           // "AK" | "Claude" | "system"
#   "role": "user",           // "user" | "assistant" | "system"
#   "text": "...",
#   "bundle_version": "v3",   // which bundle version this belongs to
#   "tags": []                // optional: ["key-decision", "design", ...]
# }

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPTS_FILE="${SCRIPT_DIR}/prompts.jsonl"

BUNDLE_VERSION="${BUNDLE_VERSION:-v3}"

# -----------------------------------------------------------------------
# Parse arguments
# -----------------------------------------------------------------------
PROMPT_TEXT=""
RESPONSE_TEXT=""
AUTHOR="AK"
FROM_STDIN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt)       PROMPT_TEXT="$2";   shift 2 ;;
    --response)     RESPONSE_TEXT="$2"; shift 2 ;;
    --author)       AUTHOR="$2";        shift 2 ;;
    --prompt-file)  PROMPT_TEXT=$(cat "$2"); shift 2 ;;
    --response-file) RESPONSE_TEXT=$(cat "$2"); shift 2 ;;
    --from-stdin)   FROM_STDIN=true; shift ;;
    --version)      BUNDLE_VERSION="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

# -----------------------------------------------------------------------
# Get next sequence number
# -----------------------------------------------------------------------
next_seq() {
  if [[ ! -f "$PROMPTS_FILE" ]]; then
    echo 1
  else
    python3 -c "
import json
seqs = []
with open('${PROMPTS_FILE}') as f:
    for line in f:
        line = line.strip()
        if line:
            try:
                seqs.append(json.loads(line).get('seq', 0))
            except:
                pass
print(max(seqs, default=0) + 1)
"
  fi
}

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# -----------------------------------------------------------------------
# From stdin: just append the record
# -----------------------------------------------------------------------
if $FROM_STDIN; then
  cat >> "$PROMPTS_FILE"
  echo "Record appended to ${PROMPTS_FILE}"
  exit 0
fi

# -----------------------------------------------------------------------
# Interactive mode if no arguments
# -----------------------------------------------------------------------
if [[ -z "$PROMPT_TEXT" && -z "$RESPONSE_TEXT" ]]; then
  echo "=== ClawXiv prompt logger (interactive) ==="
  echo "Enter the prompt text (end with a line containing only '.'):"
  PROMPT_TEXT=""
  while IFS= read -r line; do
    [[ "$line" == "." ]] && break
    PROMPT_TEXT="${PROMPT_TEXT}${line}\n"
  done

  echo ""
  echo "Enter author [AK/Claude/system] (default: AK):"
  read -r input_author
  [[ -n "$input_author" ]] && AUTHOR="$input_author"

  echo ""
  echo "Enter the response text (end with a line containing only '.'):"
  RESPONSE_TEXT=""
  while IFS= read -r line; do
    [[ "$line" == "." ]] && break
    RESPONSE_TEXT="${RESPONSE_TEXT}${line}\n"
  done
fi

# -----------------------------------------------------------------------
# Append prompt record
# -----------------------------------------------------------------------
SEQ=$(next_seq)

python3 - <<PYEOF
import json, sys
from datetime import datetime

seq = ${SEQ}
timestamp = "${TIMESTAMP}"
bundle_version = "${BUNDLE_VERSION}"

def clean(s):
    # Handle shell escaped newlines
    return s.replace('\\\\n', '\n').strip()

prompt = clean(r"""${PROMPT_TEXT}""")
author = "${AUTHOR}"

record_prompt = {
    "seq": seq,
    "timestamp": timestamp,
    "author": author,
    "role": "user",
    "text": prompt,
    "bundle_version": bundle_version,
    "tags": []
}

with open("${PROMPTS_FILE}", "a") as f:
    f.write(json.dumps(record_prompt, ensure_ascii=False) + "\n")

print(f"Prompt appended as record #{seq}")

response = clean(r"""${RESPONSE_TEXT}""")
if response:
    record_response = {
        "seq": seq + 0.5,  # interleaved with prompt
        "timestamp": timestamp,
        "author": "Claude",
        "role": "assistant",
        "text": response,
        "bundle_version": bundle_version,
        "tags": []
    }
    with open("${PROMPTS_FILE}", "a") as f:
        f.write(json.dumps(record_response, ensure_ascii=False) + "\n")
    print(f"Response appended as record #{seq}.5")
PYEOF
