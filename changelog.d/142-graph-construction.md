### Added
- `core.load_graph`/`graph_destroy`: the graph of the original (named positions first, anonymous nodes for unmatched
  sequence ends, lowest-index match wins, edges in file order) in its own arena, with
  `Duplicate_Position_Description`; checked against the oracle's whole node numbering (#142).
