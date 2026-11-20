# render
- Aislado del modelo de datos: consume estructuras de `core` de solo lectura; nunca las muta.
- Sin números mágicos: constantes con nombre o config. Frame: `context.temp_allocator` + `free_all`.
- Cualquier cambio visual: capturas en el PR; golden images solo con `./build.sh test-golden --update` y OK explícito.
- Mantén el código portable a wasm (GLSL 330 → verificar variante ES al llegar a la fase 7).
