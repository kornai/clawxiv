# ClawXiv toolchain — v2 working scripts

This bundle contains the current working scripts for the ClawXiv
archival system for human–AI collaborative research papers.

## Files

| File | Purpose |
|------|---------|
| `clawxiv.py` | Core Python library: keygen, bundle-create, bundle-verify, transparency log, classification |
| `clawxiv_import.py` | Interactive import of legacy/seed papers into normalized project directories |
| `bundle-create.sh` | Compile PDF + create signed local bundle + write back bundle_root |
| `bundle-push.sh` | Publish local bundle to IPFS + GitHub (irreversible) |

## Workflow

```
legacy working state
        │
        ▼  clawxiv_import.py
normalized project state   (<project-dir>/src/, project.yaml, provenance.json)
        │
        ▼  bundle-create.sh
signed local bundle        (<project-dir>/out/bundle.zip)
        │
        ▼  bundle-push.sh          ← deliberate, irreversible
public archive             (IPFS + GitHub + optional arXiv/lebadus)
```

`bundle-create` is local and safe to run after every session.
`bundle-push` is the publication step and should only be run when
the work is ready to be public.

## Quick start

### 1. Generate keys (once per author identity)

```bash
mkdir -p ~/.clawxiv/keys
python3 clawxiv.py keygen \
    --private-key ~/.clawxiv/keys/author.priv.pem \
    --public-key  ~/.clawxiv/keys/author.pub.pem
chmod 600 ~/.clawxiv/keys/author.priv.pem
```

### 2. Import a paper seed

```bash
python3 clawxiv_import.py
```

Asks interactively for: title/slug, project location, source files
(directory, individual files, conversation URL, or plain text file),
authors, AI contributors, status, venue.

Produces:
```
<parent>/<slug>/
    src/            source files
    project.yaml    canonical metadata
    project.tex     rendered TeX view
    provenance.json paper-level provenance
    import.log      full session log (shareable with collaborators)
    out/            (empty until bundle-create)
```

### 3. Create a local bundle

```bash
./bundle-create.sh <project-dir>
# or, if PDF already compiled:
./bundle-create.sh <project-dir> --skip-compile
```

Produces `<project-dir>/out/bundle.zip` and writes the `bundle_root`
hash back into `project.yaml` and `provenance.json`.

### 4. Publish (when ready)

```bash
./bundle-push.sh <project-dir>
```

Requires: `ipfs` daemon running, git repo with push access configured.
Use `--skip-ipfs` or `--skip-github` to publish partially.
Use `--dry-run` to preview without executing.

## Project directory structure

```
<project-dir>/
    src/
        <root>.tex          main LaTeX file
        <root>.bib          bibliography
        *.c / *.py / ...    code, data, figures
        conversation_seed.md  (if imported from conversation URL)
    project.yaml            CANONICAL metadata — edit this
    project.tex             rendered TeX view (generated from project.yaml)
    provenance.json         paper-level provenance
    import.log              import session log
    out/
        bundle.zip          signed bundle (after bundle-create)
        clawxiv_log.jsonl   local event log
        <root>.pdf          compiled PDF
```

## Registry (top-level, optional)

If multiple papers live under a common parent directory:
```
<parent>/
    registry.yaml       index of all papers
    registry.tex        rendered catalog (\input{<slug>/project.tex})
    <slug-1>/
    <slug-2>/
    ...
```

## Design notes

- **YAML is canonical**: `project.yaml` is the authoritative metadata
  record. `project.tex` is a rendered view and can be regenerated.
- **Provenance is paper-level**: no utterance-level logging. The
  conversation URL(s) recorded in `project.yaml` and `provenance.json`
  are the provenance record. `import.log` provides session continuity
  for collaborators (human and AI).
- **Bundle_root travels with the bundle**: absolute paths are never
  embedded. The slug is the only path element in the bundle.
- **bundle-create is idempotent**: running it multiple times produces
  different hashes (timestamp in manifest) but each is a valid snapshot.
  Only the pushed bundles enter the public transparency log.

## Acknowledgements

The ClawXiv system was designed by Andr\'as Kornai with Claude Sonnet 4.6
(Anthropic) and GPT-4.5 (OpenAI) as co-designers.  The three-state
pipeline (legacy → normalized → published), the YAML-canonical metadata
design, and the separation of bundle-create from bundle-push were
contributions from the joint human–AI design sessions.  See the ClawXiv
whitepaper (v2) for the full system description and motivation.

Conversation archive: https://claude.ai/share/3378b2a0-16b0-494e-b603-bffbef5e1ce5
