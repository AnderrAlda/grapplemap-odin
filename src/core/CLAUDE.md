# core
- NUNCA importar `render`, `ui` ni `editor`. Sin raylib, sin sistema de archivos (los parsers reciben `[]byte`/string).
- TDD obligatorio: primero el test que falla. Tests de propiedades, round-trip, robustez y fidelidad (ver docs).
- Errores: enum/union de error por paquete + `or_return`. Nada de `panic` por entrada malformada.
- Datos del grafo en arena (`core:mem/virtual`); índices en vez de punteros.
- Fidelidad: no "corregir" datos del original. Tolerancias de float explícitas y justificadas.

## Ficheros
- `types.odin`: `V2`, `V3`, `Joint` (23, orden del original), `Player`, `Position`, tablas de articulaciones y segmentos, constantes verbatim.
- `errors.odin`: unión `Error` (`nil` = éxito) con los errores propios y `mem.Allocator_Error`.
- `parse.odin`: parser de `GrappleMap.txt` (`parse_db` → `[]Sequence`, `sequences_destroy`, `tags_in_desc`, `properties_in_desc`); layout estricto 4 × 69 (ADR 0005 d8), primer error con línea 1-based y bloque.
- `transform.odin`: transformaciones sin trigonometría (`mirror_v3`, `mirror`, `swap_players`, `heading`, `center`, `between`); puras, sin asignar, orden de operaciones del original (ADR 0003 d4).
- `reorient.odin`: reorientaciones y orientación canónica (`rotate_v3`, `rotate`, `apply_v3`, `apply`, `reorient`, `reorient_v3`, `normal_rotation`, `normal_translation`, `canonical_reorientation_*`, `orient_canonically_*`); la única trigonometría de `core` (`math.sin`/`cos`/`atan2`, ver ADR 0003 «Open points» y #161).
- En `rotate_v3` los términos `0 *` y `+ 0` del producto matriz·vector del original NO se simplifican: deciden el signo de cero.
- `*_test.odin`: tests del paquete, uno por fichero.
- Tablas indexadas en tiempo de ejecución: `@(rodata) NAME := ...`, no `::` (Odin no indexa una constante con un índice variable).
- En los tests, los floats esperados van como literales `f64` calculados fuera de Odin: Odin pliega las expresiones constantes con más precisión que `f64` (`0.4 - 0.1` en un test no es el resultado en tiempo de ejecución).
