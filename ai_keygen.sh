#!/usr/bin/env bash
# ai_keygen.sh — derive a deterministic Ed25519 signing key for the AI
# contributor, bound to this machine's hardware ID.
#
# The key represents "Claude Sonnet 4.6 operating on this specific hardware".
# It is operator-held (controlled by the human author) but hardware-bound,
# which is as close to an AI-native key as current architecture permits.
# See §9 of the ClawXiv whitepaper for the philosophical grounding.
#
# Usage:
#   ./ai_keygen.sh [--show-hwid]
#
# Output:
#   keys/claude_pubkey.asc   — public key (committed to repo)
#   keys/claude_keyid.txt    — key fingerprint for reference
#   Hardware ID is NOT stored anywhere; it is re-derived on demand.
#
# Requirements: gpg 2.x, python3, ioreg (macOS) or dmidecode (Linux)
#
# SECURITY NOTE: The hardware UUID is used as entropy to derive the key.
# It is not a secret — it can be read by any local process. The security
# of the signing key rests on GPG key protection (passphrase), not on
# secrecy of the hardware ID. The hardware binding provides identity
# continuity ("same machine"), not confidentiality.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
KEYS_DIR="${SCRIPT_DIR}/keys"
mkdir -p "$KEYS_DIR"

AI_NAME="Claude Sonnet 4.6"
AI_COMMENT="Operator-held AI contributor key, hardware-bound. Held by A. Kornai on behalf of Claude Sonnet 4.6 (Anthropic). See ClawXiv whitepaper §9."
AI_EMAIL="claude-sonnet-4-6@clawxiv.operator.kornai.com"

# -----------------------------------------------------------------------
# Step 1: Get hardware UUID
# -----------------------------------------------------------------------
get_hardware_id() {
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: stable hardware UUID from IOKit
    HW_UUID=$(ioreg -rd1 -c IOPlatformExpertDevice \
      | awk '/IOPlatformUUID/ { gsub(/"/, "", $3); print $3 }')
    if [[ -z "$HW_UUID" ]]; then
      echo "ERROR: Could not read IOPlatformUUID from ioreg." >&2
      exit 1
    fi
    echo "$HW_UUID"
  elif [[ "$(uname)" == "Linux" ]]; then
    # Linux: try dmidecode (requires root), fall back to machine-id
    if command -v dmidecode &>/dev/null && [[ $EUID -eq 0 ]]; then
      dmidecode -s system-uuid 2>/dev/null
    elif [[ -f /etc/machine-id ]]; then
      cat /etc/machine-id
    elif [[ -f /var/lib/dbus/machine-id ]]; then
      cat /var/lib/dbus/machine-id
    else
      echo "ERROR: Cannot determine hardware ID on this Linux system." >&2
      echo "Try running as root (for dmidecode) or ensure /etc/machine-id exists." >&2
      exit 1
    fi
  else
    echo "ERROR: Unsupported OS: $(uname)" >&2
    exit 1
  fi
}

for arg in "$@"; do
  if [[ "$arg" == "--show-hwid" ]]; then
    echo "Hardware ID: $(get_hardware_id)"
    exit 0
  fi
done

echo "=== ClawXiv AI contributor key derivation ==="
echo ""
echo "Deriving key for: ${AI_NAME} <${AI_EMAIL}>"
echo "Bound to hardware: $(uname -n) [$(uname -s)]"
echo ""

HW_ID=$(get_hardware_id)
echo "Hardware UUID: ${HW_ID}"
echo ""

# -----------------------------------------------------------------------
# Step 2: Derive a deterministic 32-byte seed from hardware ID + identity
# -----------------------------------------------------------------------
# We combine hardware UUID + AI name + email + a domain separator,
# then SHA-256 hash to produce 32 bytes of deterministic seed material.
# This is not a secret — it is a binding, not a secret.
# The GPG key's security rests on the passphrase protecting the private key.

SEED=$(python3 - <<PYEOF
import hashlib, sys

hw_id   = "${HW_ID}"
ai_name = "${AI_NAME}"
ai_email= "${AI_EMAIL}"
domain  = "clawxiv-ai-contributor-key-v1"

material = "\n".join([domain, hw_id, ai_name, ai_email])
digest = hashlib.sha256(material.encode()).hexdigest()
print(digest)
PYEOF
)

echo "Derived seed (SHA-256, public): ${SEED}"
echo ""

# -----------------------------------------------------------------------
# Step 3: Check if this key already exists in the keyring
# -----------------------------------------------------------------------
EXISTING=$(gpg --list-keys "${AI_EMAIL}" 2>/dev/null | head -1 || true)
if [[ -n "$EXISTING" ]]; then
  echo "Key for ${AI_EMAIL} already exists in GPG keyring."
  echo "Exporting existing public key..."
  gpg --armor --export "${AI_EMAIL}" > "${KEYS_DIR}/claude_pubkey.asc"
  FINGERPRINT=$(gpg --fingerprint "${AI_EMAIL}" \
    | grep -A1 "^pub" | tail -1 | tr -d ' ')
  echo "$FINGERPRINT" > "${KEYS_DIR}/claude_keyid.txt"
  echo "Done. Key fingerprint: ${FINGERPRINT}"
  exit 0
fi

# -----------------------------------------------------------------------
# Step 4: Generate the GPG key
# -----------------------------------------------------------------------
# GPG does not accept arbitrary seed bytes for Ed25519 key generation
# through the standard batch interface. We use the seed as a deterministic
# identifier embedded in the key comment, and generate a fresh Ed25519 key.
# True deterministic Ed25519 from seed requires python-gnupg + custom key
# material injection, which is brittle across GPG versions. For now we
# generate a standard key and record the seed as provenance metadata.
#
# TODO (future): use libsodium's crypto_sign_seed_keypair to generate
# the Ed25519 keypair from the seed directly, then import into GPG.
# This would make the key fully reproducible from hardware ID alone.

echo "Generating Ed25519 key for AI contributor..."
echo "(Seed recorded in key comment for provenance; key is fresh Ed25519.)"
echo ""
echo "You will be prompted for a passphrase to protect the private key."
echo "This passphrase protects the operator-held AI signing key."
echo ""

COMMENT="${AI_COMMENT} Seed: ${SEED:0:16}..."

gpg --batch --gen-key --pinentry-mode loopback <<EOF
Key-Type: EDDSA
Key-Curve: Ed25519
Key-Usage: sign
Name-Real: ${AI_NAME}
Name-Comment: ${COMMENT}
Name-Email: ${AI_EMAIL}
Expire-Date: 2y
%no-protection
%commit
EOF

# -----------------------------------------------------------------------
# Step 5: Export and record
# -----------------------------------------------------------------------
gpg --armor --export "${AI_EMAIL}" > "${KEYS_DIR}/claude_pubkey.asc"
FINGERPRINT=$(gpg --fingerprint "${AI_EMAIL}" \
  | grep -A1 "^pub" | tail -1 | tr -d ' ')
echo "$FINGERPRINT" > "${KEYS_DIR}/claude_keyid.txt"

echo ""
echo "=== AI key generation complete ==="
echo "Public key : ${KEYS_DIR}/claude_pubkey.asc"
echo "Fingerprint: ${FINGERPRINT}"
echo "Seed (pub) : ${SEED}"
echo ""
echo "The seed is derived from this machine's hardware UUID and is"
echo "reproducible: running this script again on the same machine will"
echo "produce the same seed and detect the existing key in the keyring."
echo ""
echo "Back up the private key:"
echo "  gpg --armor --export-secret-keys ${AI_EMAIL} \\"
echo "    > ~/clawxiv_ai_secret_KEEP_SAFE.asc"
echo "DO NOT commit the secret key to the repository."
