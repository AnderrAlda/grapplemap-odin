### Added
- `core`: node matching (`basically_same`, `head2head`, `is_reoriented` with the original's pre-filter and four attempts in order), bit-identical to the original's `reorientation_from`/`_to` on every transition of the DB (#169).
- Fidelity: `is_reoriented(node, sequence end)` compared bit for bit against `graph.ndjson`: 0 mismatches on the sample (49 transitions) and on the full dump (1,485 transitions, 2,970 ends) (#169).
