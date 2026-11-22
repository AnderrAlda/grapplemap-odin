# Plan: #139 feat(core): trig-free transforms (mirror, swap, heading, center, between)
Spec: docs/specs/phase-2-core.md (deliverable 3) · docs/original.md §4.3, §5.1, §5.2, §5.6, §6.1 · ADR 0003

## Pasos
1. **`src/core/types.odin`**: `V2 :: [2]f64` (the `xz` result of `heading`, `src/math.hpp:110`). Nothing else changes.
2. **`src/core/transform.odin`** (new). Every procedure is pure and takes and returns values, so it allocates nothing.
   The operation order is the original's and has no rewrites (ADR 0003 decision 4: no FMA, no reassociation):
   - `mirror_v3(v: V3) -> V3`: `{-v.x, v.y, v.z}` (`src/positions.hpp:36`). Negation is exact, and `+0` becomes `-0`.
   - `mirror(p: Position) -> Position`: per player, `r[pl][mirror_joint(j)] = mirror_v3(p[pl][j])` for every joint.
     That is the same permutation as the ten `swapLimbs` `std::swap`s (`src/positions.cpp:77-89,130-136`), and it
     reuses `mirror_joint` from `types.odin`. The players are not swapped.
   - `swap_players(p: Position) -> Position`: returns `{p[1], p[0]}`. The original swaps in place
     (`src/positions.hpp:68-71`); returning a copy keeps the same bits and is the Odin idiom.
   - `heading(p: Position) -> V2`: `d := p[1][.Core] - p[0][.Core]; return {d.x, d.z}`: the full `V3` subtraction,
     then `xz` (`src/positions.hpp:132-135`).
   - `center(p: Position) -> V3`: `(p[0][.Core] + p[1][.Core]) / 2`, the `between(V3, V3)` midpoint
     (`src/math.hpp:193`, `src/positions.hpp:142-145`). Odin's array operators act per component, like `BasicV3`.
     The two-argument midpoint is not exported, so that it can't be confused with `between(Position…)`.
   - `between(a, b: Position, s: f64 = 0.5) -> Position`: per joint, `a[j] + (b[j] - a[j]) * s` (§6.1). It is not
     clamped, and it is not rewritten as `a·(1 − s) + b·s`.
   - Doc comment on each procedure with its source line in the original. `normalRotation`, `normalTranslation`,
     `xzCenter` and anything with trigonometry belong to #140.
3. **Fidelity, `tests/fidelity/ops_test.odin`** (new): parse the whole DB once (`load_db` + `parse_db`), then stream
   `ops.ndjson` with `ndjson_each`. Each record `{block, pos}` takes `seqs[block].positions[pos]` and compares, bit for
   bit with `expect_bits`, `mirror`, `swap_players`, `heading` (2 values) and `center` (3 values). `orient_canonically_*`
   is decoded and not compared (#140). Like `sequences_test.odin`:
   - `block`/`pos` must be in range, and the records in order;
   - the test stops at the first differing record;
   - it asserts `compared == lines > 0`;
   - on the full dump (`oracle_dir() != DEFAULT_ORACLE_DIR`), it checks that the total number of records equals the
     total number of positions (8,323).
4. **Fidelity, `tests/fidelity/between_test.odin`** (new): stream `between.ndjson`. Each record `{block, seq, pos, s}`:
   - checks that `seqs[block]` is a transition with `pos + 1 < len(positions)`;
   - computes `between(positions[pos], positions[pos + 1], s)` and compares it bit for bit with `position`;
   - checks that `s ∈ {0.25, 0.5, 0.75}` (bits);
   - with `compared == lines > 0`, and on the full dump the total equals 3 × Σ(len(positions) − 1) over the
     transitions.
   `seq` is the original's `SeqNum` and isn't compared (no graph yet; #142).
5. Docs: `src/core/CLAUDE.md` ("Ficheros": `transform.odin`), `docs/architecture.md` only if its fidelity table lists
   the files per comparison (otherwise not touched), and `changelog.d/139-trig-free-transforms.md`.
6. `./build.sh ci`. Once by hand, run `GM_ORACLE_DIR=<full dump> ./build.sh test` on the full dump
   (`gh run download <latest successful oracle run on main> -n oracle-full-dump -D build/oracle-full`), with the result
   in the PR.

## Ficheros a tocar
`src/core/types.odin` (only `V2`), `src/core/transform.odin`, `src/core/transform_test.odin`,
`tests/fidelity/ops_test.odin`, `tests/fidelity/between_test.odin`, `src/core/CLAUDE.md`,
`changelog.d/139-trig-free-transforms.md` (+ the plan, `docs/plans/139-trig-free-transforms.md`).
Not touched: `build.sh` (`tests/fidelity` is already in `TEST_PKGS`), `.github/`, `tests/fidelity/{oracle,ndjson}.odin`
(if the harness is missing something, the worker escalates), or the files of #147.

## Tests a escribir primero
`src/core/transform_test.odin` (TDD: red first with stubs that return `{}`):
- `mirror` is an involution bit for bit on a hand-written position. `mirror` of `x = +0` gives `-0` (bits). Left and
  right are swapped (for example `LeftHand` ↔ `RightHand` with `x` negated), `Core`/`Neck`/`Head` keep their index,
  and the players are not swapped.
- `swap_players` is an involution. `heading(swap_players(p)) == -heading(p)` and `center(swap_players(p)) == center(p)`
  (bits).
- `heading` uses `Core` (a different `Head` doesn't change it); `center` keeps `y`.
- `between`:
  - `s = 0` turns `-0` into `+0` when `b ≥ 0`, as §6.1 says;
  - `s = 1` is not bit-equal to `b` in at least one case: take the frames 5/6 case of
    `tools/oracle/dump/testdata/basic/playback.ndjson`, or find a pair of doubles and pin it;
  - `s = 2` and `s = -1` extrapolate (no clamp);
  - one value where `a + (b − a)·s` differs from `a·(1 − s) + b·s`, to pin the formula.
Then `ops_test.odin` and `between_test.odin`. Check they can fail: changing a bit in a local copy of the sample
(`GM_ORACLE_DIR=<copy>`) makes them red, and so does swapping the order to `a·(1 − s) + b·s`. Neither change is
committed.

## Riesgos
- **FMA:** `a + (b − a) * s` is the textbook case for contraction. ADR 0003 says the pinned Odin doesn't contract at
  our build levels; the `between` fidelity test, in debug with ASan and on both CI targets, is what guards it.
- **Signed zero:** `-0`/`+0` differ by bits. Don't normalize anything.
- **Positions:** the dump uses the graph's positions (`g[SeqNum]`), while the test uses the parse's. #138 showed they
  are the same bits (`sequences.ndjson`). If they ever differed, it is an escalation, not a workaround.
- **Cost on the full dump:** `ops.ndjson` is 93 MB and `between.ndjson` 52 MB. They are streamed line by line with
  `free_all` of `context.temp_allocator` per line; no file is ever held whole in memory.
- **Size:** ~350 hand-written lines expected. If it goes over 400, `between` (procedure + tests) goes to a second
  stacked PR.

## Criterio de hecho
- `./build.sh ci` green locally and in CI (linux + macOS).
- The full dump run by hand is green, and the result is in the PR.
- No vacuous test.
- `code-reviewer` (opus, `src/core`) without blockers.
- Labels `type:feat`, `area:core`, `phase-2`; milestone «Fase 2: Núcleo de datos»; `Closes #139`.
- Worker model: opus (fidelity in `core`).
