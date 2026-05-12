# Milkdrop preset ingestion — counsel review brief

**Status:** Draft for outgoing counsel communication. Authored
2026-05-12 in support of Decision I.1 in
[`MILKDROP_STRATEGY.md`](MILKDROP_STRATEGY.md) §3 and
[`D-111`](DECISIONS.md) in `DECISIONS.md`. **Not legal advice.** The
brief presents facts and Phosphene's proposed posture for counsel's
review; counsel's response is not to be committed to this repository
(privileged correspondence stays out of tree).

---

## 1. Subject

Phosphene is a macOS music-visualization application (MIT-licensed,
public repository at `github.com/hoaxpoet/phosphene`). The project
plans to ingest derivative works from a curated, third-party
collection of Milkdrop visualizer presets and ship them as
Phosphene-native presets under Phosphene's MIT licence. This brief
asks counsel to validate the proposed licensing posture before any
derivative content is committed to a public branch.

## 2. Background — what is being ingested

**Milkdrop** is a music-visualization plug-in originally released by
Ryan Geiss in 2001. Milkdrop "presets" are small text files
(typically 1–20 KB) describing per-frame numerical equations and,
in later format versions, embedded pixel-shader source code. Each
preset defines a single visualization behaviour. Over two decades,
the Milkdrop community has produced tens of thousands of presets.

**The source pack at issue** is `presets-cream-of-the-crop`, a
curated collection of 9,795 presets compiled by an individual using
the handle "ISOSCELES." The pack has been distributed publicly since
2020 and has been adopted as the default preset library for
**projectM** — the open-source cross-platform Milkdrop-compatible
renderer maintained at `github.com/projectM-visualizer`.

Source URLs:

* Pack repository (Phosphene's intended source):
  `https://github.com/projectM-visualizer/presets-cream-of-the-crop`
* Pack's stated license file:
  `https://github.com/projectM-visualizer/presets-cream-of-the-crop/blob/master/LICENSE.md`
* Original pack release (Patreon, ISOSCELES):
  `https://www.patreon.com/posts/pack-nestdrop-91682111`
* Historical context (blog post, web archive):
  `https://web.archive.org/web/20240609162724/https://thefulldomeblog.com/2020/02/21/nestdrop-presets-collection-cream-of-the-crop/`

## 3. The pack's stated license posture

The pack's `LICENSE.md` file is reproduced in full (61 words):

> Milkdrop presets were, in almost all cases, not released under any
> specific license. Theoretically, each preset author holds the full
> copyright on any released presets. Since the presets were freely
> released and have been used in so many packages and applications in
> the past two decades, it is safe to assume them to be in the public
> domain.
>
> If any preset author doesn't want their own creation in this
> repository, please contact the projectM team and we will remove the
> preset(s) from future releases.

Key features of this posture:

* No SPDX-identifiable license assigned to the pack as a whole.
* Acknowledges individual preset authors retain technical copyright.
* Asserts a *de facto* public-domain status based on (a) decades of
  free public release and (b) widespread unchallenged reuse across
  derivative works.
* Establishes a takedown path: preset authors may contact the
  projectM team to have a preset removed from future releases.

## 4. Phosphene's intended use

Phosphene proposes to:

1. Select ~35 presets from the pack across three quality tiers.
2. **Transpile** each preset offline (not at runtime) from
   Milkdrop's `.milk` format into Phosphene-native Metal shader
   source code and a JSON metadata sidecar. This is a one-way
   conversion; the original `.milk` files are not redistributed.
3. **Modify** each transpiled preset to varying degrees depending
   on tier — from minimal (Classic Port tier: visual fidelity to the
   source) to substantial (Hybrid tier: Phosphene's ray-marching
   3D rendering integrated with Milkdrop-style feedback warp).
4. **Ship** the resulting `.metal` + `.json` files under Phosphene's
   MIT license as part of the Phosphene repository and any
   distributed binaries.

## 5. Proposed licensing posture (Decision I.1)

For each Milkdrop-derived preset shipped:

1. **License of distribution:** MIT (Phosphene's project license).
2. **Provenance metadata** is embedded in each preset's JSON sidecar:

   ```json
   "milkdrop_source": {
     "filename": "<original .milk filename>",
     "author": "<author from filename pattern, best-effort>",
     "theme": "<cream-of-crop theme directory>",
     "sha256": "<SHA256 of source .milk file>",
     "pack": "projectM-visualizer/presets-cream-of-the-crop"
   }
   ```

3. **User-visible attribution** in `docs/CREDITS.md`, with one entry
   per shipped preset enumerating source filename, original author
   (when discernible from the filename), and the pack reference.
   This file is required to be preserved in any redistribution and
   reachable from a user-visible "About" surface in any derivative
   product (the requirement is already documented in
   `docs/CREDITS.md`).
4. **Takedown protocol:** Phosphene commits to honoring takedown
   requests routed through the projectM team. If a preset author
   contacts projectM to have their work removed from the upstream
   pack, Phosphene will remove the corresponding derivative preset
   from Phosphene in the next release.

This posture mirrors the attribution pattern Phosphene already uses
for the **Open-Unmix HQ** and **Beat This!** machine-learning model
weights — both vendored under permissive licences with provenance
recorded in `CREDITS.md`. See
`https://github.com/hoaxpoet/phosphene/blob/main/docs/CREDITS.md`
for the existing pattern.

## 6. Alternatives considered

* **Dual-license** the derivative output as MIT + a separately
  stated "Milkdrop preset content used under the pack's curatorial
  posture" notice. **Rejected** as adding documentation surface
  without clarifying the legal posture — counsel review of the
  base posture is the more direct path to confidence.
* **Defer the entire Phase MD work track** until each preset
  author can be individually contacted for explicit licensing.
  **Rejected** as impractical: the pack contains 9,795 presets from
  many hundreds of authors over two decades; many authors are no
  longer reachable. Phosphene's intended subset is ~35 presets.
* **Run a runtime `.milk` interpreter** that loads pack files
  directly without producing derivatives. **Rejected** for unrelated
  engineering reasons (runtime safety, performance) but worth
  noting as it would shift the licensing analysis.

## 7. Specific questions for counsel

1. Is the pack's *de facto* public-domain assertion (two decades of
   free release + widespread unchallenged reuse + curator-managed
   takedown path) a sufficient legal basis under U.S. copyright law
   to ship transpiled derivatives of individual presets under
   Phosphene's MIT licence? If not, what additional steps are
   required?

2. The proposed posture relies on attribution via embedded
   provenance metadata and a `CREDITS.md` file. Does this discharge
   any attribution-related obligations that may apply, including:
   (a) moral-rights / paternity-rights claims under non-U.S.
   jurisdictions where users may run Phosphene; (b) any implied
   contractual attribution norms in the Milkdrop / projectM
   community of practice? If not, what attribution form would
   discharge these?

3. Is the proposed takedown protocol — honoring requests routed
   through the projectM team rather than maintaining direct contact
   channels with original authors — sufficient as a remediation
   mechanism? Or should Phosphene establish a direct takedown contact
   path (e.g. an email address or GitHub issue label) advertised in
   `CREDITS.md`?

4. Phosphene modifies the transpiled presets to varying degrees,
   including substantial rewrites for the Hybrid tier (combining
   Milkdrop-style feedback warp with Phosphene's own ray-marching
   3D rendering). Does the extent of modification affect the
   attribution requirements or the underlying licensing analysis?

5. Are there jurisdictional considerations (EU moral rights, UK
   database rights, DMCA notice-and-takedown procedure) that change
   any of the above analyses for users in those jurisdictions?

6. If counsel concludes the proposed posture is insufficient, which
   of the following alternatives is most likely to be viable, and
   what additional steps would each require:
   (a) shipping only presets whose original authors can be
       individually contacted and have granted explicit license;
   (b) dual-licensing as in §6;
   (c) deferring the work entirely;
   (d) some other approach counsel can identify?

## 8. Source documents counsel may want

All in the Phosphene repository (`github.com/hoaxpoet/phosphene`):

* `docs/MILKDROP_STRATEGY.md` — the full Phase MD strategy
  document, including the decision context for the licensing
  posture in §3 Decision I.
* `docs/DECISIONS.md` D-111 — the recorded decision adopting
  posture I.1 with this counsel-review checkpoint.
* `docs/CREDITS.md` — the existing attribution patterns for
  Open-Unmix HQ and Beat This! ML weights, which the Milkdrop
  attribution is modelled on. The "Milkdrop preset attribution"
  section is presently a placeholder pending counsel sign-off.
* `docs/diagnostics/MD-strategy-pre-audit-2026-05-12.md` —
  empirical audit of the pack, including the count of files
  shipping embedded HLSL pixel-shader source vs. expression-language-
  only presets (relevant if counsel wants to understand exactly what
  Phosphene is transpiling vs. what it is leaving aside).

## 9. Project state at time of writing

* Strategy and decisions for Phase MD are signed off and committed.
* Pre-counsel-review increments (MD.1 grammar audit) can run and
  commit no licensed content; the audit cites the pack as a corpus,
  not as committed content.
* Post-counsel-review increments (MD.2 transpiler, MD.5 first
  ports, MD.6 / MD.7 follow-ons) are **gated** on counsel sign-off
  per D-111.

## 10. Authoring note

This brief was drafted by Phosphene's lead developer with AI
assistance. It is intended as a working summary to enable an
efficient initial conversation with counsel; it is not itself
legal analysis and should not be relied on as such. Counsel's
response is privileged and should be retained in counsel's records
or in a non-public channel — please do not respond by committing to
this repository.
