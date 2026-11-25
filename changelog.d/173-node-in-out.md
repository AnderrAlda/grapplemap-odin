### Added
- `core`: each graph node's `incoming`/`outgoing`/`in_out` step lists, in the original's order (`Graph::compute_in_out`) (#173).
- `tests/fidelity`: `load_graph` over seeded mutants of a 60-block sample of the DB (named positions + transitions):
  an error or a graph with every edge end and step in range, no panic, no leak (#173).
