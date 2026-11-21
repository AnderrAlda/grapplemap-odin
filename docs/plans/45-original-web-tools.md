# Plan: #45 docs(original): web tools (section 8)
Spec: docs/specs/phase-1-original-research.md (section 8 of `docs/original.md`; input for phase 5)
## Pasos
1. Read `docs/original.md` §1-§7 headings and the parts §8 links to (style: `file:line` citations of the pinned submodule, `[unverified]` for anything not checked; link earlier sections, do not repeat them). Note the open points other sections left for §8: JS segment table not in sync with C++ (§3.2, `src/gm.js:89,117`), Babylon handedness / possible mirroring of the JS view (§3.2, §7.7).
2. Read in `reference/GrappleMap/src/` (read-only, ~6,200 lines in total; skim CSS):
   - Data pipeline: `dbtojs.cpp`, `js_conversions.{hpp,cpp}` (what the web tools load and in which format), `SConstruct` lines for `dbtojs`, `mkpospages` and the emscripten `libgrapplemap.js` (`SConstruct:47-55`).
   - `gm.js` (shared viewer code: Babylon scene, camera, players, playback in JS) and `graphdisplay.{js,css}` (graph view).
   - `search.{html,js}`: query language/filters (tags, properties, text), results, what clicking does.
   - `mkpospages.cpp`: the per-position pages (what each page shows, links in/out, images, naming).
   - `explorer.{html,js}`: navigation over the graph, what is shown around the current node.
   - `composer.{html,js}`: building sequences/drills, how they are stored or shared (URL?).
   - `editor.{html,js,css}` + `editor_canvas.cpp`/`cursor_canvas.cpp`/`editor.cpp` (web editor via emscripten): what it can edit and how it persists. Semantics of editing are §9 (#46): describe only the UX here and link §9.
   - `example-drills.html` (one line).
3. Write `## 8. Web tools`, one subsection per tool: purpose, inputs (files/URL params), main UX (controls, keys, mouse), what it computes vs. what it reads precomputed, and differences from the C++ viewer (segments, colors, camera, playback speed). Then "8.x Input for phase 5": features worth keeping, what is free to redesign, and open points.
4. Babylon handedness: check Babylon.js docs (scene `useRightHandedSystem` default) and cite the URL; if not verifiable, keep `[unverified]`. No other external sources.
5. Update Contents. Changelog fragment `changelog.d/45-original-web-tools.md` (`### Added`).
## Ficheros a tocar
`docs/original.md` (§8 and one Contents line), `changelog.d/45-original-web-tools.md` (new). Nothing under `reference/`; not `docs/adr/` or `docs/architecture.md` (#44 in the same batch).
## Tests a escribir primero
n/a (docs). Check every `file:line` citation against the pinned submodule before the PR (grep/sed of each one).
## Riesgos
- Size: the PR limit is <400 hand-written lines; the editor UX is the likeliest overflow. If it does not fit, move the editor's UX into §9 (#46) or a follow-up phase-1 docs issue and say so in the PR.
- Do not describe editing semantics (spring, bone-length constraint, persistence): that is §9.
- JS code may differ from C++ in subtle ways (as `gm.js` segments do): state differences explicitly, never assume the JS mirrors the C++.
- Insert §8 after §7 and before any later section; do not touch §1-§7 text except Contents.
## Criterio de hecho
Done-when of #45 met, citations verified, `./build.sh ci` green, reviewer (sonnet; opus if the reviewer rule picks it for fidelity content) without blockers.
