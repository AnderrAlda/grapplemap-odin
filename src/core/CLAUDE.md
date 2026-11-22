# core
- NUNCA importar `render`, `ui` ni `editor`. Sin raylib, sin sistema de archivos (los parsers reciben `[]byte`/string).
- TDD obligatorio: primero el test que falla. Tests de propiedades, round-trip, robustez y fidelidad (ver docs).
- Errores: enum/union de error por paquete + `or_return`. Nada de `panic` por entrada malformada.
- Datos del grafo en arena (`core:mem/virtual`); índices en vez de punteros.
- Fidelidad: no "corregir" datos del original. Tolerancias de float explícitas y justificadas.

## Ficheros
- `types.odin`: `V3`, `Joint` (23, orden del original), `Player`, `Position`, tablas de articulaciones y segmentos, constantes verbatim.
- `errors.odin`: unión `Error` (`nil` = éxito) con los errores propios y `mem.Allocator_Error`.
- `*_test.odin`: tests del paquete, uno por fichero.
