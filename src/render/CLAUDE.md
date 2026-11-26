# render
- Aislado del modelo de datos: consume estructuras de `core` de solo lectura; nunca las muta.
- Sin números mágicos: constantes con nombre o config. Frame: `context.temp_allocator` + `free_all`.
- Cualquier cambio visual: capturas en el PR; golden images solo con `./build.sh test-golden --update` y OK explícito.
- Mantén el código portable a wasm (GLSL 330 → verificar variante ES al llegar a la fase 7).

## Ficheros
- `camera.odin`: cámara del original en `f64` (`M` column-major `m[4·c + r]`, `mat_mul`/`xrot`/`yrot`/`translate`/`perspective` con el orden de operaciones de `math.hpp`; trig con `core.cr_sin`/`cr_cos`, nunca `core:math`). `model_view` = `T(0,0,−z)·X·Y·T(−offset)` asociando a la izquierda. `to_raylib` pasa a `rl.Matrix` con una conversión a `f32` por elemento (`m[r, c] = f32(m[4·c + r])`).
- `constants.odin`: constantes de la malla del original con su línea de origen (`ICO_X_F32`/`ICO_Z_F32` y las tablas del icosaedro en `f32`, ensanchadas a `f64` solo en tiempo de ejecución; `PILLAR_FACES`, subdivisiones, `FINE_JOINTS`, `FAT_TRIANGLES`, `OVERRIDE_RADIUS_DELTA`). Colores, radios y extremidades vienen de `core` (no se redefinen). `test_constants_match_oracle` las compara con el bloque `draw` de `tests/fixtures/oracle/body.json`.
- `mesh.odin`: malla de referencia (ADR 0006 d2) en `f64` con el orden de operaciones del original, a `f32` solo al escribir cada vértice (`Body_Mesh`: lista de triángulos no indexada, `positions`/`normals`/`colors` paralelos). `icosphere_make` = `make_icosphere` literal (aristas en orden de triángulo, punto medio añadido en el primer uso); `Mesh_Builder` guarda las icosferas 1 y 2 y la tabla `pillar_angles` (`cr_sin`/`cr_cos`; la entrada 10 no es `(0, 1)`). `emit_sphere` invierte cada triángulo (2, 1, 0); `emit_pillar` es la versión shader (dos triángulos por cara), posición `(from + (a·r)·sin) + (b·r)·cos`.
