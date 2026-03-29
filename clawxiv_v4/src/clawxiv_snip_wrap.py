#!/usr/bin/env python3
"""
clawxiv_snip_wrap.py — wrap a text snippet in the appropriate LaTeX
provenance environment based on author metadata.

Called by bin/clawxiv-snip; not intended for direct use.

Usage:
    python3 clawxiv_snip_wrap.py <text_file> <meta_json_file> [options]

Options:
    --senior-orcid ORCID    ORCID of the senior author (default: env
                            CLAWXIV_ORCID or 0000-0001-6078-6840)
    --out FILE              write LaTeX to FILE instead of stdout

The script determines the LaTeX environment by comparing the detected
author against the senior author identity:
    - senior author → \\begin{seniorquote}...\\end{seniorquote}
    - any AI author → \\begin{aiquote}...\\end{aiquote}
    - other human  → \\begin{coauthorquote}...\\end{coauthorquote}

AI authorship is detected by the presence of known AI system names
in the author string (case-insensitive).  The set is intentionally
conservative; extend AI_NAMES below as new systems are added.

The text is escaped for LaTeX: special characters are handled, and
long lines are left as-is (LaTeX wraps them at typeset time).
"""

from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import sys
from typing import Optional

# ── AI author detection ───────────────────────────────────────────────────────
# Substrings (case-insensitive) that identify an AI system as the author.
AI_NAMES: list[str] = [
    "claude",
    "gpt",
    "gemini",
    "copilot",
    "llama",
    "mistral",
    "perplexity",
    "anthropic",
    "openai",
    "google deepmind",
    "meta ai",
]

def is_ai_author(author: str) -> bool:
    a = author.lower()
    return any(name in a for name in AI_NAMES)


# ── LaTeX escaping ────────────────────────────────────────────────────────────
# Conservative escaping: only the characters that LaTeX treats specially
# outside of verbatim mode.  We do NOT escape < > or | because these are
# common in log output and the user's prose; they are valid in text mode.
_LATEX_ESCAPE = str.maketrans({
    '&':  r'\&',
    '%':  r'\%',
    '$':  r'\$',
    '#':  r'\#',
    '_':  r'\_',
    '{':  r'\{',
    '}':  r'\}',
    '~':  r'\textasciitilde{}',
    '^':  r'\textasciicircum{}',
    '\\': r'\textbackslash{}',
})

def latex_escape(text: str) -> str:
    return text.translate(_LATEX_ESCAPE)


# ── Environment selection ─────────────────────────────────────────────────────
def select_environment(author: str, senior_author: str) -> str:
    """
    Return the LaTeX environment name appropriate for this author.
    """
    if is_ai_author(author):
        return "aiquote"
    # Normalize for comparison: strip accents and case
    def normalize(s: str) -> str:
        import unicodedata
        return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode().lower()
    if normalize(author) == normalize(senior_author):
        return "seniorquote"
    return "coauthorquote"


# ── LaTeX generation ──────────────────────────────────────────────────────────
def wrap_snippet(
    text: str,
    author: str,
    url: str,
    timestamp: str,
    senior_author: str,
    snip_id: Optional[str] = None,
) -> str:
    """
    Wrap `text` in the appropriate clawxiv.sty LaTeX environment.

    Returns a complete LaTeX fragment ready to be input{}'d or pasted.
    """
    env = select_environment(author, senior_author)
    escaped_text = latex_escape(text.strip())
    escaped_author = latex_escape(author)

    # Format: YYYY-MM-DD for display; full ISO for machine use
    display_ts = timestamp[:10] if len(timestamp) >= 10 else timestamp

    lines: list[str] = []

    # Comment block for human editors
    if snip_id:
        lines.append(f"%% clawxiv snip: {snip_id}")
    lines.append(f"%% author: {author}")
    lines.append(f"%% ts:     {timestamp}")
    if url:
        lines.append(f"%% url:    {url}")
    lines.append(f"%% env:    {env}")
    lines.append("")

    # Environment open
    if env == "aiquote" and url:
        lines.append(f"\\begin{{{env}}}{{{escaped_author}}}{{{display_ts}}}[{url}]")
    else:
        lines.append(f"\\begin{{{env}}}{{{escaped_author}}}{{{display_ts}}}")

    # Body
    # Preserve paragraph breaks (blank lines → \par); single newlines → space
    paragraphs = re.split(r'\n{2,}', escaped_text)
    for i, para in enumerate(paragraphs):
        # Collapse single newlines within a paragraph
        para = re.sub(r'\n', ' ', para).strip()
        if para:
            lines.append(para)
            if i < len(paragraphs) - 1:
                lines.append("")   # blank line between paragraphs = \par in LaTeX

    lines.append(f"\\end{{{env}}}")
    lines.append("")

    return "\n".join(lines)


# ── CLI ───────────────────────────────────────────────────────────────────────
def main(argv: Optional[list[str]] = None) -> None:
    p = argparse.ArgumentParser(
        description="Wrap a captured text snippet in a clawxiv LaTeX provenance environment."
    )
    p.add_argument("text_file", help="file containing raw captured text")
    p.add_argument("meta_file", help="JSON file with author/url/ts metadata")
    p.add_argument(
        "--senior-orcid",
        default=os.environ.get("CLAWXIV_ORCID", "0000-0001-6078-6840"),
        help="ORCID of the senior/corresponding author",
    )
    p.add_argument(
        "--senior-author",
        default=os.environ.get("CLAWXIV_SENIOR_AUTHOR", "András Kornai"),
        help="Display name of the senior author",
    )
    p.add_argument("--out", default=None, help="output file (default: stdout)")
    p.add_argument("--snip-id", default=None, help="snip identifier for comment header")
    args = p.parse_args(argv)

    text = pathlib.Path(args.text_file).read_text(encoding="utf-8")
    meta = json.loads(pathlib.Path(args.meta_file).read_text(encoding="utf-8"))

    author = meta.get("author", args.senior_author)
    url    = meta.get("url", "")
    ts     = meta.get("ts", "")

    result = wrap_snippet(
        text=text,
        author=author,
        url=url,
        timestamp=ts,
        senior_author=args.senior_author,
        snip_id=args.snip_id,
    )

    if args.out:
        pathlib.Path(args.out).write_text(result, encoding="utf-8")
        print(f"snip written to {args.out}", file=sys.stderr)
    else:
        sys.stdout.write(result)


if __name__ == "__main__":
    main()
