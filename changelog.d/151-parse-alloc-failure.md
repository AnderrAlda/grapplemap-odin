### Added
- `core`: test of `parse_db` failing each allocation through its `allocator` in turn, on a valid file and on one ending in a `Bad_Base62_Digit`: `Out_Of_Memory` (or the parse error), no leak, no bad free (#151).
