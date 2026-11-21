# Flujo de trabajo con IA

Principio: lo crítico lo hacen cumplir permisos, hooks y CI; lo demás va en CLAUDE.md, skills y subagentes.

## Reparto de modelos
| Trabajo | Modelo | Cómo |
|---|---|---|
| Specs, planes, ADRs, bugs difíciles | opus | `model: opusplan` en `.claude/settings.json` (Opus en plan mode, Sonnet al ejecutar); skills `/spec`, `/plan`, `/adr` con `model: opus` |
| Implementar plan aprobado, tests, refactors acotados | sonnet | ejecución normal; `/start-task`, `/pr` |
| `code-reviewer` | sonnet; opus en core/render/arquitectura | frontmatter `model: sonnet`; `/pr` lo invoca con `model: opus` según las áreas tocadas |
| `test-writer`, `render-verifier` | sonnet | frontmatter |
| `explorer`, `odin-researcher`, `chore`, `Explore` (override) | haiku | frontmatter |

Cambiarlo: edita `model:` en el frontmatter del agente/skill o `model` en `.claude/settings.json`.
No uses `CLAUDE_CODE_SUBAGENT_MODEL`: pisaría el `model:` de cada subagente.
Para trabajo acotado pero delicado, sube `effort:` del subagente antes de subir de modelo.
Revisa el gasto con `/cost` al cerrar cada fase.

## Flujo spec → plan → ejecución
1. `/spec <fase>` → `docs/specs/` (PR solo docs). 2. `/plan <issue>` en plan mode → `docs/plans/<issue>-<slug>.md`, lo reviso.
3. `/clear` o sesión nueva (en worktree) y `/start-task <issue>`. 4. `/pr` lanza `code-reviewer` en contexto limpio.
5. Para lo crítico (parser, interpolación, shaders de cuerpo): una sesión escribe tests (`test-writer`) y otra el código.
Excepción: cambios describibles en una frase van sin spec ni plan, con PR pequeño. **Nunca sin `code-reviewer`**: todo PR se revisa (mínimo sonnet) sin excepción por tamaño; sin revisión sin bloqueantes sobre el último commit, el PR sigue en draft.

## Enforcement (qué lo hace cumplir)
- Regla de revisión: la skill `/pr` y `CLAUDE.md` exigen `code-reviewer` en todo PR; no se marca ready sin CI verde, revisión sin bloqueantes y checklist completo, todo sobre el mismo commit. Como mucho una ronda de no bloqueantes aplicados por PR; el resto va a issues.
  Los hallazgos no bloqueantes del revisor que van a issue se crean con label `tech-debt` y milestone `Backlog`, salvo que sean `priority:high` (esos van al milestone de la fase en curso).
- Permisos en `.claude/settings.json` (allow/ask/deny; deny gana siempre; `ask` solo conserva instalaciones, `gh release create` y workflows de CI). Las reglas de ruta para ficheros se escriben como `Edit(...)`: cubren todas las herramientas que escriben ficheros (Edit, Write, NotebookEdit; no las escrituras por Bash, ver #21); `Write(...)` no tiene efecto. Personal: `.claude/settings.local.json` (ignorado por git).
- Hooks (`.claude/hooks/`): formato+check tras editar `.odin`; bloqueo de `reference/GrappleMap/` y `tests/golden/`; bloqueo de commit/push en `main` y comandos destructivos; `Stop` ejecuta `check`+tests; `SessionStart` muestra rama/issue.
- El `Stop` hook respeta `stop_hook_active` para no hacer bucles. Claude Code fuerza la parada tras 8 bloqueos seguidos
  (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`): si ocurre, el resumen debe decirlo y la tarea NO se da por buena.

## Protección de `main` (sin branch protection de GitHub)
El repo es privado sin plan Pro, así que GitHub no puede proteger `main`. La protección depende **solo de los hooks locales** y exige haber ejecutado `./build.sh setup` en cada clon/worktree (activa `core.hooksPath=.githooks`):
- git `pre-commit`: bloquea commits en `main`. git `pre-push`: bloquea cualquier push cuyo destino sea `refs/heads/main` (también `git push origin feat:main`).
- Guard de Claude (`.claude/hooks/guard-bash.sh` + reglas `deny`): bloquea commit/push estando en `main`, pushes con destino `main` desde cualquier rama, `--force`, `--no-verify` y `gh pr merge`.
- Los merges se hacen **solo desde GitHub** (squash). Un `git push --no-verify` manual o un clon sin `setup` saltan los hooks git: no hay defensa del lado del servidor hasta activar GitHub Pro o hacer el repo público.

## Worktrees (varios agentes)
`./build.sh worktree <rama>` crea `../grapplemap-odin-wt/<rama>`. Un worktree por rama/agente; nunca dos agentes en la misma rama.

## Orquestación (MAIN + Herdr)
La app Herdr corre sus terminales en herdr-core (`hc`); el CLI `herdr` antiguo no los ve. `herdr-app` solo coloca ventanas (y solo existe en el Mac); `hc` funciona igual en el Mac y en el servidor.
La sesión `MAIN` (raíz del repo, en `main`, sin editar código; recomendado en el servidor de Hetzner, para que siga aunque el portátil duerma, pero lanza los workers en la máquina donde corre) coordina los workers con `/orchestrate`:
1. Inventario de issues, PRs, worktrees y agentes (`gh`, `git worktree list`, `hc ls`).
2. Por cada issue con **plan aprobado por ti**: `./build.sh worktree <rama>` → `hc run --bg --name <slug> --cwd <worktree> --label herdr.space=<space de MAIN> claude --permission-mode auto "…"`
   (así aparece como pestaña en la app) → mensajes separados con `hc send`: `/start-task <N>` y `/pr`. El primer mensaje (lenguaje natural) hace `./build.sh setup`
   y copia el plan aprobado a la rama del worker, porque `main` no lo tiene commiteado. Como mucho 3 workers a la vez.
3. Vigila con `hc wait` / `hc read` (nunca sleep ni polling). Cuando un PR cumple CI verde + `code-reviewer` sin bloqueantes + checklist completo
   (mismo commit), lo pasa a ready sin preguntar y te avisa. **El merge es siempre tuyo** (`gh pr merge` sigue en `deny`).
4. Solo te pregunta en: aprobar un plan, merge, plan erróneo o alcance ambiguo, dependencia nueva, tocar `reference/` o golden,
   editar workflows de CI, worker `blocked`, CI rojo tras 2 intentos, tope del Stop hook, conflicto entre workers o una acción
   irreversible no cubierta por `allow`.
Para que los workers no se detengan a pedir permiso, `git push`, `gh pr create/ready/edit/comment`, `gh issue create/edit/comment`
y los subcomandos `hc` que usa la skill (`ls`, `get`, `read`, `wait`, `send`, `run --bg`) están en `allow` en
`.claude/settings.json`. `hc exec`, `hc keys`, `hc interrupt`, `hc kill/rm` y `hc run` sin `--bg` NO están en `allow`. Pero `hc send` (teclea en
cualquier terminal) y `hc run --bg` (arranca cualquier programa) sí lo están, porque MAIN y los workers los necesitan, y **ni los `deny` ni el guard analizan
el texto interior**: es un riesgo residual asumido, mitigado por convención (MAIN solo habla con sus workers, comprobar el estado con `hc get` antes de enviar, nunca `--force`, que
además está en `deny`). Los `deny` (merge, force-push, push a `main`) siguen igual y el guard de push bloquea además
`--mirror`, `--all` y `+refspec`.
Limpieza: tras cada merge MAIN elimina el worktree, borra la rama local (`-D`, por el squash) y hace `git fetch --prune` (GitHub ya borra la remota),
solo si el PR está `MERGED`, el HEAD del worktree (no solo la rama) es el `headRefOid` del PR, el árbol está limpio (incluidos ignorados no regenerables)
y las ramas `pre-rebase-*` son ancestro del PR. `git branch -D main*` está en `deny`; `--force` solo en `git worktree remove`, nunca en push. Un worktree con submódulos exige `--force` en git plano
(pide confirmación) hasta que exista `./build.sh worktree-remove` (#54).
MAIN nunca responde a un diálogo de permisos de otro agente. `./build.sh worktree` no ejecuta `./build.sh setup`: lo hace el worker.

## Propuestas pendientes de tu OK (no activadas)
- **Sandbox**: en `.claude/settings.json` añadir `"sandbox": {"enabled": true, "autoAllowBashIfSandboxed": true, "network": {"allowedDomains": ["github.com", "api.github.com"]}}`. Menos confirmaciones sin salir del repo.
- **Claude en CI**: `anthropics/claude-code-action@v1` con el plugin `code-review@claude-plugins-official` en `pull_request`; requiere el secreto `ANTHROPIC_API_KEY` (o `CLAUDE_CODE_OAUTH_TOKEN`) que añadirías tú en GitHub. No se ha creado ningún workflow ni secreto.
- **LSP**: Odin no tiene plugin LSP oficial para Claude Code; se puede crear un plugin propio con `.lsp.json` apuntando a `ols`. Mientras tanto: `./build.sh check` y el hook post-edición dan los errores del compilador.
- **Hot reload** de shaders/estética (juego como DLL recargable): propuesta para la Fase 4, fuera de la build de release.
