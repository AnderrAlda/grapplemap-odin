---
name: release
description: Cierra una fase: comprueba el estado, actualiza CHANGELOG, crea el tag y explica el workflow de release.
disable-model-invocation: true
model: sonnet
---
1. Comprueba que el milestone/épica de la fase está cerrado y que `main` está verde (`gh run list`, `gh issue list`).
2. Mueve Unreleased a `## [X.Y.Z] - fecha` en `CHANGELOG.md` (PR `chore: release vX.Y.Z`).
3. Explica qué hará `release.yml` al pushear el tag `vX.Y.Z` (build en matriz, binarios, notas del CHANGELOG).
4. Pide confirmación explícita antes de `git tag` y `git push --tags`.
