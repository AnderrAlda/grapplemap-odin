### Added
- `tests/fidelity/`: the body tables of `core` vs the oracle's `body.json` (bit for bit), and a seeded mutation test
  over the real DB (truncation, byte flip, line swap) where `parse_db` must never panic or leak (#138).
