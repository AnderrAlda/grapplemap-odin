# Assets de terceros
No se añade ningún asset (texturas, fuentes, HDRIs) sin registrar aquí su origen y licencia compatible.

| Asset | Origen (URL) | Licencia | Fecha |
|---|---|---|---|
| (ninguno todavía) | | | |

Datos: la base de posiciones de [GrappleMap](https://github.com/Eelis/GrappleMap) es de dominio público.

## Código de terceros
| Código | Origen (URL) | Licencia | Fecha |
|---|---|---|---|
| `src/core/cr_atan2.odin`: port de `src/binary64/atan2/atan2.c` y `tint.h`; `src/core/cr_sin_cos.odin`: port de `src/binary64/sin/sin.c` y `src/binary64/cos/cos.c` (los dos, commit `333d11d04d73ef165cf217e773b3b3d6372aa66f`); `tests/fixtures/cr_atan2.txt` y `tests/fixtures/cr_sin_cos.txt` incluyen entradas de sus `atan2.wc`, `sin.wc` y `cos.wc` | [CORE-MATH](https://gitlab.inria.fr/core-math/core-math) | MIT (aviso completo en la cabecera de cada fichero). Cambio propio en `cr_atan2`: tabla `EXCEPTIONS` con una entrada que ese commit no sabe redondear (hueco de CORE-MATH, ADR 0003, enmienda #161); `cr_sin_cos` sin cambios de algoritmo | 2026-11-23 |
