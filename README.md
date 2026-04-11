# ClawXiv

**A signed archival workflow and distributed publication architecture
for human–AI collaborative research.**

ClawXiv is a framework and toolchain for converting human–AI
co-research sessions into durable, cryptographically signed, publicly
archived artifacts. It is designed around a **two-foot publication
model**: an arXiv (or equivalent) submission as the human-legible
foot, and a decentralized content-addressed bundle as the
machine-readable foot.

## Repository contents

| Path | Description |
|------|-------------|
| `src/clawxiv_whitepaper_v4.tex` | Whitepaper source (v4 release-candidate line) |
| `src/clawxiv_whitepaper_arxiv.tex` | arXiv-facing source variant |
| `src/clawxiv.sty` | LaTeX provenance typesetting macros |
| `src/clawxiv.py` | Core Python toolchain |
| `src/clawxiv_import.py` | Seed-to-project import |
| `src/bundle-create.sh` | Local bundle assembly for normalized projects |
| `src/bundle-push.sh` | Publication to Swarm / IPFS / GitHub |
| `src/bundle-sign.sh` | Sidecar signing for bundles and other release artifacts |
| `src/verify_sig.py` | Verify legacy and current provenance sidecars |
| `src/ai_keygen.sh` | Deprecated historical script retained for provenance |
| `DESIGN_HISTORY.md` | Append-only design-history and provenance narrative |
| `keys/` | Public keys and provenance sidecars only (never private keys) |
| `project.yaml` | Canonical project metadata |
| `Makefile` | Build system entry points |
| `configure` | Dependency autodetection |

## Quick start

```bash
git clone https://github.com/kornai/clawxiv
cd clawxiv
./configure
make help
```

See `src/clawxiv_whitepaper_v4.pdf` for the framework paper and
`DESIGN_HISTORY.md` for the signing-architecture evolution.

## Signing note

As of `v4.rc4`, ClawXiv treats signer identity as an explicit claim
recorded in a provenance sidecar. Hardware or runtime observations may
be retained as secondary custody evidence, but they are not treated as
the primary identity of an AI co-author.

## Published artifact

A previously published whitepaper bundle exists at content hash:

`e7acc972f1a142903dc22f1bdc5c78cec3ca9529754d843cb23fe7c8eb0e9176`

## Authors

- András Kornai (BME / SZTAKI) — responsible author
- GPT-5.2 Thinking (OpenAI) — historical AI co-author
- Claude Sonnet 4.6 (Anthropic) — AI co-author
- GPT-5.4 Thinking (OpenAI) — AI co-author

Historical attributions are preserved on a best-effort basis. Current
release-candidate signatures attest only to presently accessible signers.

## License

Public domain dedication (CC0) unless otherwise noted in individual
bundle manifests.
