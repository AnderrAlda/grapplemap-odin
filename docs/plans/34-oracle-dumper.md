# Plan: #34 ci: oracle dumper and ./build.sh oracle (PR 1 of 2)
Spec: docs/specs/phase-1-original-research.md (deliverable 3, "Dump format", "Full dump")
The issue does not fit one PR <400 lines. **PR 1 (`Refs #34`)**: infrastructure + `meta`, `sequences`, `graph`, `body`. **PR 2 (`Closes #34`, next batch)**: `ops`, `between`, `playback`, `spring`. Tick the issue checklist per PR.
## Pasos (PR 1)
1. `tools/oracle/dump/dump.cpp` (+ a minimal own JSON helper, no new deps): always load with `loadGraph(std::istream&)` (`persistence.cpp:171`), no `.index`; walk blocks by index; write NDJSON in a fixed order: quantized positions `q` (integers 0…3843, decoding documented), doubles with `%.17g`; correct JSON escaping of `\n`, UTF-8 and quotes.
2. `graph.ndjson`: nodes (including anonymous ones from `find_or_add`, `graph.cpp:235`, block of origin `null`) and transitions `{from,to,reorientation_from,reorientation_to}`; the `.index` from `grapplemap-indexer` run on a **copy** of the DB inside the container.
3. `body.json`: `jointDefs`, segments, colors per player, geometry constants from `playerdrawer.cpp`/`rendering.cpp`.
4. `meta.json`: submodule commit (env from `build.sh`), md5 of `GrappleMap.txt`, dumper version, `/oracle/VERSIONS`, counts (blocks, positions, total nodes, anonymous) and errors reported by the original.
5. `tools/oracle/Dockerfile`: new stage after the original build compiling the dumper with `g++ -std=c++1y -O3 -DNDEBUG -ffp-contract=off -I/oracle/src`, linking the `common` objects (`SConstruct:33`) and the `cmdlibs`; `Dockerfile.dockerignore` lets `tools/oracle/dump` through. The submodule is never dirtied.
6. `build.sh`: `cmd_oracle` with `--full` (docker build + run, output to `build/oracle/full/`, wipe and regenerate → idempotent, clear error without Docker/daemon) and `--test` (dumper over `tools/oracle/dump/testdata/*.txt`, diff against committed expected output). `--sample|--images|--update-full-hashes` → error "arrives with #35". Check `build/` is git-ignored.
7. Docs: `tools/oracle/README.md`, `CLAUDE.md` (Comandos line: `oracle`), CHANGELOG.
## Ficheros a tocar
`tools/oracle/dump/*`, `tools/oracle/dump/testdata/*`, `tools/oracle/Dockerfile`, `tools/oracle/Dockerfile.dockerignore`, `tools/oracle/README.md`, `build.sh`, `CLAUDE.md`, `CHANGELOG.md`. Not `.github/workflows` (that is #36).
## Tests a escribir primero
Hand-written `testdata/` (description with literal `\n`, UTF-8, quotes, a named position, a transition, an anonymous endpoint) + expected output; `./build.sh oracle --test` red before the dumper, green after.
## Riesgos
- Oracle timebox: if the dumper cannot link against the `.o` files after a reasonable attempt, stop and ask (spec).
- `./build.sh ci` does not use Docker; put the evidence of `--test`/`--full` in the PR (output and counts: 2,086 blocks, 8,323 positions; two consecutive `--full` runs with the same `sha256sum`).
- Overlaps `build.sh`/`CHANGELOG.md` with #20: whoever opens the PR second rebases.
## Criterio de hecho
Issue items for PR 1 met with evidence, `./build.sh ci` green, reviewer (opus) without blockers.
