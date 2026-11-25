### Added
- `core`: the original's lookups by name (`node_by_desc`, `step_by_desc`, `named_entity`), quirks included; an out-of-range index or a `p<N>` that overflows is "not found", and an overflowing `l<N>` is not an `l` name, instead of the original's undefined behaviour or crash (#143).
