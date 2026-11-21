---
name: start-task
description: Lee un issue y su plan (copiándolo y commiteándolo si te lo pasan), implementa en el worktree y termina invocando /pr para dejar el PR listo.
argument-hint: "<nº de issue> [ruta absoluta del plan aprobado]"
disable-model-invocation: true
---
Empieza el issue indicado en `$ARGUMENTS`: el primer valor es el nº de issue (`N`) y el segundo, opcional, la ruta absoluta del plan aprobado (lo pasa `/orchestrate`).

0. Si estás en un worktree recién creado, ejecuta `./build.sh setup` (activa los hooks git anti-`main`; no lo hace `./build.sh worktree`).
1. `gh issue view N`. Si te pasaron la ruta de un plan y `docs/plans/N-*.md` no existe en este worktree, cópialo a `docs/plans/` y commitéalo (`docs(plan): add plan for #N`): el plan aprobado vive sin commit en `main`. Lee `docs/plans/N-*.md`. Si no hay plan (y el cambio no es de una frase), para y sugiere `/plan`.
2. Si ya estás en un worktree/rama del issue (p. ej. creado por `/orchestrate`), no crees otra. Si no, crea la rama con prefijo según el label `type:` (`git switch -c feat/<slug>`) o usa `./build.sh worktree <rama>`.
3. Implementa siguiendo el plan: TDD en `core`, commits pequeños Conventional, cada uno compila. Si el plan resulta erróneo, para y propón actualizarlo; no improvises. No lances más agentes que los subagentes que pidan estas skills (p. ej. `code-reviewer`).
4. Termina con `./build.sh ci` y muestra la evidencia.
5. Si `./build.sh ci` está verde, invoca la skill `pr`: abre el PR en draft, lo revisa, espera la CI y lo pasa a ready (regla de autonomía de `CLAUDE.md`). Si surge cualquiera de las escalaciones de `docs/ai-workflow.md` (Orquestación, punto 4), para y dilo en tu último mensaje: MAIN lo leerá. No uses preguntas interactivas: nadie las contesta. (`./build.sh ci` lo ejecutan este paso y el paso 1 de `/pr`; si el HEAD no cambió entre medias, el segundo puede saltarse.)
