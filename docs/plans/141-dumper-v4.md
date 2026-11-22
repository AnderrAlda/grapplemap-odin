# Plan: #141 test(oracle): dumper v4 with save and compose/inverse
Spec: docs/specs/phase-2-core.md (deliverable 5, "Oracle data")

## Pasos
1. `tools/oracle/dump/dump.cpp`: `DUMPER_VERSION` "3" → "4".
2. **`save`**: serialize `save(g, std::ostream&)` (`reference/GrappleMap/src/persistence.hpp:11`) into a string once.
   - Full mode (no `--sample`): write it as `save.txt` through `Staged_Files` (same atomic rename as the other files).
   - Both modes: `meta.json` gets `save_md5` (the original's `md5.hpp`, already linked and used for `db_md5`; no
     SHA-256 exists in the dumper or the original, and adding one would be new code or a new dependency) and
     `save_equals_db` (bytes equal to the DB input). The spec's `save_sha256` becomes `save_md5`: it is an equality
     check against our own output, not a security boundary; the PR updates the spec's wording (two mentions).
3. **`compose.ndjson`**: one line per transition in file order (filtered by the sample's transition blocks like
   `graph.ndjson`): `block`, `seq`, `inverse_from` = `inverse(e.from.reorientation)`, `inverse_to`,
   `compose_from_to` = `compose(e.from.reorientation, e.to.reorientation)`, and `compose_inverse_from_to` =
   `compose(inverse(e.from.reorientation), e.to.reorientation)` (the form `follow` uses, §6.2), each written with the
   existing `reorientation(Json&, PositionReorientation const&)` (`dump.cpp:211`). Inserted in the file order after
   `between.ndjson`.
4. Header comment of `dump.cpp` (file list, line 9) updated.
5. Testdata: run `./build.sh oracle --test`; review by hand the new `testdata/basic/compose.ndjson`, `save.txt` and the
   `meta.json` fields (the two transitions of `basic.txt`: one plain translation, one mirror end, so `inverse`/`compose`
   are checkable by hand from §5.4) and the `sample_*` expected outputs; commit them with the reason in the PR.
6. Regenerate: `./build.sh oracle --sample` (sample + `MANIFEST.sha256`), `./build.sh oracle --update-full-hashes`
   (`FULL.sha256`). Check the sample stays < 2 MB (`du -b`) and that every file except `meta.json`, `compose.ndjson` and
   `save.txt` is byte-identical to v3 (`--full` before/after, `cmp`).
7. Docs: `tools/oracle/README.md` (file table, `dumper_version` 4, sizes, note that `save.txt` is full-only);
   ADR 0005 "Open points" first bullet closed with the result of `save_equals_db` on the real DB; `docs/original.md`
   §5.7 second bullet closed (compose/inverse dumped). `changelog.d/141-dumper-v4.md`.
8. `./build.sh ci` (does not need Docker) and the `oracle` workflow green on the PR (it triggers on `tools/oracle/**`).

## Ficheros a tocar
`tools/oracle/dump/dump.cpp`, `tools/oracle/dump/testdata/*/` (expected outputs), `tests/fixtures/oracle/*`
(regenerated only by `./build.sh oracle`), `tests/fixtures/oracle/FULL.sha256`, `tools/oracle/README.md`,
`docs/adr/0005-json-format.md`, `docs/original.md` (§5.7 only), `docs/specs/phase-2-core.md` (`save_sha256` →
`save_md5`), `changelog.d/141-dumper-v4.md`.
Not touched: `reference/GrappleMap`, `tests/golden/`, `tests/fixtures/oracle/images/` (`--sample` never writes it),
`src/`, CI workflows.

## Tests a escribir primero
`testdata/basic/` expected `compose.ndjson` and `meta.json` fields written by hand from §5.4 before running the new
dumper, so `./build.sh oracle --test` fails first and then passes.

## Riesgos
- `save` order or bytes differ from the DB (`save_equals_db = false`): not a dumper bug; record it in ADR 0005 and in the
  PR (deliverable 9 compares with `save.txt`, not with the DB).
- Dumper's own arithmetic: none new (only calls into the original), so `-ffp-contract=off` is not at stake.
- Docker runs emulated on Apple Silicon (slow); the full dump takes ~15 s on amd64. Run on the amd64 server.
- If the image or the pin fails to build: stop and escalate (ADR 0002 d7).

## Criterio de hecho
`./build.sh oracle --test` green; sample and hashes regenerated and committed; `oracle` workflow and CI green on the
PR's HEAD; sample < 2 MB; v3 files unchanged byte for byte; docs updated; `code-reviewer` (opus) without blockers; PR
labels `type:test`, `area:infra`, `phase-2`, milestone «Fase 2: Núcleo de datos». Hand-written lines < 400
(regenerated fixtures do not count).
