---
name: pr
description: Ejecuta ./build.sh ci, lanza el code-reviewer, rellena la plantilla (con label, milestone y checklist real) y abre el PR como draft.
disable-model-invocation: true
model: sonnet
---
Un PR nunca se abre ni se marca ready sin **label + milestone** y con el **checklist reflejando lo realmente hecho**.

## 1. Verificar
1. Comprueba que no estás en `main`. Ejecuta `./build.sh ci`; si falla, para. Guarda la salida como evidencia.
2. Áreas tocadas: `git diff --stat origin/main...HEAD`.

## 2. Revisión
3. **Todo PR se revisa, sin excepción por tamaño** (ni «n/a» en la casilla). Lanza `code-reviewer` con `model: opus` si toca `src/core`, `src/render`, shaders o ADRs/arquitectura; `model: sonnet` en el resto. Guarda qué modelo se usó.
4. Corrige los bloqueantes y vuelve a lanzar la revisión hasta que no queden; los bloqueantes de cualquier revisión se corrigen siempre.
   **Máximo una ronda de no bloqueantes aplicados por PR; el resto va a issues.** Una ronda = los no bloqueantes que decidas aplicar de una revisión, en un solo commit, que se vuelve a revisar. Los no bloqueantes de esa re-revisión y de las siguientes, y los que no apliques, van como comentario en el issue que corresponda o en un issue nuevo (con label y milestone); enlázalos en el cuerpo del PR.
   Los hallazgos no bloqueantes del revisor que van a issue se crean con label `tech-debt` y milestone `Backlog`, salvo que sean `priority:high` (esos van al milestone de la fase en curso).

## 3. Metadatos (obligatorios)
5. **Labels** (al menos tres), derivados del tipo del título Conventional y de las rutas tocadas:
   - `type:`: `feat`→`type:feat`, `fix`→`type:fix`, `refactor` y `perf`→`type:refactor`, `test`→`type:test`, `docs`→`type:docs`, `ci`, `build` y `chore`→`type:ci`.
   - `area:`: `src/core`→`area:core`, `src/render` y shaders→`area:render`, `src/ui`→`area:ui`, `src/editor`→`area:editor`, el resto (CI, scripts, `.claude`, docs generales)→`area:infra`. Si toca varias, pon todas.
   - `phase-N`: la fase del issue/épica enlazado.
6. **Milestone**: el de la fase del issue/épica enlazado (`gh issue view N --json milestone`). Si no se puede determinar, pregunta; nunca lo dejes vacío.
7. Aplícalos al crear: `gh pr create --draft --label ... --milestone "..."`. Antes de pedir confirmación, comprueba con `gh pr view --json labels,milestone` que no están vacíos.

## 4. Cuerpo y checklist
8. Rellena `.github/pull_request_template.md`: qué y por qué, plan enlazado, `Closes #N` (o `Refs #N` si no debe cerrarlo), cómo probarlo, capturas si hay cambios visuales. Título Conventional Commit.
9. **Checklist según evidencia, nunca por defecto**. Marca `[x]` solo lo que hiciste y verificaste en esta sesión; lo demás queda `[ ]`:
   - Tests añadidos → hay tests nuevos o actualizados en el diff.
   - `./build.sh ci` pasa → solo si lo ejecutaste y salió bien.
   - Docs/CLAUDE.md/CHANGELOG/ADR → solo si realmente se actualizaron o no aplica (escribe «n/a»).
   - Sin leaks → solo si los tests/smoke en debug lo confirman.
   - CI verde → solo cuando `gh pr checks` lo muestre en el último commit.
   - `code-reviewer` sin bloqueantes → solo tras ejecutarlo; indica modelo y resultado en el cuerpo.
10. **Mantén el cuerpo al día**: tras la revisión o cuando la CI termine, actualiza las casillas con `gh pr edit --body`. Antes de `gh pr ready` repasa el checklist completo contra la evidencia.

## 5. Reglas
- Sin ninguna mención a Claude/Anthropic ni «Generated with» en título o cuerpo; el PR figura como hecho por el usuario.
- Nunca marques ready sin: CI verde en el último commit, `code-reviewer` sin bloqueantes sobre ese mismo commit y checklist completo. Si el commit cambia después, repite la revisión.
- Pide confirmación y abre con `gh pr create --draft`. Marca ready solo con CI verde y revisión sin bloqueantes. NO hagas merge.
