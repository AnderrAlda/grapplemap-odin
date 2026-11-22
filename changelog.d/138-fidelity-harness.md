### Added
- `tests/fidelity/`: fidelity tests of `core` against the oracle (#138): `parse_db` of the real DB vs
  `sequences.ndjson` and `meta.json` (strings exact, coordinates bit for bit), over a streaming NDJSON reader.
  `GM_ORACLE_DIR` points them at the full dump; the default is the committed sample. A missing
  `reference/GrappleMap` submodule fails them.

### Changed
- `./build.sh test` fails a test on leaks and bad frees (`ODIN_TEST_FAIL_ON_BAD_MEMORY`, #151); `check`, `fmt` and
  `fmt-check` also cover `tests/fidelity/`.
- CI checks out the submodule in the `test` and `bench` jobs.
