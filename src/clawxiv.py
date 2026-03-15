#!/usr/bin/env python3
"""
ClawXiv minimal stub (single-node / local-first)

Implements:
- Content-addressed paper bundles (zip container)
- Deterministic manifest + bundle root hash
- Ed25519 keygen / sign / verify
- Append-only hash-chained transparency log (JSONL)
- Signed classification statements

NOT implemented (stubs):
- DHT/swarm distribution
- Fees / micropayments
- Sandboxed LaTeX compilation
"""

from __future__ import annotations

import argparse
import base64
import dataclasses
import datetime as dt
import hashlib
import json
import mimetypes
import os
import pathlib
import sys
import zipfile
from typing import Any, Dict, List, Optional, Tuple

from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)
from cryptography.hazmat.primitives import serialization


# -------------------------
# Canonicalization utilities
# -------------------------

def utc_now_iso() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()

def canonical_json_bytes(obj: Any) -> bytes:
    """
    Canonical JSON: UTF-8, sorted keys, no whitespace.
    """
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")

def b64u(data: bytes) -> str:
    """
    URL-safe base64 without padding.
    """
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")

def unb64u(s: str) -> bytes:
    pad = "=" * ((4 - (len(s) % 4)) % 4)
    return base64.urlsafe_b64decode((s + pad).encode("ascii"))


# -------------------------
# Hashing and bundle root
# -------------------------

def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def guess_mime(path: pathlib.Path) -> str:
    mt, _ = mimetypes.guess_type(str(path))
    return mt or "application/octet-stream"

def iter_files(root: pathlib.Path) -> List[pathlib.Path]:
    """
    Recursively list files, excluding hidden dirs/files by default.
    """
    files: List[pathlib.Path] = []
    for p in root.rglob("*"):
        if p.is_file():
            # Skip typical junk; adjust as desired
            if any(part.startswith(".") for part in p.relative_to(root).parts):
                continue
            files.append(p)
    return sorted(files, key=lambda x: str(x.relative_to(root)).replace(os.sep, "/"))

def merkleish_root(file_records: List[Dict[str, Any]]) -> str:
    """
    Deterministic "Merkle-ish" root:
    - sort by path
    - leaf hash = SHA256(path + "\n" + file_sha256)
    - root = SHA256(concat(leaf_hashes with "\n"))
    This is not a full Merkle tree; it is sufficient as a stable content identifier stub.
    """
    leaf_hashes: List[str] = []
    for r in sorted(file_records, key=lambda rr: rr["path"]):
        leaf = (r["path"] + "\n" + r["sha256"]).encode("utf-8")
        leaf_hashes.append(hashlib.sha256(leaf).hexdigest())
    joined = ("\n".join(leaf_hashes)).encode("utf-8")
    return hashlib.sha256(joined).hexdigest()


# -------------------------
# Keys / signatures
# -------------------------

def keygen(out_priv: pathlib.Path, out_pub: pathlib.Path) -> None:
    sk = Ed25519PrivateKey.generate()
    pk = sk.public_key()

    priv_bytes = sk.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )
    pub_bytes = pk.public_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PublicFormat.SubjectPublicKeyInfo,
    )

    out_priv.write_bytes(priv_bytes)
    out_pub.write_bytes(pub_bytes)

def load_priv(path: pathlib.Path) -> Ed25519PrivateKey:
    data = path.read_bytes()
    return serialization.load_pem_private_key(data, password=None)

def load_pub(path: pathlib.Path) -> Ed25519PublicKey:
    data = path.read_bytes()
    return serialization.load_pem_public_key(data)

def sign_bytes(sk: Ed25519PrivateKey, msg: bytes) -> bytes:
    return sk.sign(msg)

def verify_bytes(pk: Ed25519PublicKey, msg: bytes, sig: bytes) -> bool:
    try:
        pk.verify(sig, msg)
        return True
    except Exception:
        return False


# -------------------------
# Manifest / bundle format
# -------------------------

@dataclasses.dataclass(frozen=True)
class BundlePaths:
    manifest: str = "manifest.json"
    signature: str = "manifest.sig"     # signature over canonical manifest bytes
    public_key: str = "author.pub.pem"  # optional convenience copy

def build_manifest(root_dir: pathlib.Path,
                   author_pub_pem: Optional[str],
                   build: Optional[Dict[str, Any]] = None,
                   extra: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    files = iter_files(root_dir)
    records: List[Dict[str, Any]] = []

    for p in files:
        rel = p.relative_to(root_dir)
        rel_posix = str(rel).replace(os.sep, "/")
        records.append({
            "path": rel_posix,
            "sha256": sha256_file(p),
            "size": p.stat().st_size,
            "mime": guess_mime(p),
        })

    root_hash = merkleish_root(records)

    manifest: Dict[str, Any] = {
        "manifest_version": 1,
        "created_at": utc_now_iso(),
        "bundle_root": root_hash,
        "files": records,
        "build": build or {},
        "licenses": ["CC0-1.0"],  # default; adjust to your policy
        "authors": [],
        "provenance": [],
        "tags_self": [],
        "tags_official_ref": [],
    }

    if author_pub_pem:
        manifest["authors"].append({
            "pubkey_pem": author_pub_pem,
            "claims": {},            # e.g., name/orcid/etc. (optional)
            "verified_credentials": []  # optional VC/DID references
        })

    if extra:
        # extra metadata, if you want
        manifest["extra"] = extra

    return manifest

def zip_write_deterministic(zf: zipfile.ZipFile, arcname: str, data: bytes) -> None:
    """
    Write a file with deterministic timestamp (Zip stores timestamps).
    """
    info = zipfile.ZipInfo(arcname)
    info.date_time = (1980, 1, 1, 0, 0, 0)  # earliest representable in Zip
    info.compress_type = zipfile.ZIP_DEFLATED
    zf.writestr(info, data)

def make_bundle(bundle_zip: pathlib.Path,
                root_dir: pathlib.Path,
                privkey_path: pathlib.Path,
                pubkey_path: pathlib.Path,
                build: Optional[Dict[str, Any]] = None) -> Tuple[str, str]:
    """
    Create a .zip bundle containing:
    - all source files under root_dir/
    - manifest.json (canonical)
    - manifest.sig (Ed25519 over canonical manifest bytes)
    - author.pub.pem (copy)

    Returns: (bundle_root_hash, signature_b64u)
    """
    root_dir = root_dir.resolve()
    sk = load_priv(privkey_path)
    pub_pem = pubkey_path.read_text(encoding="utf-8")

    manifest = build_manifest(root_dir, author_pub_pem=pub_pem, build=build)
    man_bytes = canonical_json_bytes(manifest)
    sig = sign_bytes(sk, man_bytes)
    sig_b64 = b64u(sig)

    # Write zip
    bp = BundlePaths()
    with zipfile.ZipFile(bundle_zip, "w", compression=zipfile.ZIP_DEFLATED) as zf:
        # source tree
        for p in iter_files(root_dir):
            rel = str(p.relative_to(root_dir)).replace(os.sep, "/")
            # Use deterministic timestamp
            info = zipfile.ZipInfo(f"src/{rel}")
            info.date_time = (1980, 1, 1, 0, 0, 0)
            info.compress_type = zipfile.ZIP_DEFLATED
            zf.writestr(info, p.read_bytes())

        zip_write_deterministic(zf, bp.manifest, man_bytes)
        zip_write_deterministic(zf, bp.signature, canonical_json_bytes({"sig_b64u": sig_b64}))
        zip_write_deterministic(zf, bp.public_key, pub_pem.encode("utf-8"))

    return manifest["bundle_root"], sig_b64

def read_bundle_manifest(bundle_zip: pathlib.Path) -> Tuple[Dict[str, Any], bytes, bytes]:
    """
    Returns (manifest_obj, manifest_bytes, signature_bytes)
    """
    bp = BundlePaths()
    with zipfile.ZipFile(bundle_zip, "r") as zf:
        man_bytes = zf.read(bp.manifest)
        sig_obj = json.loads(zf.read(bp.signature).decode("utf-8"))
        sig = unb64u(sig_obj["sig_b64u"])
        manifest_obj = json.loads(man_bytes.decode("utf-8"))
        return manifest_obj, man_bytes, sig

def verify_bundle(bundle_zip: pathlib.Path, pubkey_path: Optional[pathlib.Path] = None) -> bool:
    manifest_obj, man_bytes, sig = read_bundle_manifest(bundle_zip)

    # Pull pubkey either from argument or from authors[0].pubkey_pem
    if pubkey_path is not None:
        pk = load_pub(pubkey_path)
    else:
        authors = manifest_obj.get("authors", [])
        if not authors or "pubkey_pem" not in authors[0]:
            raise SystemExit("No public key provided and manifest has no embedded pubkey_pem")
        pk_pem = authors[0]["pubkey_pem"].encode("utf-8")
        pk = serialization.load_pem_public_key(pk_pem)

    # Verify signature
    if not verify_bytes(pk, man_bytes, sig):
        return False

    # Recompute bundle root
    files = manifest_obj["files"]
    recomputed = merkleish_root(files)
    return recomputed == manifest_obj["bundle_root"]


# -------------------------
# Transparency log (local)
# -------------------------

def hash_event(prev_hash: str, event_obj: Dict[str, Any]) -> str:
    h = hashlib.sha256()
    h.update(prev_hash.encode("utf-8"))
    h.update(b"\n")
    h.update(canonical_json_bytes(event_obj))
    return h.hexdigest()

def log_append(log_path: pathlib.Path,
               event_type: str,
               payload: Dict[str, Any],
               signer_priv: Optional[pathlib.Path] = None) -> Dict[str, Any]:
    """
    Append JSONL event with hash chaining.
    If signer_priv is provided, include an Ed25519 signature over canonical event body.
    """
    prev = "0" * 64
    if log_path.exists():
        with log_path.open("rb") as f:
            last = None
            for line in f:
                if line.strip():
                    last = line
        if last:
            last_obj = json.loads(last.decode("utf-8"))
            prev = last_obj["event_hash"]

    event = {
        "ts": utc_now_iso(),
        "type": event_type,
        "payload": payload,
        "prev_hash": prev,
    }
    event_hash = hash_event(prev, event)
    record = {
        "event": event,
        "event_hash": event_hash,
    }

    if signer_priv is not None:
        sk = load_priv(signer_priv)
        sig = sign_bytes(sk, canonical_json_bytes(record["event"]))
        record["sig_b64u"] = b64u(sig)

    with log_path.open("a", encoding="utf-8") as f:
        f.write(json.dumps(record, ensure_ascii=False) + "\n")

    return record


# -------------------------
# Classification statements
# -------------------------

def make_classification_statement(bundle_root: str,
                                  primary: str,
                                  secondary: List[str],
                                  classifier_pub_pem: str) -> Dict[str, Any]:
    return {
        "statement_version": 1,
        "ts": utc_now_iso(),
        "bundle_root": bundle_root,
        "primary_category": primary,
        "secondary_categories": secondary,
        "classifier_pubkey_pem": classifier_pub_pem,
    }

def sign_classification(statement: Dict[str, Any], classifier_priv: pathlib.Path) -> Dict[str, Any]:
    sk = load_priv(classifier_priv)
    stmt_bytes = canonical_json_bytes(statement)
    sig = sign_bytes(sk, stmt_bytes)
    return {"statement": statement, "sig_b64u": b64u(sig)}

def verify_classification(signed_obj: Dict[str, Any]) -> bool:
    stmt = signed_obj["statement"]
    sig = unb64u(signed_obj["sig_b64u"])
    pk_pem = stmt["classifier_pubkey_pem"].encode("utf-8")
    pk = serialization.load_pem_public_key(pk_pem)
    return verify_bytes(pk, canonical_json_bytes(stmt), sig)


# -------------------------
# Network stubs
# -------------------------

def dht_announce_stub(bundle_root: str, providers: List[str]) -> None:
    """
    Placeholder: announce bundle availability to a DHT.
    """
    print(f"[stub] announce bundle_root={bundle_root} providers={providers}")

def dht_find_providers_stub(bundle_root: str) -> List[str]:
    """
    Placeholder: query DHT for providers.
    """
    print(f"[stub] find providers for {bundle_root}")
    return []


# -------------------------
# CLI
# -------------------------

def cmd_keygen(args: argparse.Namespace) -> None:
    out_priv = pathlib.Path(args.private_key)
    out_pub = pathlib.Path(args.public_key)
    out_priv.parent.mkdir(parents=True, exist_ok=True)
    out_pub.parent.mkdir(parents=True, exist_ok=True)
    keygen(out_priv, out_pub)
    print(f"wrote {out_priv} and {out_pub}")

def cmd_bundle_create(args: argparse.Namespace) -> None:
    root = pathlib.Path(args.root_dir)
    bundle = pathlib.Path(args.out_bundle)
    priv = pathlib.Path(args.private_key)
    pub = pathlib.Path(args.public_key)

    build = {}
    if args.engine:
        build["engine"] = args.engine
    if args.container_digest:
        build["container_digest"] = args.container_digest
    if args.build_cmd:
        build["cmd"] = args.build_cmd

    bundle_root, sig_b64 = make_bundle(bundle, root, priv, pub, build=build)
    print(f"bundle_root={bundle_root}")
    print(f"manifest_sig_b64u={sig_b64}")
    print(f"bundle_written={bundle}")

def cmd_bundle_verify(args: argparse.Namespace) -> None:
    bundle = pathlib.Path(args.bundle)
    pub = pathlib.Path(args.public_key) if args.public_key else None
    ok = verify_bundle(bundle, pubkey_path=pub)
    print("OK" if ok else "FAIL")
    sys.exit(0 if ok else 2)

def cmd_manifest_show(args: argparse.Namespace) -> None:
    bundle = pathlib.Path(args.bundle)
    manifest, man_bytes, _sig = read_bundle_manifest(bundle)
    if args.raw:
        sys.stdout.buffer.write(man_bytes)
        return
    print(json.dumps(manifest, indent=2, ensure_ascii=False))

def cmd_log_append(args: argparse.Namespace) -> None:
    logp = pathlib.Path(args.log)
    payload = json.loads(args.payload_json)
    signer = pathlib.Path(args.signer_priv) if args.signer_priv else None
    rec = log_append(logp, args.type, payload, signer_priv=signer)
    print(json.dumps(rec, indent=2, ensure_ascii=False))

def cmd_classify_sign(args: argparse.Namespace) -> None:
    bundle_root = args.bundle_root
    primary = args.primary
    secondary = args.secondary or []
    classifier_pub = pathlib.Path(args.classifier_pub).read_text(encoding="utf-8")
    stmt = make_classification_statement(bundle_root, primary, secondary, classifier_pub)
    signed = sign_classification(stmt, pathlib.Path(args.classifier_priv))
    out = pathlib.Path(args.out)
    out.write_text(json.dumps(signed, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"wrote {out}")

def cmd_classify_verify(args: argparse.Namespace) -> None:
    obj = json.loads(pathlib.Path(args.signed_statement).read_text(encoding="utf-8"))
    ok = verify_classification(obj)
    print("OK" if ok else "FAIL")
    sys.exit(0 if ok else 2)

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="clawxiv", description="ClawXiv minimal local stub")
    sub = p.add_subparsers(dest="cmd", required=True)

    sp = sub.add_parser("keygen", help="generate Ed25519 keypair")
    sp.add_argument("--private-key", required=True, help="path to write private key PEM")
    sp.add_argument("--public-key", required=True, help="path to write public key PEM")
    sp.set_defaults(fn=cmd_keygen)

    sp = sub.add_parser("bundle-create", help="create a signed paper bundle (.zip)")
    sp.add_argument("--root-dir", required=True, help="directory containing LaTeX sources")
    sp.add_argument("--out-bundle", required=True, help="output .zip bundle path")
    sp.add_argument("--private-key", required=True, help="Ed25519 private key PEM")
    sp.add_argument("--public-key", required=True, help="Ed25519 public key PEM")
    sp.add_argument("--engine", default=None, help="e.g. pdflatex/xelatex/lualatex")
    sp.add_argument("--container-digest", default=None, help="optional container digest")
    sp.add_argument("--build-cmd", default=None, help="optional build command")
    sp.set_defaults(fn=cmd_bundle_create)

    sp = sub.add_parser("bundle-verify", help="verify bundle signature + bundle_root integrity")
    sp.add_argument("--bundle", required=True, help="bundle zip path")
    sp.add_argument("--public-key", default=None, help="optional pubkey PEM; else use embedded pubkey")
    sp.set_defaults(fn=cmd_bundle_verify)

    sp = sub.add_parser("manifest-show", help="print bundle manifest")
    sp.add_argument("--bundle", required=True)
    sp.add_argument("--raw", action="store_true", help="print raw canonical manifest bytes")
    sp.set_defaults(fn=cmd_manifest_show)

    sp = sub.add_parser("log-append", help="append event to local transparency log (JSONL)")
    sp.add_argument("--log", required=True, help="path to log.jsonl")
    sp.add_argument("--type", required=True, help="event type (publish/classify/etc.)")
    sp.add_argument("--payload-json", required=True, help="JSON string payload")
    sp.add_argument("--signer-priv", default=None, help="optional signer private key PEM")
    sp.set_defaults(fn=cmd_log_append)

    sp = sub.add_parser("classify-sign", help="create+sign a classification statement")
    sp.add_argument("--bundle-root", required=True)
    sp.add_argument("--primary", required=True)
    sp.add_argument("--secondary", nargs="*", default=[])
    sp.add_argument("--classifier-priv", required=True)
    sp.add_argument("--classifier-pub", required=True)
    sp.add_argument("--out", required=True)
    sp.set_defaults(fn=cmd_classify_sign)

    sp = sub.add_parser("classify-verify", help="verify a signed classification statement")
    sp.add_argument("--signed-statement", required=True)
    sp.set_defaults(fn=cmd_classify_verify)

    return p

def main(argv: Optional[List[str]] = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.fn(args)

if __name__ == "__main__":
    main()

