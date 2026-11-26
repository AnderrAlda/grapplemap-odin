# render
- Aislado del modelo de datos: consume estructuras de `core` de solo lectura; nunca las muta.
- Sin números mágicos: constantes con nombre o config. Frame: `context.temp_allocator` + `free_all`.
- Cualquier cambio visual: capturas en el PR; golden images solo con `./build.sh test-golden --update` y OK explícito.
- Mantén el código portable a wasm (GLSL 330 → verificar variante ES al llegar a la fase 7).

## Ficheros
- `camera.odin`: cámara del original en `f64` (`M` column-major `m[4·c + r]`, `mat_mul`/`xrot`/`yrot`/`translate`/`perspective` con el orden de operaciones de `math.hpp`; trig con `core.cr_sin`/`cr_cos`, nunca `core:math`). `model_view` = `T(0,0,−z)·X·Y·T(−offset)` asociando a la izquierda. `to_raylib` pasa a `rl.Matrix` con una conversión a `f32` por elemento (`m[r, c] = f32(m[4·c + r])`).
