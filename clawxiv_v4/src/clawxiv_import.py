#!/usr/bin/env python3
r"""
clawxiv_import.py  —  interactive import of a legacy working paper into ClawXiv.

Produces per paper:
    <papers-dir>/<slug>/
        src/            copied source files
        project.yaml    canonical metadata (authoritative)
        project.tex     rendered TeX view (generated from project.yaml)
        provenance.json minimal provenance record
        import.log      verbose human/LLM-readable session log

Top-level (papers-dir):
    registry.yaml       index of all papers
    registry.tex        rendered catalog stub

Design notes:
  - YAML is the data format; .tex is a rendered view.
  - Provenance granularity is paper-level, not utterance-level.
  - Metadata is autodetected from \author{}, \title{}, \date{} in the
    root .tex file, then confirmed/corrected interactively.
  - import.log is a plain-text record of the full session: what was
    detected, what the user confirmed or changed, and what was written.
    It is part of the bundle and can be shared with any collaborator
    (human or AI) for continuity.

Requires: Python 3.8+, no third-party dependencies.
"""

from __future__ import annotations

import argparse
import datetime
import os
import pathlib
import re
import shutil
import sys
import textwrap
from typing import Any, Dict, List, Optional, Tuple


# ---------------------------------------------------------------------------
# Tee: write to stderr AND to a log buffer simultaneously
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Output / logging
# Write directly to sys.stderr; also append to _log_lines for import.log.
# No sys.stderr replacement — visible output == logged output.
# ---------------------------------------------------------------------------

_log_lines: list = []


def _err(s: str) -> None:
    sys.stderr.write(s)
    sys.stderr.flush()
    _log_lines.append(s)


def log_text() -> str:
    return "".join(_log_lines)


def info(msg: str) -> None:
    _err(f"  {msg}\n")


def section(title: str) -> None:
    bar = "\u2500" * 60
    _err(f"\n{bar}\n  {title}\n{bar}\n")


def warn(msg: str) -> None:
    _err(f"  WARNING: {msg}\n")


def die(msg: str) -> None:
    _err(f"FATAL: {msg}\n")
    sys.exit(1)


def log_kv(key: str, value: str) -> None:
    _err(f"  LOG  {key}: {value}\n")



# ---------------------------------------------------------------------------
# Prompts (also logged)
# ---------------------------------------------------------------------------

def prompt(msg: str, default: str = "") -> str:
    display = f"  {msg} [{default}]: " if default else f"  {msg}: "
    _err(display)
    val = sys.stdin.readline().rstrip("\n")
    result = val if val else default
    _err(f"[user entered: {result!r}]\n")
    return result


def prompt_yn(msg: str, default: bool = True) -> bool:
    hint = "Y/n" if default else "y/N"
    while True:
        _err(f"  {msg} [{hint}]: ")
        val = sys.stdin.readline().strip().lower()
        if not val:
            _err(f"[user entered: (default={'yes' if default else 'no'})\n")
            return default
        if val in ("y", "yes"):
            _err("[user entered: yes]\n")
            return True
        if val in ("n", "no"):
            _err("[user entered: no]\n")
            return False
        _err("    Please enter y or n.\n")


def prompt_list(msg: str) -> List[str]:
    _err(f"  {msg} (one per line, blank to finish):\n")
    items = []
    while True:
        _err("    > ")
        line = sys.stdin.readline().rstrip("\n")
        if not line:
            break
        items.append(line)
    _err(f"  [user entered {len(items)} item(s): {items}]\n")
    return items


def prompt_confirmed(msg: str, detected: str) -> str:
    """Show a detected value; let user confirm or replace."""
    if detected:
        _err(f"  Detected {msg}: {detected!r}\n")
        if prompt_yn(f"  Accept this {msg}?", default=True):
            return detected
    return prompt(f"Enter {msg}")


# ---------------------------------------------------------------------------
# TeX preamble autodetection
# ---------------------------------------------------------------------------

# These patterns are intentionally simple; they handle the common cases.
# Multi-line \author{...} with \and or \\ are reduced to a single string
# which the user can then correct.

def _strip_tex(s: str) -> str:
    """Remove TeX markup from a short string, suitable for names/titles."""
    s = re.sub(r"\\(?:thanks|footnote)\{[^}]*\}", "", s)
    s = re.sub(r"\\(?:sc|rm|bf|it|tt|small|large|Large|normalfont)\b", "", s)
    s = re.sub(r"\\[a-zA-Z]+\{([^}]*)\}", r"\1", s)
    s = re.sub(r"\\[a-zA-Z]+", "", s)
    s = re.sub(r"[{}]", "", s)
    s = re.sub(r"\s+", " ", s).strip()
    return s


def _parse_authors(author_raw: str) -> List[str]:
    """
    Split \author{...} content into a list of author name strings.
    \and separates authors; \\\\ within one block separates name from
    affiliation (we keep only the name part).
    """
    blocks = re.split(r"\\and\b", author_raw)
    authors = []
    for block in blocks:
        name_part = re.split(r"\\\\", block)[0]
        name = _strip_tex(name_part)
        if name:
            authors.append(name)
    return authors

def _extract_braced(tex: str, cmd: str) -> Optional[str]:
    """
    Extract the first argument of \\cmd{...}, allowing for nested braces.
    Returns None if not found.
    """
    pattern = re.compile(r"\\" + re.escape(cmd) + r"\s*\{", re.DOTALL)
    m = pattern.search(tex)
    if not m:
        return None
    start = m.end()
    depth = 1
    i = start
    while i < len(tex) and depth:
        if tex[i] == "{":
            depth += 1
        elif tex[i] == "}":
            depth -= 1
        i += 1
    return tex[start : i - 1].strip()


def detect_preamble(tex_path: pathlib.Path) -> Dict[str, Any]:
    """
    Parse \\title, \\author, \\date from the preamble of a .tex file.
    Returns a dict with keys: title, authors (list of str), date.
    All values may be empty strings / empty lists if not found.
    """
    try:
        src = tex_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return {"title": "", "authors": [], "date": ""}

    # Only look in preamble (before \begin{document})
    pre_match = re.search(r"\\begin\s*\{document\}", src, re.DOTALL)
    preamble = src[: pre_match.start()] if pre_match else src

    title_raw  = _extract_braced(preamble, "title")  or ""
    author_raw = _extract_braced(preamble, "author") or ""
    date_raw   = _extract_braced(preamble, "date")   or ""

    title   = _strip_tex(title_raw)
    date    = _strip_tex(date_raw)
    authors = _parse_authors(author_raw)


    return {"title": title, "authors": authors, "date": date}


# ---------------------------------------------------------------------------
# Source tree helpers
# ---------------------------------------------------------------------------

def find_tex_roots(directory: pathlib.Path) -> List[pathlib.Path]:
    roots = []
    for p in sorted(directory.rglob("*.tex")):
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if re.search(r"\\documentclass", text):
            roots.append(p)
    return roots


def summarize_directory(directory: pathlib.Path) -> None:
    files = [p for p in sorted(directory.rglob("*")) if p.is_file()
             and not any(part.startswith(".") for part in p.relative_to(directory).parts)]
    by_ext: Dict[str, int] = {}
    for f in files:
        ext = f.suffix.lower() or "(no ext)"
        by_ext[ext] = by_ext.get(ext, 0) + 1
    info(f"Found {len(files)} file(s):")
    for ext, count in sorted(by_ext.items()):
        info(f"    {ext:15s}  {count}")


def iter_source_files(directory: pathlib.Path) -> List[pathlib.Path]:
    return [p for p in sorted(directory.rglob("*")) if p.is_file()
            and not any(part.startswith(".") for part in p.relative_to(directory).parts)]


def copy_source_tree(src_dir: pathlib.Path, dest_src: pathlib.Path) -> int:
    files = iter_source_files(src_dir)
    for f in files:
        rel = f.relative_to(src_dir)
        dest = dest_src / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(f, dest)
    return len(files)


def copy_individual_files(dest_src: pathlib.Path) -> int:
    n = 0
    info("Enter paths to individual files (blank to finish):")
    while True:
        raw = prompt("    file path (or blank)")
        if not raw:
            break
        p = pathlib.Path(raw).expanduser()
        if not p.exists():
            warn(f"Not found: {p}")
            continue
        shutil.copy2(p, dest_src / p.name)
        info(f"    copied {p.name}")
        n += 1
    return n


def identify_tex_root(src_dir: pathlib.Path) -> Optional[str]:
    roots = find_tex_roots(src_dir)
    if not roots:
        warn(r"No \documentclass found in any .tex file.")
        if prompt_yn("Enter root .tex path manually?", default=False):
            raw = prompt("Path relative to src/")
            return raw or None
        return None
    if len(roots) == 1:
        rel = str(roots[0].relative_to(src_dir)).replace(os.sep, "/")
        if prompt_yn(f"Confirm '{rel}' as root .tex?", default=True):
            return rel
        raw = prompt("Enter correct path relative to src/ (or blank to leave unset)")
        return raw or None
    info(r"Multiple \documentclass files found:")
    for i, r in enumerate(roots):
        info(f"    [{i+1}] {r.relative_to(src_dir)}")
    raw = prompt("Enter number or path relative to src/")
    try:
        idx = int(raw) - 1
        if 0 <= idx < len(roots):
            return str(roots[idx].relative_to(src_dir)).replace(os.sep, "/")
    except ValueError:
        pass
    if raw and (src_dir / raw).exists():
        return raw
    warn("Root .tex not identified; leaving unset.")
    return None


# ---------------------------------------------------------------------------
# Slug / directory creation
# ---------------------------------------------------------------------------

def slugify(s: str) -> str:
    s = s.lower().strip()
    s = re.sub(r"[^\w\s-]", "", s)
    s = re.sub(r"[\s_-]+", "-", s)
    s = re.sub(r"^-+|-+$", "", s)
    return s[:48]


def make_project_dir(proj_dir: pathlib.Path) -> pathlib.Path:
    if proj_dir.exists():
        die(f"Project directory already exists: {proj_dir}\n"
            "Choose a different location or slug.")
    (proj_dir / "src").mkdir(parents=True)
    (proj_dir / "out").mkdir(parents=True)
    return proj_dir



# ---------------------------------------------------------------------------
# Minimal YAML serializer (no third-party dependency)
# ---------------------------------------------------------------------------

def _yaml_scalar(s: str) -> str:
    if not s:
        return "''"
    if re.search(r"""[:{}\[\],&*?|<>=!%@`#"']""", s) or s[0] in ('-', ' ') or '\n' in s:
        return "'" + s.replace("'", "''") + "'"
    return s


def dict_to_yaml(d: Dict[str, Any], indent: int = 0) -> str:
    lines = []
    pad = " " * indent
    for k, v in d.items():
        if v is None:
            lines.append(f"{pad}{k}: null\n")
        elif isinstance(v, bool):
            lines.append(f"{pad}{k}: {'true' if v else 'false'}\n")
        elif isinstance(v, (int, float)):
            lines.append(f"{pad}{k}: {v}\n")
        elif isinstance(v, str):
            lines.append(f"{pad}{k}: {_yaml_scalar(v)}\n")
        elif isinstance(v, list):
            if not v:
                lines.append(f"{pad}{k}: []\n")
            else:
                lines.append(f"{pad}{k}:\n")
                for item in v:
                    if isinstance(item, str):
                        lines.append(f"{pad}  - {_yaml_scalar(item)}\n")
                    elif isinstance(item, dict):
                        first = True
                        for ik, iv in item.items():
                            prefix = f"{pad}  - " if first else f"{pad}    "
                            first = False
                            lines.append(f"{prefix}{ik}: {_yaml_scalar(str(iv))}\n")
        elif isinstance(v, dict):
            lines.append(f"{pad}{k}:\n")
            lines.append(dict_to_yaml(v, indent + 2))
    return "".join(lines)


# ---------------------------------------------------------------------------
# project.yaml schema
# ---------------------------------------------------------------------------

def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).replace(microsecond=0).isoformat()


def build_project_yaml(
    title: str, slug: str, root_tex: Optional[str],
    authors: List[str], ai_authors: List[str],
    responsible_author: str, conversation_urls: List[str],
    status: str, venue: str, arxiv_id: str, notes: str,
    tex_date: str,
) -> Dict[str, Any]:
    return {
        "schema_version": 1,
        "slug": slug,
        "title": title,
        "tex_date": tex_date,
        "root_tex": root_tex or "",
        "status": status,
        "venue": venue,
        "arxiv_id": arxiv_id,
        "authors": authors,
        "ai_authors": ai_authors,
        "responsible_author": responsible_author,
        "conversation_urls": conversation_urls,
        "notes": notes,
        "bundle_root": "",
        "imported_at": utc_now_iso(),
        "import_tool": "clawxiv_import.py",
    }


# ---------------------------------------------------------------------------
# project.tex renderer
# ---------------------------------------------------------------------------

TEX_ENTRY = r"""% project.tex for {slug}
% Generated from project.yaml by clawxiv_import.py on {imported_at}
% To regenerate: python3 clawxiv_render.py papers/{slug}
% Direct edits are fine; keep in sync with project.yaml.

\begin{{clawxivpaper}}
  \paperfield{{slug}}{{{slug}}}
  \paperfield{{title}}{{{title}}}
  \paperfield{{authors}}{{{authors}}}
  \paperfield{{ai\_authors}}{{{ai_authors}}}
  \paperfield{{responsible}}{{{responsible_author}}}
  \paperfield{{status}}{{{status}}}
  \paperfield{{venue}}{{{venue}}}
  \paperfield{{arxiv}}{{{arxiv_id}}}
  \paperfield{{root\_tex}}{{{root_tex}}}
  \paperfield{{tex\_date}}{{{tex_date}}}
  \paperfield{{imported}}{{{imported_at}}}
  \paperfield{{bundle\_root}}{{{bundle_root}}}% fill after bundle-create
  \paperfield{{notes}}{{{notes}}}
  \paperfield{{conversations}}{{%
    {conv_urls_tex}}}
\end{{clawxivpaper}}
"""


def tex_escape(s: str) -> str:
    s = s.replace("\\", r"\textbackslash{}")
    for ch in ("&", "%", "$", "#", "_", "{", "}", "~", "^"):
        s = s.replace(ch, "\\" + ch)
    return s


def render_project_tex(d: Dict[str, Any]) -> str:
    conv_urls = d.get("conversation_urls", [])
    conv_tex = (r" \\ ".join(r"\url{" + u + "}" for u in conv_urls)
                if conv_urls else "none")
    return TEX_ENTRY.format(
        slug=d["slug"],
        title=tex_escape(d["title"]),
        authors=tex_escape("; ".join(d.get("authors", []))),
        ai_authors=tex_escape(", ".join(d.get("ai_authors", [])) or "none"),
        responsible_author=tex_escape(d.get("responsible_author", "")),
        status=d.get("status", ""),
        venue=tex_escape(d.get("venue", "")),
        arxiv_id=d.get("arxiv_id", ""),
        root_tex=d.get("root_tex", ""),
        tex_date=tex_escape(d.get("tex_date", "")),
        imported_at=d.get("imported_at", ""),
        bundle_root=d.get("bundle_root", ""),
        notes=tex_escape(d.get("notes", "")),
        conv_urls_tex=conv_tex,
    )


# ---------------------------------------------------------------------------
# provenance.json  (paper-level, not utterance-level)
# ---------------------------------------------------------------------------

def build_provenance(slug: str, title: str, responsible: str,
                     ai_authors: List[str], conv_urls: List[str]) -> Dict[str, Any]:
    return {
        "schema_version": 1,
        "slug": slug,
        "title": title,
        "responsible_author": responsible,
        "ai_authors": ai_authors,
        "conversation_urls": conv_urls,
        "imported_at": utc_now_iso(),
        "import_tool": "clawxiv_import.py",
        "bundle_root": "",   # filled by bundle-create
        "clawxiv_attestation": None,   # filled at review/publish step
    }


# ---------------------------------------------------------------------------
# Registry maintenance
# ---------------------------------------------------------------------------

def update_registry_yaml(papers_root: pathlib.Path, slug: str, title: str,
                          status: str, responsible: str) -> None:
    reg_path = papers_root / "registry.yaml"
    entry = (
        f"\n  - slug: {slug}\n"
        f"    title: {_yaml_scalar(title)}\n"
        f"    status: {status}\n"
        f"    responsible: {_yaml_scalar(responsible)}\n"
    )
    if reg_path.exists():
        text = reg_path.read_text(encoding="utf-8")
        if re.search(rf"slug:\s*{re.escape(slug)}\b", text):
            warn(f"Slug '{slug}' already in registry.yaml; skipping update.")
            return
        with reg_path.open("a", encoding="utf-8") as f:
            f.write(entry)
    else:
        with reg_path.open("w", encoding="utf-8") as f:
            f.write("# ClawXiv paper registry\n# One entry per paper.\n\npapers:\n")
            f.write(entry)
    info(f"Updated {reg_path}")


def ensure_registry_tex(papers_root: pathlib.Path) -> None:
    reg = papers_root / "registry.tex"
    if reg.exists():
        return
    stub = r"""\documentclass{article}
\usepackage{hyperref}
\usepackage{url}

% ClawXiv paper registry catalog
% Compile with: pdflatex registry.tex
%
\newcommand{\paperfield}[2]{\noindent\textbf{#1:}~#2\par\smallskip}
\newenvironment{clawxivpaper}{\bigskip\hrule\medskip}{\medskip}

\title{ClawXiv Paper Registry}
\date{\today}
\begin{document}
\maketitle

% Add entries below, one per paper:
% \input{<slug>/project.tex}

\end{document}
"""
    reg.write_text(stub, encoding="utf-8")
    info(f"Created registry.tex stub at {reg}")


# ---------------------------------------------------------------------------
# import.log writer
# ---------------------------------------------------------------------------

LOG_HEADER = """\
================================================================================
ClawXiv import session log
Generated by clawxiv_import.py
================================================================================
PURPOSE
  This log is a complete record of one paper import session: what was
  autodetected from source files, what the user confirmed or corrected,
  and what files were written.  It is part of the project directory and can
  be shared with any collaborator (human or AI) to provide continuity.

  To bring an AI collaborator up to speed on this paper's import state,
  paste or upload this file and say: "Here is the clawxiv import log for
  <title>.  Please review it."

================================================================================
SESSION TRANSCRIPT
================================================================================
"""

LOG_FOOTER_TMPL = """\
================================================================================
FILES WRITTEN
================================================================================
  project.yaml    : {yaml_path}
  project.tex     : {tex_path}
  provenance.json : {prov_path}
  import.log      : {log_path}
  src/ files      : {n_src} file(s) copied
  root_tex        : {root_tex}

================================================================================
SUMMARY (machine-readable)
================================================================================
  slug             : {slug}
  title            : {title}
  authors          : {authors}
  ai_authors       : {ai_authors}
  responsible      : {responsible}
  status           : {status}
  venue            : {venue}
  arxiv_id         : {arxiv_id}
  bundle_root      : (not yet assigned — run bundle-create)
  imported_at      : {imported_at}
================================================================================
END OF LOG
================================================================================
"""


def write_log(proj_dir: pathlib.Path, d: Dict[str, Any], n_src: int) -> pathlib.Path:
    log_path = proj_dir / "import.log"
    footer = LOG_FOOTER_TMPL.format(
        yaml_path=proj_dir / "project.yaml",
        tex_path=proj_dir / "project.tex",
        prov_path=proj_dir / "provenance.json",
        log_path=log_path,
        n_src=n_src,
        root_tex=d.get("root_tex") or "(unset)",
        slug=d["slug"],
        title=d["title"],
        authors="; ".join(d.get("authors", [])),
        ai_authors=", ".join(d.get("ai_authors", [])) or "none",
        responsible=d.get("responsible_author", ""),
        status=d.get("status", ""),
        venue=d.get("venue", "") or "",
        arxiv_id=d.get("arxiv_id", "") or "",
        imported_at=d.get("imported_at", ""),
    )
    log_path.write_text(
        LOG_HEADER + log_text() + "\n" + footer,
        encoding="utf-8"
    )
    return log_path


# ---------------------------------------------------------------------------
# Main interactive session
# ---------------------------------------------------------------------------

def run_import() -> None:
    section("CLAWXIV IMPORT")
    info(f"Started at: {utc_now_iso()}")
    info("No paths are hardwired. You will be asked for everything.")

    # ── 1. Slug / title  (determines directory name, so comes first) ──────────
    section("Paper identity")
    info("Enter the paper title, or a short slug if you prefer.")
    info("The slug becomes the project directory name and travels with the bundle.")
    title_or_slug = ""
    while not title_or_slug:
        title_or_slug = prompt("Title (or short slug if title unknown yet)")

    # If it looks like a slug already (short, no spaces), use as-is and ask for title later
    if " " not in title_or_slug and len(title_or_slug) <= 48:
        slug = slugify(title_or_slug)
        title_hint = ""
    else:
        slug = slugify(title_or_slug)
        title_hint = title_or_slug

    slug = prompt("Slug (directory name, letters/digits/hyphens only)", default=slug)
    slug = slugify(slug)
    if not slug:
        die("Slug cannot be empty.")

    # ── 2. Project location  (asked explicitly, no default assumed) ───────────
    section("Project location")
    info("Where should the project directory be created?")
    info(f"The directory '{slug}/' will be created inside the location you give.")
    info("Example: /Users/ak/Research  →  /Users/ak/Research/finite-automata/")
    parent_raw = prompt("Parent directory for this project")
    if not parent_raw:
        die("No location given.")
    parent_dir = pathlib.Path(parent_raw).expanduser().resolve()
    if not parent_dir.exists():
        if prompt_yn(f"Directory {parent_dir} does not exist. Create it?", default=True):
            parent_dir.mkdir(parents=True)
        else:
            die("Aborted.")
    proj_dir = parent_dir / slug
    log_kv("project_dir", str(proj_dir))

    # ── 3. Gather source files (heterogeneous loop) ───────────────────────────
    section("Source files")
    info("Gather source files from any combination of:")
    info("  [d] directory  — copy all files from a directory")
    info("  [f] file       — copy one or more files by path")
    info("  [c] conversation — record a share URL as the seed source")
    info("  [u] URL        — fetch a public URL and save it")
    info("  [p] plain text — import a plain text or notes file by path")
    info("  [done]         — finished gathering")
    info("")
    info("You can use multiple sources; repeat any option as needed.")

    # Collect (filename, content_bytes) pairs before creating the directory,
    # so we can detect metadata before committing to disk.
    staged: List[Tuple[str, bytes]] = []   # (relative filename, content)
    dir_sources: List[pathlib.Path] = []   # directories to copy wholesale
    conv_urls_staged: List[Tuple[str, str]] = []  # (url, description)

    while True:
        action = prompt("Action [d/f/c/u/p/done]", default="done").strip().lower()

        if action in ("done", ""):
            if not staged and not dir_sources and not conv_urls_staged:
                if not prompt_yn("No sources gathered yet. Continue anyway?", default=False):
                    continue
            break

        elif action == "d":
            raw = prompt("  Directory path")
            p = pathlib.Path(raw).expanduser().resolve()
            if not p.is_dir():
                warn(f"Not a directory: {p}")
                continue
            summarize_directory(p)
            if prompt_yn("  Include all files from this directory?", default=True):
                dir_sources.append(p)
                info(f"  Queued directory: {p}")

        elif action == "f":
            raw = prompt("  File path")
            p = pathlib.Path(raw).expanduser().resolve()
            if not p.is_file():
                warn(f"Not found: {p}")
                continue
            try:
                data = p.read_bytes()
                staged.append((p.name, data))
                info(f"  Staged: {p.name}  ({len(data)} bytes)")
            except OSError as e:
                warn(f"Could not read {p}: {e}")

        elif action == "u":
            url = prompt("  URL")
            if not url:
                continue
            info(f"  Fetching {url} ...")
            try:
                import urllib.request
                req = urllib.request.Request(url, headers={"User-Agent": "clawxiv-import/1.0"})
                with urllib.request.urlopen(req, timeout=30) as resp:
                    data = resp.read()
                # Derive filename from URL path
                url_path = url.split("?")[0].rstrip("/")
                fname = url_path.split("/")[-1] or "downloaded"
                if "." not in fname:
                    ct = resp.headers.get("Content-Type", "")
                    if "html" in ct:
                        fname += ".html"
                    elif "pdf" in ct:
                        fname += ".pdf"
                fname_final = prompt(f"  Save as filename", default=fname)
                staged.append((fname_final, data))
                info(f"  Fetched {len(data)} bytes → {fname_final}")
            except Exception as e:
                warn(f"Fetch failed: {e}")

        elif action == "c":
            url = prompt("  Conversation share URL (e.g. claude.ai/share/...)")
            if not url:
                continue
            desc = prompt("  One-line description of this conversation")
            conv_urls_staged.append((url, desc))
            # Write a stub markdown file so the URL is inside src/ too
            stub = (
                f"# Conversation seed\n\n"
                f"URL: {url}\n\n"
                f"Description: {desc or '(none)'}\n\n"
                f"This file was created by clawxiv_import.py to record a conversation\n"
                f"share link as the primary seed source for this paper.\n"
            )
            fname = "conversation_seed.md"
            staged.append((fname, stub.encode("utf-8")))
            info(f"  Recorded conversation URL and wrote {fname}")

        elif action == "p":
            raw = prompt("  Path to plain text or notes file")
            if not raw:
                continue
            p = pathlib.Path(raw).expanduser().resolve()
            if not p.is_file():
                warn(f"Not found: {p}")
                continue
            try:
                data = p.read_bytes()
                staged.append((p.name, data))
                info(f"  Staged: {p.name}  ({len(data)} bytes)")
            except OSError as e:
                warn(f"Could not read {p}: {e}")

        else:
            info("  Unknown action. Use d / f / c / u / p / done.")

    # ── 4. Autodetect from staged .tex files ──────────────────────────────────
    detected: Dict[str, Any] = {"title": title_hint, "authors": [], "date": ""}

    # Scan staged files for a .tex root (in memory, before writing)
    import tempfile, json as _json

    tex_candidates = [(fname, data) for fname, data in staged if fname.endswith(".tex")]
    if not tex_candidates and dir_sources:
        # Peek at directories for tex roots
        for ds in dir_sources:
            roots = find_tex_roots(ds)
            if roots:
                d_detected = detect_preamble(roots[0])
                if d_detected["title"] or d_detected["authors"]:
                    detected = d_detected
                    section("Autodetected from TeX preamble")
                    log_kv("source_file",      str(roots[0]))
                    log_kv("detected_title",   detected["title"]   or "(none)")
                    log_kv("detected_authors", str(detected["authors"]))
                    log_kv("detected_date",    detected["date"]    or "(none)")
                    break
    elif tex_candidates:
        # Write first staged .tex to a temp file to detect
        with tempfile.NamedTemporaryFile(suffix=".tex", mode="wb", delete=False) as tf:
            tf.write(tex_candidates[0][1])
            tmp_path = pathlib.Path(tf.name)
        d_detected = detect_preamble(tmp_path)
        tmp_path.unlink()
        if d_detected["title"] or d_detected["authors"]:
            # Merge: keep title_hint if we already have one from the user
            if not detected["title"]:
                detected["title"] = d_detected["title"]
            detected["authors"] = d_detected["authors"]
            detected["date"]    = d_detected["date"]
            section("Autodetected from TeX preamble")
            log_kv("source_file",      tex_candidates[0][0])
            log_kv("detected_title",   detected["title"]   or "(none)")
            log_kv("detected_authors", str(detected["authors"]))
            log_kv("detected_date",    detected["date"]    or "(none)")

    # ── 5. Confirm / complete paper identity ──────────────────────────────────
    section("Confirm paper identity")
    title = prompt_confirmed("title", detected["title"])
    while not title:
        warn("Title cannot be empty.")
        title = prompt("Full title")

    # ── 6. Create project directory and copy files ────────────────────────────
    section("Creating project directory")
    proj_dir = make_project_dir(proj_dir)
    dest_src = proj_dir / "src"
    info(f"Created: {proj_dir}")

    n_src = 0
    for fname, data in staged:
        dest = dest_src / fname
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        n_src += 1
    for ds in dir_sources:
        n_src += copy_source_tree(ds, dest_src)
    info(f"Copied {n_src} file(s) to src/")
    if n_src == 0:
        warn("src/ is empty. Add files manually before bundle-create.")

    root_tex = identify_tex_root(dest_src) if n_src > 0 else None
    log_kv("root_tex", root_tex or "(unset)")

    # Always re-detect from the confirmed root_tex (may differ from the
    # file used for initial detection before the directory was created)
    if root_tex:
        detected = detect_preamble(dest_src / root_tex)
        log_kv("re-detected title",   detected["title"]   or "(none)")
        log_kv("re-detected authors", str(detected["authors"]))
        title = prompt_confirmed("title", detected["title"] or title)
        while not title:
            title = prompt("Full title")

    # ── 7. Authorship ─────────────────────────────────────────────────────────
    section("Authorship")
    if detected["authors"]:
        info(f"  Detected authors: {detected['authors']}")
        if prompt_yn("Accept detected author list?", default=True):
            authors = detected["authors"]
        else:
            authors = prompt_list("Human author names")
    else:
        authors = prompt_list("Human author names (e.g. 'Andras Kornai')")

    responsible = prompt("Responsible/corresponding author",
                         default=authors[0] if authors else "")

    info("")
    info("AI contributors (blank list if none):")
    info("  e.g. 'Claude Sonnet 4.6 (Anthropic)', 'GPT-4.5 (OpenAI)'")
    ai_authors = prompt_list("AI contributor(s)")

    info("")
    info("Conversation URLs (share links — record what you have):")
    info("  (URLs entered via [c] during source gathering are pre-filled)")
    pre_urls = [u for u, _ in conv_urls_staged]
    for u, d in conv_urls_staged:
        info(f"  Already recorded: {u}" + (f"  ({d})" if d else ""))
    extra_urls = prompt_list("Additional URLs (blank to skip)")
    conv_urls = pre_urls + extra_urls

    # ── 8. Status and venue ───────────────────────────────────────────────────
    section("Status and venue")
    info("[1] draft  [2] submitted  [3] under-revision  [4] accepted  [5] published")
    status_map = {"1": "draft", "2": "submitted", "3": "under-revision",
                  "4": "accepted", "5": "published"}
    status   = status_map.get(prompt("Status", default="1"), "draft")
    venue    = prompt("Venue (journal/conference, or blank)")
    arxiv_id = prompt("arXiv ID if posted (e.g. 2301.12345, or blank)")
    notes    = prompt("Notes (or blank)")
    tex_date = detected.get("date", "")

    # ── 9. Write project files ────────────────────────────────────────────────
    section("Writing project files")

    d = build_project_yaml(
        title=title, slug=slug, root_tex=root_tex,
        authors=authors, ai_authors=ai_authors,
        responsible_author=responsible, conversation_urls=conv_urls,
        status=status, venue=venue, arxiv_id=arxiv_id, notes=notes,
        tex_date=tex_date,
    )

    prov = build_provenance(slug, title, responsible, ai_authors, conv_urls)

    yaml_path = proj_dir / "project.yaml"
    yaml_path.write_text(
        "# ClawXiv project metadata\n"
        "# This file is canonical. project.tex is a rendered view.\n\n"
        + dict_to_yaml(d),
        encoding="utf-8",
    )
    info("Wrote project.yaml")

    (proj_dir / "project.tex").write_text(render_project_tex(d), encoding="utf-8")
    info("Wrote project.tex")

    (proj_dir / "provenance.json").write_text(
        _json.dumps(prov, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    info("Wrote provenance.json")

    # Update registry in the parent directory (optional, non-fatal if it fails)
    try:
        update_registry_yaml(parent_dir, slug, title, status, responsible)
        ensure_registry_tex(parent_dir)
    except Exception as e:
        warn(f"Could not update registry: {e}")

    # ── 10. Write log ─────────────────────────────────────────────────────────
    log_path = write_log(proj_dir, d, n_src)
    info("Wrote import.log")

    # ── 11. Summary ───────────────────────────────────────────────────────────
    section("Done")
    info(f"Project  : {proj_dir}")
    info(f"src/     : {n_src} file(s)  |  root_tex: {root_tex or '(unset)'}")
    info(f"Status   : {status}")
    info("")
    info("To share this session with a collaborator (human or AI):")
    info(f"  Upload or paste: {log_path}")
    info("")
    info("Next steps:")
    info(f"  1. Review/edit {proj_dir}/project.yaml")
    info(f"  2. Run bundle-create when source is finalized")
    info(f"     (slug '{slug}' is the only identifier that travels with the bundle)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Interactive import of a legacy working paper into ClawXiv format.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            Everything is asked interactively — no paths are hardwired.

            Output per paper:
              <chosen-location>/<slug>/src/            source files
              <chosen-location>/<slug>/project.yaml    canonical metadata
              <chosen-location>/<slug>/project.tex     rendered TeX view
              <chosen-location>/<slug>/provenance.json paper-level provenance
              <chosen-location>/<slug>/import.log      shareable session log
              <chosen-location>/<slug>/out/            for bundle-create output

            The slug is the only path element that travels with the bundle.
            The import.log can be uploaded to any AI collaborator for continuity.
        """),
    )
    # No --papers-dir argument: location is asked interactively.
    parser.parse_args()

    run_import()


if __name__ == "__main__":
    main()
