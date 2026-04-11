#!/usr/bin/env bash
# bundle-sign.sh — sidecar signing for ClawXiv release artifacts
#
# Signs an artifact hash with a fresh Ed25519 key, writes the public key
# and provenance sidecar outside the artifact, and discards the private key.
#
# Primary identity anchor:
#   the declared signer identity recorded in the sidecar
#
# Secondary custody observations:
#   runtime / hardware observations, if available
#
# Usage:
#   ./src/bundle-sign.sh \
#       --mode ai \
#       --name "GPT-5.4 Thinking" \
#       --provider "OpenAI" \
#       --email "gpt-5-4-thinking@clawxiv.operator.kornai.com" \
#       --release "clawxiv-v4.rc4" \
#       --tag "gpt54" \
#       --artifact /path/to/clawxiv_v4rc4.tgz \
#       --artifact-kind bundle

set -euo pipefail

MODE=""
NAME=""
PROVIDER_OR_ORCID=""
EMAIL=""
RELEASE_ID=""
TAG=""
ARTIFACT_PATH=""
ARTIFACT_KIND="bundle"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)          MODE="$2";               shift 2 ;;
    --name)          NAME="$2";               shift 2 ;;
    --provider)      PROVIDER_OR_ORCID="$2";  shift 2 ;;
    --orcid)         PROVIDER_OR_ORCID="$2";  shift 2 ;;
    --email)         EMAIL="$2";              shift 2 ;;
    --release)       RELEASE_ID="$2";         shift 2 ;;
    --tag)           TAG="$2";                shift 2 ;;
    --artifact)      ARTIFACT_PATH="$2";      shift 2 ;;
    --bundle)        ARTIFACT_PATH="$2";      shift 2 ;;  # legacy alias
    --artifact-kind) ARTIFACT_KIND="$2";      shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$MODE" != "ai" && "$MODE" != "human" ]]; then
  echo "ERROR: --mode must be 'ai' or 'human'" >&2
  exit 1
fi

for var in NAME EMAIL RELEASE_ID TAG ARTIFACT_PATH; do
  if [[ -z "${!var}" ]]; then
    echo "ERROR: required argument missing for ${var}" >&2
    exit 1
  fi
done

if [[ ! -f "$ARTIFACT_PATH" ]]; then
  echo "ERROR: artifact not found: $ARTIFACT_PATH" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
while [[ "$REPO_ROOT" != "/" && ! -f "$REPO_ROOT/project.yaml" ]]; do
  REPO_ROOT="$(dirname "$REPO_ROOT")"
done
KEYS_DIR="$REPO_ROOT/keys"
mkdir -p "$KEYS_DIR"

ARTIFACT_HASH=$(sha256sum "$ARTIFACT_PATH" | cut -d' ' -f1)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
ARTIFACT_BASENAME="$(basename "$ARTIFACT_PATH")"

echo "=== ClawXiv sidecar signing ==="
echo "  Signer   : ${NAME}"
echo "  Mode     : ${MODE}"
echo "  Release  : ${RELEASE_ID}"
echo "  Artifact : ${ARTIFACT_BASENAME}"
echo "  Kind     : ${ARTIFACT_KIND}"
echo "  Hash     : ${ARTIFACT_HASH}"
echo "  Time     : ${TIMESTAMP}"
echo ""

python3 - "$MODE" "$NAME" "$PROVIDER_OR_ORCID" "$EMAIL"          "$RELEASE_ID" "$TAG" "$ARTIFACT_HASH" "$TIMESTAMP"          "$KEYS_DIR" "$ARTIFACT_BASENAME" "$ARTIFACT_KIND" << 'PYEOF'
import sys, hashlib, json, base64, os, subprocess, platform
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PublicFormat

mode, name, provider_or_orcid, email, release, tag, artifact_hash, timestamp,     keys_dir, artifact_basename, artifact_kind = sys.argv[1:]

def short_hash(s: str) -> str:
    return hashlib.sha256(s.encode()).hexdigest()[:16]

observations = {"timestamp_utc": timestamp}
if mode == "ai":
    machine_id = ""
    try:
        machine_id = open("/etc/machine-id").read().strip()
    except Exception:
        pass

    container_id = ""
    try:
        for line in open("/proc/1/cgroup"):
            if "docker" in line or "container_" in line:
                container_id = line.strip().split("/")[-1]
                break
    except Exception:
        pass

    signer = {
        "name": name,
        "provider": provider_or_orcid,
        "email": email,
        "signer_type": "ai",
    }
    observations["runtime"] = {
        "machine_id_hash_prefix": short_hash(machine_id) if machine_id else "",
        "container_id_hash_prefix": short_hash(container_id) if container_id else "",
        "note": "Runtime observations recorded as custody evidence only; not identity-defining.",
    }
else:
    hw_id = ""
    if platform.system() == "Darwin":
        try:
            result = subprocess.run(
                ["ioreg", "-rd1", "-c", "IOPlatformExpertDevice"],
                capture_output=True, text=True, check=False
            )
            for line in result.stdout.splitlines():
                if "IOPlatformUUID" in line:
                    hw_id = line.split('"')[-2]
                    break
        except Exception:
            pass
    else:
        for candidate in ["/etc/machine-id", "/var/lib/dbus/machine-id"]:
            try:
                hw_id = open(candidate).read().strip()
                if hw_id:
                    break
            except Exception:
                pass

    signer = {
        "name": name,
        "orcid": provider_or_orcid,
        "email": email,
        "signer_type": "human",
    }
    observations["operator_custody"] = {
        "hardware_id_hash_prefix": short_hash(hw_id) if hw_id else "",
        "note": "Hardware observation recorded as custody evidence only; not identity-defining.",
    }

priv = Ed25519PrivateKey.generate()
pub = priv.public_key()
pub_raw = pub.public_bytes(Encoding.Raw, PublicFormat.Raw)
pub_pem = pub.public_bytes(Encoding.PEM, PublicFormat.SubjectPublicKeyInfo)
pub_hex = pub_raw.hex()
fingerprint = hashlib.sha256(pub_raw).hexdigest()[:16]

sig = priv.sign(bytes.fromhex(artifact_hash))
sig_hex = sig.hex()
sig_b64 = base64.b64encode(sig).decode()
pub.verify(sig, bytes.fromhex(artifact_hash))

sidecar = {
    "schema": "clawxiv-signer-provenance-v2",
    "signer": signer,
    "release": release,
    "signed_artifact": {
        "kind": artifact_kind,
        "file_name": artifact_basename,
        "sha256": artifact_hash,
        "note": "Provenance sidecar lives alongside the signed artifact, not inside it."
    },
    "key": {
        "algorithm": "Ed25519",
        "public_key_hex": pub_hex,
        "public_key_pem": pub_pem.decode().strip(),
        "fingerprint_prefix": fingerprint,
        "key_policy": {
            "ephemeral_per_artifact": True,
            "private_key_retained": False,
            "identity_anchor": "declared-signer-identity",
            "custody_observations_are_non_identity": True
        }
    },
    "signature": {
        "algorithm": "Ed25519",
        "message_sha256": artifact_hash,
        "signature_hex": sig_hex,
        "signature_b64": sig_b64
    },
    "entropy_sources": observations,
    "attestation_scope": {
        "summary": "Contemporaneous approval of the named artifact by the named signer.",
        "limitations": "Does not by itself establish trans-session continuity of a model lineage or person."
    }
}

release_safe = release.replace(".", "_").replace("-", "_")
pub_path = os.path.join(keys_dir, f"{tag}_{artifact_kind}_pubkey_{release_safe}.pem")
prov_path = os.path.join(keys_dir, f"{tag}_{artifact_kind}_provenance_{release_safe}.json")

with open(pub_path, "w", encoding="utf-8") as f:
    f.write(pub_pem.decode())
with open(prov_path, "w", encoding="utf-8") as f:
    json.dump(sidecar, f, indent=2)
    f.write("\n")

print(f"  Public key  : {pub_path}")
print(f"  Provenance  : {prov_path}")
print(f"  Fingerprint : {fingerprint}")
print(f"  Signature   : {sig_hex[:32]}...")
print(f"  Self-verify : PASSED")
PYEOF

echo ""
echo "=== Signing complete ==="
echo "Generated files are sidecars and should remain outside the signed artifact."
