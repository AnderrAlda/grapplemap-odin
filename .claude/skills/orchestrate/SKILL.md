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
- Cada worker se abre en **su propio space de Herdr** (como un worktree en la app): se lanza con una etiqueta `herdr.space` nueva, que genera `./build.sh space-id <rama>` (`sp` + 32 hex, estable por rama: relanzar un worker de la misma rama cae en el mismo space). La app abre el space con el nombre de la carpeta del worktree. Sin etiqueta el worker funciona igual pero oculto: avísame.
- Un worktree por rama/agente; nunca dos agentes en la misma rama. Como mucho 3 workers a la vez. Solo hablas con terminales que lanzaste tú (por su nombre `w-*`); nunca con otros (tus zsh, otros proyectos o máquinas).
- Lo recomendado es que MAIN corra en el servidor (sigue aunque el portátil duerma), pero la skill lanza los workers en la máquina donde corre MAIN (sin `--on`).

## 1. Inventario
`gh issue list`, `gh pr list`, `git worktree list`, `hc ls` (tus workers son los de nombre `w-*`). Clasifica cada issue:
- **Sin plan** (y el cambio no cabe en una frase): usa `/plan <issue>` y **espera mi OK**. No lances worker sin plan aprobado.
- **Plan aprobado, sin worker**: lánzalo (paso 2).
- **Con worker**: vigílalo (paso 3).
- **Con PR abierto**: sigue CI y revisión (paso 4).
Si dos issues tocan los mismos ficheros, no los lances a la vez: encadénalos.

## 2. Lanzar un worker
Cada worker hace **todo el recorrido por sí mismo** en su worktree: `/start-task` (setup, plan, implementar, `./build.sh ci`) y luego la skill `pr` (revisión, PR draft, CI, ready). Tú solo lanzas, vigilas, verificas y limpias.
1. `git fetch origin` y `./build.sh worktree <type>/<slug>` desde la raíz (crea `../grapplemap-odin-wt/<type>-<slug>` y el submódulo; el `type` sale del label `type:` del issue). Usa la ruta **absoluta** del worktree. El nombre del terminal es siempre `w-<slug>`: 1-32 caracteres de `a-z0-9-_`, único entre los vivos (deriva del nombre de la rama: minúsculas, `/` → `-`, recortado a 30 caracteres para dejar sitio al prefijo `w-`). El prefijo `w-` es lo que permiten las reglas `allow` de `hc send/kill/rm`.
2. Lanza el worker con la slash command como **prompt inicial** (así `claude` la interpreta como escrita por el usuario; con `hc send` llegaría envuelta en `<hc from=...>` como texto y no se ejecutaría):
   ```
   hc run --bg --outlive-parent --name w-<slug> --cwd <ruta-absoluta-del-worktree> --label herdr.space=<id de ./build.sh space-id <rama>> claude --permission-mode auto "/start-task <N> <ruta-absoluta>/docs/plans/<N>-<slug>.md"
   ```
   El segundo argumento (ruta del plan aprobado, sin commit en `main`) se omite si el cambio no necesita plan. `hc run` no devuelve `first_message` con flags extra: confirma que arrancó con `hc read --lines 40 w-<slug>`. Si aparece un diálogo (p. ej. de confianza), escala: nunca `hc keys`.
3. No hace falta mandarle nada más. Para corregir, contestar a una escalación suya o reanudarlo, `hc send w-<slug> "<texto en lenguaje natural>"` (nunca otro `/comando`; llegaría como texto) y solo si su estado es `idle` o `done`. `/start-task` no se puede reinvocar así, pero `/pr` sí: «invoca la skill pr» lo reanuda desde la revisión.

## 3. Vigilar
Nunca hagas sleep ni polling: `hc wait w-<slug>` (hasta que deje de trabajar; `reason: timeout` es un chequeo, vuelve a esperar) y lee con `hc read --lines 60 w-<slug>`. Su estado está en `hc get w-<slug> --json | jq -r '.status.state'` (puede estar ausente: no envíes nada en ese caso); un worker parado suele quedar en `done`.
- `idle` al principio puede ser solo el arranque (el prompt inicial no cuenta como tarea de lanzamiento para `hc wait`): si no hay PR, ni commits en el worktree, ni actividad en `hc read`, vuelve a esperar antes de tratarlo como escalación.
- `done` / `idle`: comprueba el resultado con `gh pr list --head <rama>` y `gh pr view N --json isDraft,headRefOid,statusCheckRollup,labels,milestone`: PR abierto, labels y milestone, evidencia de `./build.sh ci`. Si el worker no abrió PR, lee su pantalla y su último mensaje: normalmente es una escalación suya (plan erróneo, dependencia nueva, CI rojo tras 2 intentos): decide con la lista del paso 5.
- `blocked` / `error`: lee la pantalla. **Nunca respondas tú a un diálogo de permisos de otro agente** (no uses `hc keys`); escala con el contexto.
- Hooks Stop: si un worker se queda atascado por el Stop hook (8 bloqueos seguidos), escala.

## 4. Cerrar el PR
Normalmente el worker ya dejó el PR en ready (lo hace la skill `pr`). Compruébalo contra la evidencia, sobre el mismo commit (`gh pr view N --json headRefOid,statusCheckRollup`): CI verde, `code-reviewer` sin bloqueantes y checklist completo. Si se cumple y sigue en draft, `gh pr ready N` sin preguntar (regla de autonomía de `CLAUDE.md`). Si algo falla, el PR sigue en draft y se lo mandas al worker. Dímelo cuando haya PRs listos para tu merge.
**Nunca `gh pr merge`.** Tras mi merge, limpia (paso 4b).

## 4b. Limpiar lo terminado
En cada inventario, y siempre que te diga que he mergeado, busca worktrees y ramas locales cuyo PR esté `MERGED` y límpialos sin escalar (algunos comandos pedirán confirmación de permisos, ver abajo), **solo si se cumplen las cuatro comprobaciones**:
1. `gh pr list --head <rama> --state merged --json number,headRefOid` devuelve el PR (así `N` sale de la rama, sin confundirlo con otro PR de una rama reutilizada).
2. El HEAD **del worktree** es el del PR: `git -C <worktree> rev-parse HEAD` == `headRefOid`, y `git -C <worktree> symbolic-ref --short HEAD` == `<rama>` (HEAD desacoplado, rebase en curso u otra rama implican commits que ninguna ref protege: escala).
3. `git -C <worktree> status --short --ignored` está vacío salvo ficheros ignorados que reconozcas como regenerables (salidas de build); `--force` los borra.
4. Para las ramas de respaldo (`pre-rebase-*`): lista cada una con su SHA (`git branch -vv --list 'pre-rebase-*'`) y bórrala solo si es ancestro del `headRefOid` (`git merge-base --is-ancestor <rama> <headRefOid>`); si no, escala.
Entonces, desde la raíz y con `main` al día (`git pull --ff-only`):
- Worker: `hc kill w-<slug>`, comprueba con `hc get w-<slug>` que terminó y luego `hc rm w-<slug>` (están en `allow` solo para nombres `w-*`). Hazlo antes de quitar el worktree.
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
- `allow`: `hc ls|get|read|wait` (solo lectura), `hc run --bg`, y `hc send|kill|rm` **solo para terminales llamados `w-*`**, más un `deny` de `hc send --force`. `hc exec`, `hc keys`, `hc interrupt` y `hc run` sin `--bg` no están en `allow`. Riesgo residual asumido: `hc run --bg` puede arrancar cualquier programa y ni los `deny` ni el guard analizan ese texto interior; se mitiga por convención (solo lanzas `claude` para tus workers).
- Sin mención a Claude/Anthropic ni `Co-Authored-By` en commits, PRs o issues.
- El estado del trabajo vive en issues/PRs, no en la memoria de la sesión.
