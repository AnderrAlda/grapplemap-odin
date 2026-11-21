# Architecture

What exists or is decided today. Pieces that arrive later are marked with their phase. Decisions live in ADRs
(`docs/adr/`); the behaviour of the original we reimplement is in [`docs/original.md`](original.md).

## Packages and dependency direction

| Package | Role | Phase |
|---|---|---|
| `src` (`main`) | entry point: window, `App_State`, main loop, tracking allocator (`src/main.odin`) | placeholder today |
| `src/core` | data model, `GrappleMap.txt` parser, graph, transforms, interpolation, playback. No raylib, no file system: parsers take `[]byte`/`string` (`src/core/CLAUDE.md`) | 2 |
| `src/render` | draws `core` structures read-only, never mutates them (`src/render/CLAUDE.md`) | 3 |
| `src/ui` | navigation, history, filters, camera presets; logic separated from drawing (`src/ui/CLAUDE.md`) | 3+ |
| `src/editor` | editing of our own graph (own JSON format), commands with undo/redo (`src/editor/CLAUDE.md`) | 6 |

```
main ──► ui ──► render ──► core
  │       └───────────────► core
  └──► editor ────────────► core
```

- `core` imports none of `render`, `ui`, `editor` (rule in `CLAUDE.md` and `src/core/CLAUDE.md`).
- `render` only reads `core`. Whether `ui` and `editor` may import each other is decided when phase 3/6 needs it.
- Imports go through the collection `app` (`-collection:app=src`, `build.sh:6`): `import "app:core"`.

## Data flow

```
GrappleMap.txt (bytes) ──► parser ──► graph (arena) ──► transforms / interpolation ──► render
                          core       core              core                         render (f32)
```

1. **Bytes**: `main` reads the file and hands `core` a `[]byte`. The format is `docs/original.md` §1.
2. **Parser** (phase 2): base62 positions decoded to `f64` exactly as the original (`docs/original.md` §1.3);
   errors are values (`or_return`), never `panic` on malformed input.
3. **Graph** (phase 2): named positions and transitions, node matching by reorientation, anonymous nodes
   (`docs/original.md` §2). Stored in an arena with indices instead of pointers.
4. **Transforms and interpolation** (phase 2): `mirror`, `swap_players`, reorientations, canonical orientation,
   `between`, playback frames (`docs/original.md` §5, §6). Computed in `f64` ([ADR 0003](adr/0003-numeric-precision.md)).
5. **Render** (phase 3): converts the positions of the current frame to `f32` when uploading them to raylib.
   How the original's axes map to raylib's is ADR 0004 (#44).

## Memory strategy

- **Graph in an arena** (`core:mem/virtual`): built once per load, freed in one go. Inside it, references are
  indices into slices, never pointers, so the graph can be copied, serialized and checked without fix-ups.
- **Per frame**: `context.temp_allocator`, emptied with `free_all` at the end of each frame.
- **Leaks**: debug builds wrap the default allocator in `mem.Tracking_Allocator` and report leaks at exit
  (`TRACK_LEAKS :: ODIN_DEBUG`, `src/main.odin:13,28-45`); tests run under the tracking allocator of `core:testing` and,
  on Linux and macOS, AddressSanitizer (`sanitize_flag`, `build.sh:14-20`; skipped on the macOS CI runners).
  Target: zero leaks.
- **Global state**: minimal. `App_State` is passed explicitly.

## Test strategy

| Kind | Where | Runs |
|---|---|---|
| Unit, property, round-trip, robustness | `core` (TDD: the failing test first), `ui` logic | `./build.sh test`, part of `./build.sh ci` |
| Fidelity (sample) | Odin tests over the committed oracle sample `tests/fixtures/oracle/` (#35) | `./build.sh test`, locally, no Docker (phase 2) |
| Fidelity (full DB) | Odin tests over the full oracle dump, downloaded from the `oracle` workflow's artifact | CI only (phase 2) |
| Oracle self-check | the dumper over `tools/oracle/dump/testdata/` | `./build.sh oracle --test` (Docker) |
| Golden images | our viewer against `tests/golden/` | `./build.sh test-golden` (phase 3) |
| Hook tests | `tests/hooks/*.test.sh` | `./build.sh test` |

- The **oracle** is the original GrappleMap, pinned and built in Docker; it is the source of truth
  ([ADR 0002](adr/0002-oracle.md), `tools/oracle/README.md`).
- Only a **sample** of its output is committed. The full dump (~0.54 GB) is generated in CI and checked against
  committed hashes (`tests/fixtures/oracle/FULL.sha256`); both pending (#35, #36). `./build.sh ci` never needs Docker.
- What must match bit for bit and what may use a tolerance: [ADR 0003](adr/0003-numeric-precision.md).
- Every build and test uses `-vet -strict-style -warnings-as-errors` (`build.sh:7`); benchmarks (`cmd_bench`) do not.

## ADRs

- [0001](adr/0001-registro-de-decisiones.md) Architecture decision records.
- [0002](adr/0002-oracle.md) Oracle: the original built in Docker as the source of truth.
- [0003](adr/0003-numeric-precision.md) Numeric precision.
- 0004–0006 (axes and units, own JSON format, body rendering): #44.
