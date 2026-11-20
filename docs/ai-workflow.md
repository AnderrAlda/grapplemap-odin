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
Excepción: cambios describibles en una frase van directos, con PR pequeño.

## Enforcement (qué lo hace cumplir)
- Permisos en `.claude/settings.json` (allow/ask/deny; deny gana siempre). Personal: `.claude/settings.local.json` (ignorado por git).
- Hooks (`.claude/hooks/`): formato+check tras editar `.odin`; bloqueo de `reference/` y `tests/golden/`; bloqueo de commit/push en `main` y comandos destructivos; `Stop` ejecuta `check`+tests; `SessionStart` muestra rama/issue.
- El `Stop` hook respeta `stop_hook_active` para no hacer bucles. Claude Code fuerza la parada tras 8 bloqueos seguidos
  (`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`): si ocurre, el resumen debe decirlo y la tarea NO se da por buena.

## Protección de `main` (sin branch protection de GitHub)
El repo es privado sin plan Pro, así que GitHub no puede proteger `main`. La protección depende **solo de los hooks locales** y exige haber ejecutado `./build.sh setup` en cada clon/worktree (activa `core.hooksPath=.githooks`):
- git `pre-commit`: bloquea commits en `main`. git `pre-push`: bloquea cualquier push cuyo destino sea `refs/heads/main` (también `git push origin feat:main`).
- Guard de Claude (`.claude/hooks/guard-bash.sh` + reglas `deny`): bloquea commit/push estando en `main`, pushes con destino `main` desde cualquier rama, `--force`, `--no-verify` y `gh pr merge`.
- Los merges se hacen **solo desde GitHub** (squash). Un `git push --no-verify` manual o un clon sin `setup` saltan los hooks git: no hay defensa del lado del servidor hasta activar GitHub Pro o hacer el repo público.

## Worktrees (varios agentes)
`./build.sh worktree <rama>` crea `../grapplemap-odin-wt/<rama>`. Un worktree por rama/agente; nunca dos agentes en la misma rama.

## Propuestas pendientes de tu OK (no activadas)
- **Sandbox**: en `.claude/settings.json` añadir `"sandbox": {"enabled": true, "autoAllowBashIfSandboxed": true, "network": {"allowedDomains": ["github.com", "api.github.com"]}}`. Menos confirmaciones sin salir del repo.
- **Claude en CI**: `anthropics/claude-code-action@v1` con el plugin `code-review@claude-plugins-official` en `pull_request`; requiere el secreto `ANTHROPIC_API_KEY` (o `CLAUDE_CODE_OAUTH_TOKEN`) que añadirías tú en GitHub. No se ha creado ningún workflow ni secreto.
- **LSP**: Odin no tiene plugin LSP oficial para Claude Code; se puede crear un plugin propio con `.lsp.json` apuntando a `ols`. Mientras tanto: `./build.sh check` y el hook post-edición dan los errores del compilador.
- **Hot reload** de shaders/estética (juego como DLL recargable): propuesta para la Fase 4, fuera de la build de release.
