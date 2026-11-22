### Added
- `core`: reorientations (`Reorientation`, `Position_Reorientation`, `rotate`, `apply`, `reorient`) and canonical orientation (`normal_rotation`, `normal_translation`, `canonical_reorientation_*`, `orient_canonically_*`), in the original's operation order (#140).
- Fidelity: `orient_canonically_with_mirror`/`…_without_mirror` compared bit for bit against `ops.ndjson`, which measures the trig bits. Result: the original's `atan2`/`sin`/`cos` are correctly rounded; Odin's `atan2` and a modern libm's are not (ADR 0003, #161) (#140).
