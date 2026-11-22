### Added
- `src/core` test: `parse_db` under allocation failure at every allocation point, on a valid file and on one ending in a `Bad_Base62_Digit`: `Out_Of_Memory` (or the parse error), no leak, no bad free (#151).
