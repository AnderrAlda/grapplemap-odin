# core
- NUNCA importar `render`, `ui` ni `editor`. Sin raylib, sin sistema de archivos (los parsers reciben `[]byte`/string).
- TDD obligatorio: primero el test que falla. Tests de propiedades, round-trip, robustez y fidelidad (ver docs).
- Errores: enum/union de error por paquete + `or_return`. Nada de `panic` por entrada malformada.
- Datos del grafo en arena (`core:mem/virtual`); índices en vez de punteros.
- Fidelidad: no "corregir" datos del original. Tolerancias de float explícitas y justificadas.

## Ficheros
- `types.odin`: `V3`, `Joint` (23, orden del original), `Player`, `Position`, tablas de articulaciones y segmentos, constantes verbatim.
- `errors.odin`: unión `Error` (`nil` = éxito) con los errores propios y `mem.Allocator_Error`.
- `parse.odin`: parser de `GrappleMap.txt` (`parse_db` → `[]Sequence`, `sequences_destroy`, `tags_in_desc`, `properties_in_desc`); layout estricto 4 × 69 (ADR 0005 d8), primer error con línea 1-based y bloque.
- `*_test.odin`: tests del paquete, uno por fichero.
- Tablas indexadas en tiempo de ejecución: `@(rodata) NAME := ...`, no `::` (Odin no indexa una constante con un índice variable).
