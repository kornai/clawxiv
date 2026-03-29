# snip — selected-text capture with provenance detection

## Purpose

The `snip` subsystem captures text that is currently selected (or on
the clipboard) in any application, automatically detects who wrote it
(by inspecting the frontmost application and its URL if applicable),
and wraps the text in the appropriate `clawxiv.sty` LaTeX environment.

The result is staged as `src/snips/<timestamp>.tex` and simultaneously
placed on the system clipboard for immediate pasting into an editor.

## The provenance model

Three kinds of authorship are distinguished, each with its own visual
treatment in the typeset output (defined in `src/clawxiv.sty`):

| Author class        | LaTeX environment   | Visual style                        |
|---------------------|---------------------|-------------------------------------|
| Senior/corresponding| `seniorquote`       | Blue left rule, pale blue background|
| AI co-author        | `aiquote`           | Ochre left rule, clickable link     |
| Other human         | `coauthorquote`     | Grey left rule                      |

AI authorship is detected by the presence of known system names in
the author string (Claude, GPT, Gemini, Copilot, …).

## Workflow

### Keyboard-triggered (recommended)

1. Select text in any application (Claude.ai, your browser, a PDF
   viewer, your email client, …).
2. Press the assigned keyboard shortcut.
3. The snippet is staged in `src/snips/` and placed on the clipboard.
4. Switch to your editor; position the cursor; paste (`Cmd-V`).

Alternatively, use `--splice` to insert automatically at the
`%%CLAWXIV-SNIP-INSERT%%` marker in the target `.tex` file.

### Command-line

```sh
# Basic: stage clipboard text with auto-detected provenance
bin/clawxiv-snip --project-dir ~/Sandbox/clawxiv

# Override author and URL
bin/clawxiv-snip --project-dir ~/Sandbox/clawxiv \
    --author "Claude Sonnet 4.6 (Anthropic)" \
    --url "https://claude.ai/chat/..."

# Splice directly into a target .tex at the marker
bin/clawxiv-snip --project-dir ~/Sandbox/clawxiv \
    --target-tex src/clawxiv_whitepaper_v4.tex \
    --splice

# Batch-integrate all pending staged snips
bin/integrate-snips \
    --project-dir ~/Sandbox/clawxiv \
    --target-tex src/clawxiv_whitepaper_v4.tex
```

## Insertion point convention

Add the following comment to your `.tex` file where you want snips
to accumulate:

```latex
%%CLAWXIV-SNIP-INSERT%%
```

Or, equivalently, use the `\snipinsert` macro from `clawxiv.sty`
(which is a no-op at typeset time):

```latex
\snipinsert  %% staged snips appear here
```

## Keyboard shortcut setup (macOS)

1. Open **Automator** → New **Quick Action**.
2. Set *Workflow receives*: **No Input** in **Any Application**.
3. Add **Run Shell Script**:
   ```bash
   export CLAWXIV_PROJECT_DIR=~/Sandbox/clawxiv
   export CLAWXIV_ORCID=0000-0001-6078-6840
   export CLAWXIV_TARGET_TEX=~/Sandbox/clawxiv/src/clawxiv_whitepaper_v4.tex
   /path/to/src/bin/clawxiv-snip
   ```
4. Save as e.g. `ClawXiv Snip`.
5. System Settings → Keyboard → Keyboard Shortcuts → Services → General
   → assign e.g. `Ctrl-Opt-Cmd-S`.

## Platform implementation status

| File                | Platform        | Text retrieval | Provenance detection |
|---------------------|-----------------|----------------|----------------------|
| `macos.sh`          | macOS           | ✓ (pbpaste)   | ✓ (AppleScript)      |
| `linux_x11.sh`      | Linux / X11     | ✓ (xclip/xsel)| stub                 |
| `linux_wayland.sh`  | Linux / Wayland | ✓ (wl-paste)  | stub                 |
| `windows.ps1`       | Windows         | ✓ (Get-Clipboard)| stub              |

## Environment variables

| Variable                  | Default               | Effect                          |
|---------------------------|-----------------------|---------------------------------|
| `CLAWXIV_PROJECT_DIR`     | (required)            | Project root                    |
| `CLAWXIV_TARGET_TEX`      | (optional)            | Target .tex for --splice        |
| `CLAWXIV_SENIOR_AUTHOR`   | `András Kornai`       | Senior author display name      |
| `CLAWXIV_ORCID`           | `0000-0001-6078-6840` | Senior author ORCID             |
| `CLAWXIV_SNIP_AUTHOR`     | (auto-detected)       | Override detected author        |
| `CLAWXIV_SNIP_URL`        | (auto-detected)       | Override detected source URL    |
| `CLAWXIV_SNIP_COPY_FIRST` | `1`                   | Simulate Cmd-C before reading   |
| `CLAWXIV_PLATFORM`        | (auto-detected)       | Override platform detection     |

## Adding a new platform

1. Create `bin/snip/<platform>.sh`.
2. Read `$SNIP_TMP_PREFIX` for the output file prefix.
3. Write the captured text to `${SNIP_TMP_PREFIX}.txt`.
4. Write JSON metadata to `${SNIP_TMP_PREFIX}.meta`:
   `{"author": "...", "url": "...", "ts": "...", "app": "...", "bundle": "..."}`.
5. Exit 0 on success, 1 on empty, 2 on unsupported, 3 on missing tool.
6. Add a `case` branch in `snip.sh` and a row to the status table above.
