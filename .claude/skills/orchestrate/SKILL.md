---
name: orchestrate
description: Desde la sesión MAIN (raíz del repo), coordina los workers por worktree con hc (herdr-core): los lanza por issue, los vigila y lleva cada PR hasta ready. Solo pregunta en las escalaciones listadas.
argument-hint: "[nº de issue ...]"
disable-model-invocation: true
model: opus
---
Orquesta el trabajo de: $ARGUMENTS (si está vacío, los issues abiertos de la fase en curso con plan aprobado).

Solo desde la sesión MAIN (raíz del repo, rama `main`, sin editar código). El merge es siempre de Ander.
La app Herdr corre sus terminales en **herdr-core (`hc`)**: usa `hc` para lanzar, leer, esperar y hablar con los workers. El CLI `herdr` antiguo NO ve esos terminales; no lo uses. `herdr-app` solo coloca ventanas y no existe en el servidor. Referencia: `hc --skill`.

## 0. Entorno
- `echo "$HC_TERMINAL_ID"` no está vacío y `hc get "$HC_TERMINAL_ID" --json` responde. Si no, para y avísame.
- Guarda tu space: `hc get "$HC_TERMINAL_ID" --json` → `labels."herdr.space"` (el id del space es de cada máquina). Los workers se lanzan con esa misma etiqueta para que aparezcan como pestañas de tu space en la app. Sin etiqueta funcionan igual pero ocultos: avísame.
- Un worktree por rama/agente; nunca dos agentes en la misma rama. Como mucho 3 workers a la vez. Solo hablas con terminales que lanzaste tú (por su nombre); nunca con otros (tus zsh, otros proyectos o máquinas). `hc ls --label herdr.space=<tu-space>` limita el listado a tu space.
- Lo recomendado es que MAIN corra en el servidor (sigue aunque el portátil duerma), pero la skill lanza los workers en la máquina donde corre MAIN (sin `--on`).

## 1. Inventario
`gh issue list`, `gh pr list`, `git worktree list`, `hc ls --label herdr.space=<tu-space>`. Clasifica cada issue:
- **Sin plan** (y el cambio no cabe en una frase): usa `/plan <issue>` y **espera mi OK**. No lances worker sin plan aprobado.
- **Plan aprobado, sin worker**: lánzalo (paso 2).
- **Con worker**: vigílalo (paso 3).
- **Con PR abierto**: sigue CI y revisión (paso 4).
Si dos issues tocan los mismos ficheros, no los lances a la vez: encadénalos.

## 2. Lanzar un worker
1. `git fetch origin` y `./build.sh worktree <type>/<slug>` desde la raíz (crea `../grapplemap-odin-wt/<type>-<slug>` y el submódulo; el `type` sale del label `type:` del issue). Usa la ruta **absoluta** del worktree. El nombre del terminal (`<slug>`) son 1-32 caracteres de `a-z0-9-_` y único entre los vivos: deriva del nombre de la rama (minúsculas, `/` → `-`, recortado).
2. El plan aprobado vive sin commit en `docs/plans/` de `main`; el worktree no lo tiene. Díselo al worker en su primer mensaje (ruta absoluta) para que lo copie y lo commitee en su rama antes de implementar.
3. Lanza el worker con su primer mensaje (un `/comando` solo se interpreta al inicio de un mensaje, así que este primero va en lenguaje natural):
   ```
   hc run --bg --outlive-parent --name <slug> --cwd <ruta-absoluta-del-worktree> --label herdr.space=<tu-space> claude --permission-mode auto "Ejecuta ./build.sh setup (activa los hooks git anti-main). Copia el plan aprobado <ruta-absoluta>/docs/plans/<N>-<slug>.md a docs/plans/ de este worktree y commitéalo (docs(plan): ... (#N)). Cuando termines o te atasques, avisa con: hc send ${HC_TERMINAL_ID} 'listo o atascado'."
   ```
   `${HC_TERMINAL_ID}` se expande en tu shell (es tu id, el de MAIN), no lo escribas como marcador. `--outlive-parent` evita que reiniciar MAIN mate a un worker con trabajo sin commitear.
   Comprueba `first_message.sent` en el resultado; si es `false` o no aparece, la tarea puede NO haberse enviado: `hc read <slug>`, confirma que el worker empezó, y reenvía solo tras leer.
4. Cuando el worker esté parado (`hc wait <slug>`): `hc send --if idle <slug> "/start-task <N>"` (`--if idle` solo escribe si no está trabajando ni bloqueado; nunca uses `--force`) (la rama ya existe y es la del worktree: no crees otra). Al terminar: `hc send --if idle <slug> "/pr"`.
   Verifica en la primera ejecución real que un `/comando` enviado con `hc send` se interpreta como slash command; si no, escala.

## 3. Vigilar
Nunca hagas sleep ni polling: `hc wait <slug>` (hasta que deje de trabajar), `hc wait --children any|all` o `hc send --wait <slug> ...`, y lee con `hc read --lines 60 <slug>`. Los avisos llegan como `<hc from=...>`.
- `done` / `idle`: comprueba el resultado (PR draft abierto, evidencia de `./build.sh ci`, labels y milestone) y manda el siguiente paso.
- `blocked` / `error`: lee la pantalla. **Nunca respondas tú a un diálogo de permisos de otro agente** (no uses `hc keys`); escala con el contexto.
- `reason: timeout` de `hc wait` es un chequeo, no un fallo: vuelve a esperar.

## 4. Cerrar el PR
Con CI verde, `code-reviewer` sin bloqueantes y checklist completo, todo sobre el mismo commit (`gh pr view N --json headRefOid,statusCheckRollup`):
`gh pr ready N` sin preguntar (regla de autonomía de `CLAUDE.md`) y dímelo. Si algo falla, el PR sigue en draft y se lo mandas al worker.
**Nunca `gh pr merge`.** Tras mi merge, limpia (paso 4b).

## 4b. Limpiar lo terminado
En cada inventario, y siempre que te diga que he mergeado, busca worktrees y ramas locales cuyo PR esté `MERGED` y límpialos sin escalar (algunos comandos pedirán confirmación de permisos, ver abajo), **solo si se cumplen las cuatro comprobaciones**:
1. `gh pr list --head <rama> --state merged --json number,headRefOid` devuelve el PR (así `N` sale de la rama, sin confundirlo con otro PR de una rama reutilizada).
2. El HEAD **del worktree** es el del PR: `git -C <worktree> rev-parse HEAD` == `headRefOid`, y `git -C <worktree> symbolic-ref --short HEAD` == `<rama>` (HEAD desacoplado, rebase en curso u otra rama implican commits que ninguna ref protege: escala).
3. `git -C <worktree> status --short --ignored` está vacío salvo ficheros ignorados que reconozcas como regenerables (salidas de build); `--force` los borra.
4. Para las ramas de respaldo (`pre-rebase-*`): lista cada una con su SHA (`git branch -vv --list 'pre-rebase-*'`) y bórrala solo si es ancestro del `headRefOid` (`git merge-base --is-ancestor <rama> <headRefOid>`); si no, escala.
Entonces, desde la raíz y con `main` al día (`git pull --ff-only`):
- Worker: `hc kill <slug>`, comprueba con `hc get <slug>` que terminó y luego `hc rm <slug>` (no están en `allow`: pedirán confirmación). Hazlo antes de quitar el worktree.
- Worktree: usa `./build.sh worktree-remove <rama>` cuando exista (#54). Mientras no exista, `git worktree remove <ruta>`; si git se niega solo por tener submódulos, `--force` es aceptable **únicamente** tras las comprobaciones 1-3 y **solo en `git worktree remove`, nunca en un push** (no está en `allow`: pedirá confirmación). Luego `git worktree prune`.
- Rama local: `git branch -D <rama>` (un squash no hace la rama «mergeada» para git, por eso `-D` y no `-d`; las comprobaciones son la garantía, y `git branch -D main*` está en `deny`).
- Remoto: GitHub borra la rama al mergear (`delete_branch_on_merge`); solo `git fetch --prune`. Nunca `git push --delete`.
Si alguna comprobación falla, no borres nada y escala con el motivo.

## 5. Escalar (lista cerrada)
Pregúntame solo si ocurre alguno de estos casos; lo demás se resuelve y se resume al final en pocas líneas:
- aprobar un plan, el merge, o un plan erróneo/alcance ambiguo;
- dependencia nueva, o ADR que cambie la arquitectura;
- tocar `reference/GrappleMap` o regenerar golden images; editar workflows de CI;
- worker `blocked`/`error`, o CI rojo tras 2 intentos del worker, o tope del Stop hook (8 bloqueos);
- conflicto entre workers, o cualquier acción irreversible o externa no cubierta por `allow`.

## Reglas
- Todo issue y PR con labels (`type:`, `area:`, `phase-N`) y milestone de su fase desde que se crean: `gh issue create`/`gh pr create` no se ejecutan sin ambos.
- Solo `hc ls|get|read|wait|send|run --bg` están en `allow`. `hc exec`, `hc keys`, `hc interrupt`, `hc kill/rm` y `hc run` sin `--bg` no lo están a propósito. Ojo: `hc send` puede teclear en cualquier terminal y `hc run --bg` puede arrancar cualquier programa, y ni los `deny` ni el guard analizan ese texto interior; el riesgo residual se acepta porque MAIN y los workers lo necesitan, y se mitiga solo por convención (solo tus workers, `--if idle`, nunca `--force`) y con un `deny` de `hc send --force`.
- Sin mención a Claude/Anthropic ni `Co-Authored-By` en commits, PRs o issues.
- El estado del trabajo vive en issues/PRs, no en la memoria de la sesión.
