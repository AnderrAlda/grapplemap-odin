# Plan: #127 docs(original): settle §7.6 channel order and §4.2 on-screen camera with the oracle images
Spec: docs/specs/phase-1-original-research.md (sections 4 and 7 of `docs/original.md`); evidence in `tools/oracle/README.md` "Reference images" and `tests/fixtures/oracle/images/` (#130).
## Pasos
1. Read `tools/oracle/README.md` (reference images: the OSMesa probe, pixel values, camera check, softpipe), `tests/fixtures/oracle/images/meta.json`, ADR 0004 (its settled open point), and in `docs/original.md` §4.2 (the `[unverified]` on screen, line ~695), §7.6 (channel order, line ~1345, and the "will run" wording), §7.2 (player colors) and any other sentence that defers to "the oracle images" (grep `oracle image`, `on screen`, `BGR`, `channel`).
2. Check the evidence yourself, do not copy it: read a pixel of a player of known color in `p96-480x360.png` (e.g. `python3 -I` with only the standard library: `zlib` + PNG chunk parsing, script in the scratchpad, not committed) and check `src/images.cpp:89` and the `yaw = 0` derivation of §4.2 against the image. If what you see disagrees with the README, stop and report.
3. Edit, citing the README section and the image file as evidence:
   - §7.6: drop the `[unverified]`; state that `OSMESA_RGB` is R, G, B in memory, the swap writes BGR, so player 0 `(1,0,0)` shows blue and player 1 `(0.15,0.15,1)` shows red in the PNGs (with the pixel values); change "will run" to the present tense; one line: with Mesa 20.0.8 the default llvmpipe driver corrupts `OSMESA_RGB` renders and is not deterministic, so the oracle renders with softpipe (`GALLIUM_DRIVER`, recorded in `meta.json`).
   - §4.2: drop the `[unverified]` on screen: with `yaw = 0` world `+x` is screen right and the eye is on the `+z` side, confirmed by the images (blocks 96 and 267).
   - §7.7 (input for ADR 0006 / phase 3): one line if it helps, saying a pixel comparison against these PNGs must swap red and blue back. Nothing else.
4. Changelog fragment `changelog.d/127-original-images-answers.md` (`### Changed`).
## Ficheros a tocar
`docs/original.md` (§4.2, §7.6, possibly one line in §7.7), `changelog.d/127-original-images-answers.md` (new). Not `tools/oracle/`, `docs/adr/`, `.github/` (#36 in the same batch), `reference/`, `tests/`.
## Tests a escribir primero
n/a (docs). Every `file:line` cited is checked against the pinned submodule; the pixel values are re-read from the committed PNG (command in the PR body).
## Riesgos
- Docs-only evidence for #36: **open the PR as draft but do not mark it ready until #36 is merged**. Then `git merge origin/main` (no force-push), push, and paste in the PR body the list of checks of the new HEAD (`gh pr checks`) showing that the `oracle` workflow did not run. MAIN will ask for it.
- Do not rewrite §7.6 or §4.2 beyond the points of #127: wording polish of other sections is in their tech-debt issues.
## Criterio de hecho
No `[unverified]` left about channel order or on-screen camera orientation; the answers cite the evidence; `./build.sh ci` green; reviewer (sonnet) without blockers; docs-only evidence for #36 in the PR body. `Closes #127`.
