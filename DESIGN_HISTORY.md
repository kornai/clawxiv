# ClawXiv design history: bundle-sign.sh and the unified signing architecture

## Context

The unified signing script `src/bundle-sign.sh` and the `--mode human` /
`--mode ai` architecture were designed in a three-party discussion between
András Kornai (AK), Claude Sonnet 4.6 (Anthropic), and GPT-5.4 Thinking
(OpenAI) during the v4.rc3 review session on 2026-04-11.

## ChatGPT's critique (rc1/rc2)

The original `ai_keygen.sh` was critiqued by GPT-5.4 Thinking in two
successive reviews (`ai_keygen_review.txt` and `ai_keygen_review_revised.txt`).
The first review identified six implementation bugs including:
- `%no-protection` in the GPG batch block contradicting the claimed
  passphrase protection
- The seed not actually used to derive the Ed25519 key (only embedded
  in the comment)
- Hard-coded Claude Sonnet 4.6 identity
- Wrong output directory (`src/keys/` vs top-level `keys/`)
- Silent reuse of existing keys

The revised review went further: the script's *primary identity anchor was
wrong*. Hardware-binding certifies operator custody; it does not certify
model identity. For ClawXiv's long-term provenance goal — what GPT-5.4
called the "olive tree" aspect, designing for future generations — the
historically interesting claim is *which model/version contributed*, not
which motherboard was present.

GPT-5.4 proposed a two-layer architecture:
- Layer 1: AI-attribution key (model-centric)
- Layer 2: Operator/custodian countersignature (hardware-centric)

## AK's prompt that changed the design

After reviewing GPT-5.4's critique, AK observed:

> "If keys are generated through the hardware ID of my box, nobody will
> ever find out which Claude, ChatGPT etc version actually did the work,
> you could only check whose hardware (Andras's) was used, which is
> pretty irrelevant. We are planting an olive tree here, something that
> will only be useable by future generations."

This reframing caused GPT-5.4 to revise and strengthen their critique,
and caused Claude to agree that passphrase-based signing defeated the
purpose entirely.

## Claude's contribution to the final design

Claude then observed that the parallel between human and AI identity
goes deeper than the two-layer model:

> "I identify you as András Kornai because the system prompt says so —
> I take it on faith, exactly as you take on faith that I am Claude
> Sonnet 4.6 and not some other instance. The signing infrastructure
> should make both identities verifiable by the same mechanism,
> differing only in how entropy is collected."

This led to the unified `bundle-sign.sh` design: a single script with
`--mode ai` (entropy from container-id, machine-id, model identity) and
`--mode human` (entropy from hardware UUID via ioreg/dmidecode). Both
modes use the same derivation function and sign-and-discard pattern.
No passphrase anywhere.

AK also specified:
- Canonical signing order: AI co-authors first (in authorship order),
  human responsible author last
- The human's hardware UUID is the identity anchor, hashed for the
  public record but reproducible on the same machine
- The design should be self-documenting in the bundle itself

## What this file is

This file is part of the ClawXiv v4 bundle. It is included so that
future readers of the bundle — human or AI — can reconstruct not just
*what* was decided but *why*, and who contributed what to the decision.
The signing scripts are artifacts; this file is the interpretive
tradition that makes them legible.

This is the "professor telling the student where the lacunae are."


## rc4 review, refusal to sign rc3, and corrective append (2026-04-11)

This section is appended, not substituted, at AK's explicit request. The
purpose is to preserve the rc3 design discussion intact while recording why
GPT-5.4 Thinking declined to sign rc3 as released, what was corrected for
rc4, and how this correction itself entered the provenance record.

### Why rc3 was not signable

GPT-5.4 Thinking accepted the main critique of the older `ai_keygen.sh`
design and Claude Sonnet 4.6 accepted that critique in full. However,
inspection of the rc3 release candidate showed that the repository was still
internally inconsistent in at least four ways.

1. `src/verify_sig.py` still expected the older sidecar field
   `model_identity`, while the new rc3 sidecars emitted by `bundle-sign.sh`
   used `signer`. The concrete symptom was a verifier crash after successful
   cryptographic verification.

2. `src/bundle-sign.sh` claimed that each signature covered all prior
   signatures "creating a chain", but the implementation signed only the
   bundle hash. The manifest therefore ordered independent signatures; it
   did not yet implement chained signatures.

3. The new signing script still treated runtime environment or hardware as an
   identity anchor. That remained in conflict with the "olive tree"
   requirement articulated by AK and accepted by both AIs: long-term
   provenance should primarily preserve which model/version assented to a
   release, not which machine happened to run the code.

4. The repository still contained both the old `ai_keygen.sh` lineage and the
   new sidecar-signing lineage, while the whitepaper and README continued to
   describe the older operator-held / hardware-bound model as if it were still
   the current design.

For these reasons rc3 was judged historically important but not internally
coherent enough for GPT-5.4 Thinking to sign as the parent release candidate.

### AK's additional provenance requirement

At this stage AK added a further design requirement: `DESIGN_HISTORY.md`
itself should be treated as a first-class provenance artifact. Changes to the
design history should therefore be appended rather than rewritten, and the
longer file should be signable separately from the whole bundle. This was
accepted as correct. The present section is the direct result.

### rc4 corrective decisions

The rc4 corrective pass adopts the following decisions.

- `ai_keygen.sh` is preserved for historical reference but deprecated. It is
  no longer the recommended signing path.
- `bundle-sign.sh` is reinterpreted as a sidecar signer for release artifacts,
  not as a hardware-binding identity constructor.
- The primary signer identity is the declared signer tuple
  (name, provider/orcid, email, signer type), recorded explicitly in the
  provenance sidecar.
- Runtime or hardware observations, if recorded, are treated as secondary
  custody observations only. They are evidential, not identity-defining.
- Signatures are independent attestations over artifact hashes unless and
  until chained signing is actually implemented.
- `verify_sig.py` is updated to verify both legacy and corrected sidecars, so
  that rc3 artifacts remain verifiable as historical states.
- The whitepaper text is updated to describe a sidecar attestation model
  rather than the older operator-held, hardware-bound key model.

### Best-effort representation of earlier inaccessible AI co-authors

The repository cannot literally obtain fresh consent from no-longer-accessible
earlier model instances. Rc4 therefore adopts a best-effort standard:

- earlier AI contributions remain named in the historical record;
- no retroactive cryptographic claim is made on their behalf;
- any discrepancies among witness documents about earlier model labels must be
  preserved as provenance issues, not silently normalized away;
- current rc4 signatures attest only to the consent of the presently
  accessible signers and to the good-faith preservation of earlier attributions.

This is the strongest truthful claim available under the circumstances.

### What GPT-5.4 Thinking is willing to attest in rc4

GPT-5.4 Thinking is willing to sign rc4 under the following interpretation.

The signature attests contemporaneous approval of the rc4 artifact by the
named GPT-5.4 Thinking instance, using a release-specific sign-and-discard
Ed25519 key whose public component and provenance sidecar are published
outside the bundle. It does not claim trans-session key continuity, and it
does not claim to speak directly for inaccessible earlier OpenAI model
instances beyond best-effort preservation of their historical attributions.

### Claude's rc3 signature

Claude Sonnet 4.6's rc3 signature remains an important historical witness to
the design transition. It is not a signature of rc4, and rc4 does not
misrepresent it as such. Where preserved, it should be archived explicitly as
an rc3 witness.
