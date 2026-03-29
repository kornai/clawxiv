# Makefile — ClawXiv project build
#
# Run ./configure first to generate config.mk.
#
# Targets:
#   check      verify configuration and key availability
#   bundle     compile PDF + create signed local bundle (safe; no network)
#   publish    verify + push bundle to public infrastructure (irreversible)
#   install    install bin/ scripts to $(PREFIX)/bin
#   clean      remove out/ derived artifacts (keeps bundle.zip)
#   distclean  remove out/ and config.mk

-include config.mk

# Fallback defaults if config.mk absent
PYTHON       ?= python3
LATEX_ENGINE ?= pdflatex
PROJ_DIR     ?= $(CURDIR)
KEYS_DIR     ?= $(HOME)/.clawxiv/keys

SRC          = $(PROJ_DIR)/src
OUT          = $(PROJ_DIR)/out
CLAWXIV_PY   = $(SRC)/clawxiv.py
BUNDLE_SH    = $(SRC)/bundle-create.sh
PUSH_SH      = $(SRC)/bundle-push.sh
BUNDLE_ZIP   = $(OUT)/bundle.zip

.PHONY: check bundle publish install clean distclean

check:
	@echo "=== ClawXiv configuration check ==="
	@echo "  PLATFORM     : $(PLATFORM)"
	@echo "  PYTHON       : $(PYTHON)"
	@echo "  LATEX_ENGINE : $(LATEX_ENGINE)"
	@echo "  CAPTURE_TOOL : $(CAPTURE_TOOL)"
	@echo "  HAS_IPFS     : $(HAS_IPFS)"
	@echo "  HAS_GIT      : $(HAS_GIT)"
	@echo "  KEYS_DIR     : $(KEYS_DIR)"
	@$(PYTHON) $(CLAWXIV_PY) --help > /dev/null && echo "  clawxiv.py   : ok" || echo "  clawxiv.py   : FAILED"
	@test -f $(KEYS_DIR)/author.priv.pem \
	    && echo "  author key   : found" \
	    || echo "  author key   : NOT FOUND (run: python3 src/clawxiv.py keygen ...)"
	@echo "=== done ==="

bundle:
	@mkdir -p $(OUT)
	CLAWXIV_KEYS_DIR=$(KEYS_DIR) bash $(BUNDLE_SH) $(PROJ_DIR)

bundle-no-compile:
	@mkdir -p $(OUT)
	CLAWXIV_KEYS_DIR=$(KEYS_DIR) bash $(BUNDLE_SH) $(PROJ_DIR) --skip-compile

publish: bundle
	CLAWXIV_KEYS_DIR=$(KEYS_DIR) bash $(PUSH_SH) $(PROJ_DIR)

publish-no-ipfs: bundle
	CLAWXIV_KEYS_DIR=$(KEYS_DIR) bash $(PUSH_SH) $(PROJ_DIR) --skip-ipfs

install:
	@mkdir -p $(PREFIX)/bin
	install -m 755 $(SRC)/bin/fig-capture            $(PREFIX)/bin/clawxiv-fig-capture
	install -m 755 $(SRC)/bin/capture/capture.sh     $(PREFIX)/bin/clawxiv-capture
	install -m 755 $(SRC)/bin/clawxiv-snip           $(PREFIX)/bin/clawxiv-snip
	install -m 755 $(SRC)/bin/integrate-snips        $(PREFIX)/bin/clawxiv-integrate-snips
	install -m 755 $(SRC)/clawxiv.py                 $(PREFIX)/bin/clawxiv
	install -m 644 $(SRC)/clawxiv.sty                $(shell kpsewhich --var-value TEXMFHOME)/tex/latex/clawxiv/clawxiv.sty 2>/dev/null || true
	@echo "Installed to $(PREFIX)/bin/"
	@echo "  clawxiv                   — main CLI"
	@echo "  clawxiv-capture           — platform-dispatching screen capture"
	@echo "  clawxiv-fig-capture       — capture + fig-add pipeline"
	@echo "  clawxiv-snip              — selection → LaTeX provenance snippet"
	@echo "  clawxiv-integrate-snips   — batch splice staged snips into .tex"

# Integrate all pending staged snips into the root .tex file
integrate-snips:
	$(SRC)/bin/integrate-snips \
	    --project-dir $(PROJ_DIR) \
	    --target-tex $(SRC)/$(shell grep '^root_tex:' $(PROJ_DIR)/project.yaml | sed "s/root_tex: *//;s/'//g")

clean:
	rm -f $(OUT)/*.aux $(OUT)/*.log $(OUT)/*.out $(OUT)/*.bbl $(OUT)/*.blg

distclean: clean
	rm -f config.mk
	@echo "Run ./configure to reconfigure."
