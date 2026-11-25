### Added
- `core`: the original's lookups by name (`node_by_desc`, `step_by_desc`, `named_entity`), quirks included; an out-of-range index or a `p<N>` that overflows is "not found" instead of the original's undefined behaviour (#143).
