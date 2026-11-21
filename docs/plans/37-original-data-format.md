# Plan: #37 docs(original): data format and parser of GrappleMap.txt (section 1)
Spec: docs/specs/phase-1-original-research.md (Deliverable 6.., L33; sections list L156–169; language L265; E2E L285)

## Context
Phase 2 will reimplement the parser in Odin with exact fidelity, without reading C++ again. Section 1 of
`docs/original.md` must therefore describe `GrappleMap.txt` and the original parser completely: structure,
encoding, grammar and every error path, each claim citing `file:line` of the submodule pinned at `032c8f9`.
`docs/original.md` does not exist yet, so this PR also creates it (header + section skeleton). Docs only, no Odin code.

Core sources (already located):
- `src/persistence.cpp:13-23` base62 table + `fromBase62` (throws via `error`, `src/util.hpp:68`)
- `src/persistence.cpp:31` `encoded_pos_size = 2·joint_count·3·2 + 4·5` (= 296 with 23 joints, `src/players.hpp`)
- `src/persistence.cpp:33-56` `decodePosition`: skips any `isspace` before each digit; value `(62·d0+d1)/1000`; `x−2, y, z−2` in `playerJoints` order
- `src/persistence.cpp:58-116` `readSeqs`: line starting with `' '` = position, else description line; `line_nr` bookkeeping; `abort()` on truncation (L89); `assert(!desc.empty())` (L77); exceptions rewrapped as `"at line N: …"` (L110-113)
- `src/persistence.cpp:118-151` writer (`round(d·1000)`, `assert i<4000`, 4 lines with 4-space indent) and `save` (L235+)
- `src/persistence.cpp:154-233` 1-position blocks → `NamedPosition`; `.index` + md5 path (only pointer to section 2)
- `src/metadata.cpp:37-53` `properties:` (whitespace-split; `detailed`/`bidirectional` read at `persistence.cpp:84-85`)
- `src/graph_util.cpp:151` `tags:`; literal `\n` in names: `metadata.cpp:69,89`, `persistence.cpp:317`
- `ref:`, `note`, `todo`: to be located (grep `src/*.cpp|hpp|js`); if a keyword has no parser support, say so explicitly.

## Pasos
1. Commit this plan as `docs/plans/37-original-data-format.md`.
2. Create `docs/original.md`:
   - Header: purpose, pin (`032c8f9`), citation convention (`src/x.cpp:L` relative to `reference/GrappleMap`),
     marker for unverified claims (`**[unverified]**` + why, e.g. "needs the oracle, #<dumper issue>").
   - TOC with the 10 spec sections; 2–10 as one-line "pending" stubs.
3. Write section 1 with subsections:
   1. **File layout**: blocks = ≥1 description lines followed by ≥1 positions; line classification by first byte; blank lines and `\r` (CRLF) behaviour as derived from code.
   2. **Description lines**: first line = name, literal `\n` as line-break marker; `tags:`, `properties:` (known values `detailed`, `bidirectional`), `ref:`, `note`, `todo` — who reads each, with citations.
   3. **Position encoding**: 23 joints × 2 players × 3 coords × 2 digits = 276 digits + 20 bytes of layout; joint order; base62 alphabet; quantization; offsets; resulting range (`[0, 3.843]` raw → x,z ∈ `[−2, 1.843]`, y ∈ `[0, 3.843]` m); note the mismatch with the writer's `i < 4000` assert.
   4. **Named positions vs. sequences** (1-position blocks), `line_nr` semantics; pointer to section 2.
   5. **Writer and round-trip**: exact output format of `save`; what is and isn't preserved (rounding, whitespace).
   6. **Grammar (EBNF)** of what the parser accepts (looser than what the writer emits — show both if they differ).
   7. **Errors and edge cases**: table *input → original behaviour → citation*: bad digit (exception, message text, which line number is reported), truncated position (`abort`, not an exception), position before any description (`assert`; check SConstruct for `NDEBUG` → otherwise UB), misaligned/extra whitespace in position lines (fixed `b += 296` vs. whitespace skipping), no trailing newline, empty file. Anything only derivable by running → `[unverified]`, to be confirmed with the dumper's `testdata/`.
   8. **Observed in the DB at the pin**: line length / charset checks over `GrappleMap.txt` with the exact shell command used (counts of blocks/positions deferred to section 10).
4. `CHANGELOG.md` Unreleased → Added: `docs/original.md` section 1 (#37). Root `CLAUDE.md` already lists `original.md`; no change. No ADR (no decision made; ADR 0003/0005 later).
5. `/pr`: draft PR, labels `type:docs area:core phase-1`, milestone "Fase 1: Investigación del original", `code-reviewer` (opus, core area) checking a sample of citations against the submodule.

## Ficheros a tocar
`docs/original.md` (new, ~250 lines) · `docs/plans/37-original-data-format.md` (new) · `CHANGELOG.md`. Submodule untouched.

## Tests a escribir primero
No `core` code → no Odin tests. Evidence instead, run and pasted in the PR:
- Citation check: every `src/…:L` in section 1 resolved with `sed -n 'Lp'` against `reference/GrappleMap` and matches the claim (a small one-off loop in the scratchpad, not committed).
- DB checks: `awk` over `GrappleMap.txt` — every position line is 4 spaces + 69 base62 chars, every position group has 4 lines, alphabet ⊆ `[a-zA-Z0-9]`, max decoded value ≤ the stated range.
- `git -C reference/GrappleMap status --porcelain` empty; `./build.sh ci` green.

## Riesgos
- Claiming runtime behaviour (assert/abort/UB, exact error messages and line numbers) without running the original → mark `[unverified]`, link to the dumper's `testdata/` for confirmation.
- Citations rot on a pin bump → convention in the header points to `reference/CLAUDE.md`.
- Scope creep into section 2 (node matching, `.index`): only pointers.
- Size: keep the hand-written diff < 400 lines.

## Criterio de hecho
- Section 1 covers all three checklist items of #37 (structure, EBNF + all parser errors, `file:line` everywhere, unverified marked).
- Evidence commands above pass; `./build.sh ci` green locally and in CI; CHANGELOG updated.
- `code-reviewer` finds no blocking discrepancies; PR in draft until then. No merge without Ander's OK.
