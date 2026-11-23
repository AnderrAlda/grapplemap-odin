# Assets de terceros
No se añade ningún asset (texturas, fuentes, HDRIs) sin registrar aquí su origen y licencia compatible.

| Asset | Origen (URL) | Licencia | Fecha |
|---|---|---|---|
| (ninguno todavía) | | | |

Datos: la base de posiciones de [GrappleMap](https://github.com/Eelis/GrappleMap) es de dominio público.

## Código de terceros
| Código | Origen (URL) | Licencia | Fecha |
|---|---|---|---|
| `src/core/cr_atan2.odin`: port de `src/binary64/atan2/atan2.c` y `tint.h` (commit `333d11d04d73ef165cf217e773b3b3d6372aa66f`); `tests/fixtures/cr_atan2.txt` incluye entradas de su `atan2.wc` | [CORE-MATH](https://gitlab.inria.fr/core-math/core-math) | MIT (aviso completo en la cabecera del fichero). Cambio propio: tabla `EXCEPTIONS` con una entrada que ese commit no sabe redondear (hueco de CORE-MATH, ADR 0003, enmienda #161) | 2026-11-23 |
