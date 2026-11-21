---
name: orchestrate
description: Desde la sesión MAIN (raíz del repo), coordina los worktrees con Herdr: lanza workers por issue, los vigila y lleva cada PR hasta ready. Solo pregunta en las escalaciones listadas.
argument-hint: "[nº de issue ...]"
disable-model-invocation: true
model: opus
---
Orquesta el trabajo de: $ARGUMENTS (si está vacío, los issues abiertos de la fase en curso con plan aprobado).

Solo desde la sesión MAIN (raíz del repo, rama `main`, sin editar código). El merge es siempre de Ander.

## 0. Entorno
- `herdr pane current --current` debe devolver el pane de esta sesión. (`HERDR_ENV` puede venir vacío en la herramienta Bash; el criterio es que el CLI de `herdr` responda.) Si no responde, para y avísame.
- Un worktree por rama/agente; nunca dos agentes en la misma rama. Como mucho 3 workers a la vez.

## 1. Inventario
`gh issue list`, `gh pr list`, `git worktree list`, `herdr agent list`. Clasifica cada issue:
- **Sin plan** (y el cambio no cabe en una frase): usa `/plan <issue>` y **espera mi OK**. No lances worker sin plan aprobado.
- **Plan aprobado, sin worker**: lánzalo (paso 2).
- **Con worker**: vigílalo (paso 3).
- **Con PR abierto**: sigue CI y revisión (paso 4).
Si dos issues tocan los mismos ficheros, no los lances a la vez: encadénalos.

## 2. Lanzar un worker
1. `git fetch origin` y luego `herdr worktree create --branch <type>/<slug> --base origin/main --path ../grapplemap-odin-wt/<type>-<slug> --label <slug>`
   (misma convención que `./build.sh worktree`; el `type` sale del label `type:` del issue). Guarda el workspace y el pane de `.result`; confirma en la primera ejecución real que vienen ahí.
2. `herdr agent start <slug> --kind claude --pane <pane> -- --permission-mode auto`
3. Un prompt por mensaje, porque un `/comando` solo se interpreta al inicio del mensaje (sin `--wait`; vigila con el paso 3):
   1. `herdr agent prompt <slug> "Ejecuta ./build.sh setup (activa los hooks git anti-main; herdr worktree create no lo hace)."`
   2. cuando esté `idle`: `herdr agent prompt <slug> "/start-task <N>"` (la rama ya existe y es la del worktree: no crees otra).
   3. cuando haya terminado: `herdr agent prompt <slug> "/pr"`.

## 3. Vigilar
`herdr agent wait <slug> --timeout 120000` y `herdr agent read <slug>`:
- `done` / `idle`: comprueba el resultado (PR draft abierto, evidencia de `./build.sh ci`, labels y milestone) y manda el siguiente paso.
- `blocked`: lee el diálogo. **Nunca respondas tú a un diálogo de permisos de otro agente**; escala con el contexto.
- `unknown`: no prueba nada; mira `herdr agent read` antes de decidir.

## 4. Cerrar el PR
Con CI verde, `code-reviewer` sin bloqueantes y checklist completo, todo sobre el mismo commit (`gh pr view N --json headRefOid,statusCheckRollup`):
`gh pr ready N` sin preguntar (memoria `auto-ready-prs`) y dímelo. Si algo falla, el PR sigue en draft y se lo mandas al worker.
**Nunca `gh pr merge`.** Tras mi merge: `herdr worktree remove --workspace <id guardado>` (nunca `--force`; no está en `allow`, así que te lo pedirá) y libera el agente.

## 5. Escalar (lista cerrada)
Pregúntame solo si ocurre alguno de estos casos; lo demás se resuelve y se resume al final en pocas líneas:
- aprobar un plan, el merge, o un plan erróneo/alcance ambiguo;
- dependencia nueva, o ADR que cambie la arquitectura;
- tocar `reference/GrappleMap` o regenerar golden images; editar workflows de CI;
- worker `blocked`, o CI rojo tras 2 intentos del worker, o tope del Stop hook (8 bloqueos);
- conflicto entre workers, o cualquier acción irreversible o externa no cubierta por `allow`.

## Reglas
- Todo issue y PR con labels (`type:`, `area:`, `phase-N`) y milestone de su fase desde que se crean: `gh issue create`/`gh pr create` no se ejecutan sin ambos.
- No uses `herdr pane run`, `pane send-text/send-keys` ni `agent send-keys` para mandar comandos o aprobar diálogos de otro agente; no están en `allow` a propósito.
- Sin mención a Claude/Anthropic ni `Co-Authored-By` en commits, PRs o issues.
- El estado del trabajo vive en issues/PRs, no en la memoria de la sesión.
