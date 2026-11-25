### Added
- `core.export_txt`: writes a graph as `GrappleMap.txt` exactly like the original's `save` (named positions, then
  transitions; `round((x + 2) * 1000)` in base62, 4 × 69 layout), rejecting with `Export_Error` what could not load
  back (description line starting with a space or holding `'\n'`, empty description, duplicate position description,
  coordinate outside 0…3843 or NaN); `export_txt(load_graph(DB))` is the DB byte for byte (#145).
- Fidelity tests load the DB graph once per test binary (`shared_graph`) (#145).
