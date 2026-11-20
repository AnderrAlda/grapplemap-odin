# reference
- `GrappleMap/` es el original (submódulo fijado en `032c8f9`), SOLO LECTURA: nunca editar, compilar dentro ni dejar ficheros en él
  (el oráculo se construye fuera del árbol; parches solo en `tools/oracle/patches/` + ADR 0002). `git status` debe mostrarlo limpio.
- Los hooks no cubren escrituras por Bash; la misma regla aplica.
- Inicializar: `git submodule update --init`. Comprobar el pin: `git -C reference/GrappleMap rev-parse HEAD`.
- Subir el pin: solo en un PR propio que actualice el gitlink, regenere la muestra del oráculo (`tests/fixtures/oracle/`),
  `FULL.sha256` y el inventario, y revise las citas `file:line` de `docs/original.md`.
