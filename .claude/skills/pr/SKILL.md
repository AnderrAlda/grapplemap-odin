---
name: pr
description: Ejecuta ./build.sh ci, lanza el code-reviewer, rellena la plantilla (con label, milestone y checklist real), abre el PR como draft, espera la CI y lo pasa a ready. La pueden invocar los workers de /orchestrate.
model: sonnet
---
Un PR nunca se abre ni se marca ready sin **label + milestone** y con el **checklist reflejando lo realmente hecho**.

## 1. Verificar
1. Comprueba que no estás en `main`. Ejecuta `./build.sh ci`; si falla, para. Guarda la salida como evidencia.
2. Áreas tocadas: `git diff --stat origin/main...HEAD`.

## 2. Revisión
3. **Todo PR se revisa, sin excepción por tamaño** (ni «n/a» en la casilla). Lanza `code-reviewer` con `model: opus` si toca `src/core`, `src/render`, shaders o ADRs/arquitectura; `model: sonnet` en el resto. Guarda qué modelo se usó.
4. Corrige los bloqueantes y vuelve a lanzar la revisión hasta que no queden; los bloqueantes de cualquier revisión se corrigen siempre.
   **Máximo una ronda de no bloqueantes aplicados por PR; el resto va a issues.** Una ronda = los no bloqueantes que decidas aplicar de una revisión, en un solo commit, que se vuelve a revisar. Si una re-revisión tras corregir bloqueantes devuelve solo no bloqueantes, aplicarlos cuenta como esa única ronda. Los no bloqueantes de las re-revisiones posteriores, y los que no apliques, van como comentario en el issue de la tarea (el que el PR cierra o referencia) o en un issue nuevo (con label y milestone); enlázalos en el cuerpo del PR.
   Los hallazgos no bloqueantes del revisor que van a issue se crean con label `tech-debt` y milestone `Backlog`, salvo que sean `priority:high` (esos van al milestone de la fase en curso).

## 3. Metadatos (obligatorios)
5. **Labels** (al menos tres), derivados del tipo del título Conventional y de las rutas tocadas:
   - `type:`: `feat`→`type:feat`, `fix`→`type:fix`, `refactor` y `perf`→`type:refactor`, `test`→`type:test`, `docs`→`type:docs`, `ci`, `build` y `chore`→`type:ci`.
   - `area:`: `src/core`→`area:core`, `src/render` y shaders→`area:render`, `src/ui`→`area:ui`, `src/editor`→`area:editor`, el resto (CI, scripts, `.claude`, docs generales)→`area:infra`. Si toca varias, pon todas.
   - `phase-N`: la fase del issue/épica enlazado.
6. **Milestone**: el de la fase del issue/épica enlazado (`gh issue view N --json milestone`). Si no se puede determinar, pregunta; nunca lo dejes vacío.
7. Aplícalos al crear: `gh pr create --draft --label ... --milestone "..."`. Antes de abrir el PR y antes de marcarlo ready, comprueba con `gh pr view --json labels,milestone` que no están vacíos.

## 4. Cuerpo y checklist
8. Rellena `.github/pull_request_template.md`: qué y por qué, plan enlazado, `Closes #N` (o `Refs #N` si no debe cerrarlo), cómo probarlo, capturas si hay cambios visuales. Título Conventional Commit.
9. **Checklist según evidencia, nunca por defecto**. Marca `[x]` solo lo que hiciste y verificaste en esta sesión; lo demás queda `[ ]`:
   - Tests añadidos → hay tests nuevos o actualizados en el diff.
   - `./build.sh ci` pasa → solo si lo ejecutaste y salió bien.
   - Docs/CLAUDE.md/fragmento `changelog.d/<issue>-<slug>.md` (nunca editar `CHANGELOG.md`)/ADR → solo si realmente se actualizaron o no aplica (escribe «n/a»).
   - Sin leaks → solo si los tests/smoke en debug lo confirman.
   - CI verde → solo cuando `gh pr checks` lo muestre en el último commit.
   - `code-reviewer` sin bloqueantes → solo tras ejecutarlo; indica modelo y resultado en el cuerpo.
10. **Mantén el cuerpo al día**: tras la revisión o cuando la CI termine, actualiza las casillas. Parte del cuerpo actual (`gh pr view <N> --json body -q .body > <fichero temporal>`), edita las casillas en ese fichero y aplícalo con `gh pr edit <N> --body-file <fichero temporal>`. Antes de `gh pr ready` repasa el checklist completo contra la evidencia.
    **Verifica siempre cada edición leyendo el cuerpo de vuelta** con un criterio concreto, p. ej. `gh pr view <N> --json body -q .body | grep -F '[x] CI verde'`: no te fíes de que el comando no haya dado error. Si `gh pr edit` falla (versiones antiguas de `gh`, p. ej. 2.45, dan un error de Projects classic y no aplican el cambio: ver #76), usa la API REST: `gh api -X PATCH repos/{owner}/{repo}/pulls/<N> -F body=@<fichero temporal>` (`{owner}` y `{repo}` los resuelve `gh`; escríbelos tal cual) y vuelve a verificar. Solo ese comando exacto (PATCH sobre `pulls/<N>`) está en `allow`; no uses `gh api` para nada más. Si aun así no te lo permiten, para y dilo en tu último mensaje en lugar de marcar ready.

## 5. Reglas
- Sin ninguna mención a Claude/Anthropic ni «Generated with» en título o cuerpo; el PR figura como hecho por el usuario.
- Nunca marques ready sin: CI verde en el último commit, `code-reviewer` sin bloqueantes sobre ese mismo commit y checklist completo. Si el commit cambia después, repite la revisión.
- Abre con `gh pr create --draft` sin pedir confirmación. Cuando se cumplan esas tres condiciones, pasa a ready con `gh pr ready` sin preguntar y avísame. NO hagas merge.

## 6. Esperar la CI y pasar a ready
11. Tras abrir el draft, espera la CI sobre el último commit con `gh pr checks <N> --watch`, llamándolo con `timeout: 600000` en la herramienta Bash. Si la llamada expira por timeout, repite `--watch` (es idempotente): un timeout NO es un fallo de CI. Justo tras crear el PR puede salir «no checks reported»: espera unos segundos y reintenta. Solo cuenta como fallo un check en `fail`; entonces corrige (como mucho 2 intentos; luego para y cuéntalo) y repite la revisión si el commit cambió.
12. Con CI verde, marca la casilla de CI en el cuerpo (paso 10, con la verificación de lectura posterior) y **solo después de ver la casilla marcada** y si se cumplen las tres condiciones de la sección 5, `gh pr ready <N>`. Termina con un resumen corto: PR, CI, revisión, hallazgos enviados a issues. El merge nunca es tuyo.
