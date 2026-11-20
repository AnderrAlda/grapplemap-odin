---
name: start-task
description: Lee un issue y su plan, crea la rama con el prefijo correcto (o worktree) y empieza a implementar.
argument-hint: "<nº de issue>"
disable-model-invocation: true
model: sonnet
---
Empieza el issue #$ARGUMENTS

1. `gh issue view $ARGUMENTS` y lee `docs/plans/$ARGUMENTS-*.md`. Si no hay plan (y el cambio no es de una frase), para y sugiere `/plan`.
2. Crea la rama con prefijo según el label `type:` (`git switch -c feat/<slug>`) o usa `./build.sh worktree <rama>`.
3. Implementa siguiendo el plan: TDD en `core`, commits pequeños Conventional, cada uno compila. Si el plan resulta erróneo, para y propón actualizarlo; no improvises.
4. Termina con `./build.sh ci` y muestra la evidencia.
