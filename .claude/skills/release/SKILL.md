---
name: release
description: Cierra una fase: comprueba el estado, pliega los fragmentos en CHANGELOG, crea el tag y explica el workflow de release.
disable-model-invocation: true
model: sonnet
---
1. Comprueba que el milestone/épica de la fase está cerrado y que `main` está verde (`gh run list`, `gh issue list`).
2. En un PR `chore: release vX.Y.Z`, pliega en `CHANGELOG.md` un `## [X.Y.Z] - fecha` con los fragmentos de `changelog.d/*.md` (excepto `README.md`, agrupados por `###`, en orden numérico de issue) más lo que ya hubiera en Unreleased, y borra los fragmentos en ese mismo PR. La línea «Unreleased changes live in `changelog.d/`…» se queda bajo el nuevo `## [Unreleased]` vacío, no pasa a la versión. `release.yml` sigue leyendo `CHANGELOG.md`, así que se pliega antes de etiquetar.
3. Explica qué hará `release.yml` al pushear el tag `vX.Y.Z` (build en matriz, binarios, notas del CHANGELOG).
4. Pide confirmación explícita antes de `git tag` y `git push --tags`.
