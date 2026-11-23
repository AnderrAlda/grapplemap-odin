### Added
- `core`: reorientations (`Reorientation`, `Position_Reorientation`, `rotate`, `apply`, `reorient`) and canonical orientation (`normal_rotation`, `normal_translation`, `canonical_reorientation_*`, `orient_canonically_*`), in the original's operation order, with the correctly rounded `cr_atan2`/`cr_sin`/`cr_cos` (#140).
- Fidelity: `orient_canonically_with_mirror`/`…_without_mirror` compared bit for bit against `ops.ndjson`: 0 mismatches on the sample (62 positions) and on the full dump (8,323) (#140).
