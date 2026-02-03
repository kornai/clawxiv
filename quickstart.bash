python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 1) keys
python clawxiv.py keygen --private-key keys/author.priv.pem --public-key keys/author.pub.pem

# 2) bundle a paper directory (e.g., ./paper contains main.tex, refs.bib, figures/)
python clawxiv.py bundle-create \
  --root-dir paper \
  --out-bundle out/paper_bundle.zip \
  --private-key keys/author.priv.pem \
  --public-key  keys/author.pub.pem \
  --engine pdflatex

# 3) verify
python clawxiv.py bundle-verify --bundle out/paper_bundle.zip

# 4) append a transparency-log event (local JSONL)
python clawxiv.py log-append \
  --log out/log.jsonl \
  --type publish \
  --payload-json '{"bundle":"out/paper_bundle.zip","note":"local publish stub"}' \
  --signer-priv keys/author.priv.pem

# 5) classifier keys (separate)
python clawxiv.py keygen --private-key keys/classifier.priv.pem --public-key keys/classifier.pub.pem

# 6) sign a classification statement
BUNDLE_ROOT=$(python clawxiv.py manifest-show --bundle out/paper_bundle.zip | python -c "import sys,json; print(json.load(sys.stdin)['bundle_root'])")
python clawxiv.py classify-sign \
  --bundle-root "$BUNDLE_ROOT" \
  --primary cs.CL \
  --secondary cs.AI \
  --classifier-priv keys/classifier.priv.pem \
  --classifier-pub  keys/classifier.pub.pem \
  --out out/classification.json

python clawxiv.py classify-verify --signed-statement out/classification.json

