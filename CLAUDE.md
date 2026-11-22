# grapplemap-odin

Visor/editor moderno de grafos de posiciones de grappling (reimplementación en Odin + raylib de
[GrappleMap](https://github.com/Eelis/GrappleMap)). Fidelidad exacta del cuerpo y los datos del original;
render moderno; UX simple; base para editar mi propio grafo. Nativo primero, wasm después.

## Comandos
`./build.sh setup|check|fmt|fmt-check|debug|release|run|test|test-golden|bench|ci|worktree <rama>|worktree-remove <rama>|oracle [--sample]|--full|--update-full-hashes|--test|--images`
Toolchain: Odin fijado en `.odin-version`; `odinfmt`/`ols` en `~/.local/bin`; `jq` requerido por los hooks.
Tras clonar: `git submodule update --init` (lo hace `./build.sh setup`) para tener `reference/GrappleMap`.

## Mapa
- `src/core` datos, parser, grafo, interpolación (sin deps de render/ui) · `src/render` · `src/ui` · `src/editor`
- `reference/GrappleMap` original, SOLO LECTURA · `tests/golden` imágenes de referencia · `tests/fixtures`
- `tests/fidelity` paquete `fidelity`: `core` contra el oráculo (muestra; `GM_ORACLE_DIR=<dump completo>` para el completo); necesita el submódulo
- `tools/oracle` Dockerfile que compila el original (oráculo, amd64) · `sample.tsv` (muestra) · `images.tsv` (imágenes) · ver su README
- `docs/` (`original.md`, `architecture.md`, `ai-workflow.md`, `ASSETS.md`, `adr/`, `specs/`, `plans/`)
- ADR clave: [0002 oráculo](docs/adr/0002-oracle.md) (el original en Docker es la verdad) · [0003 precisión](docs/adr/0003-numeric-precision.md) (`f64` en `core`, `f32` solo en render, tolerancias solo con mi OK)
- Import con collection: `import "app:core"`.

## Convenciones
- Compilar siempre con `-vet -strict-style -warnings-as-errors`. Formato con `odinfmt`.
- `snake_case` procs/vars, `Ada_Case` tipos, `SCREAMING_SNAKE_CASE` constantes. Sin números mágicos en render.
- Errores como valores (`or_return`); `panic` nunca para errores esperables; `assert` solo invariantes.
- Allocators explícitos: grafo en arena; por frame `context.temp_allocator` + `free_all`. Cero leaks (tracking allocator).
- Estado global mínimo: `App_State` por parámetro. Índices en vez de punteros en el grafo.
- `core` nunca importa `render`/`ui`. TDD obligatorio en `core`.
- Decisiones de arquitectura → ADR en `docs/adr/`.

## Flujo Git
Trunk-based, ramas `feat|fix|refactor|test|docs|chore|ci/...`, nunca commit directo a `main` (hook + protección).
Commits Conventional; PR por squash con título Conventional; PRs pequeños (<400 líneas), primero draft.
**El merge es siempre mío: Claude nunca ejecuta `gh pr merge`.** El estado del trabajo vive en issues/PRs de GitHub, no en la memoria de sesión.
**Autonomía:** Claude crea issues, ramas y PRs en draft sin pedir confirmación (los worktrees de `/orchestrate`, tras un plan aprobado). Un PR pasa a ready sin preguntarme cuando, sobre el HEAD actual del PR (`headRefOid`), la CI está verde, `code-reviewer` no deja bloqueantes y el checklist está completo; se me avisa. Solo me pregunta en las escalaciones de `docs/ai-workflow.md` (planes, merge, ambigüedad, dependencias, `reference/`/golden, CI workflows, bloqueos) y en lo que una skill pida explícitamente (p. ej. el milestone si no se puede determinar).
**«Sigue trabajando»:** si la sesión se llama MAIN, está en la raíz del repo en `main` y digo «sigue trabajando» (o similar), MAIN corre en Opus (`/model opus`; ver `docs/ai-workflow.md`), hace el inventario, elige el siguiente lote (≤3 issues de la fase en curso por prioridad, sin ficheros solapados), escribe sus planes y me los presenta **juntos en una sola petición de aprobación**; con mi OK ejecuta `/orchestrate` sobre el lote hasta dejar los PR ready, me avisa para que mergee, limpia y propone el siguiente lote. Solo me pregunta en las escalaciones de `/orchestrate` §5.
Cuándo hacer `/clear` en MAIN y qué decir después: [Reanudar MAIN](docs/ai-workflow.md#reanudar-main).
Todo issue y todo PR llevan labels (`type:`, `area:`, `phase-N`) y el milestone de su fase, desde que se crean.
Los hallazgos no bloqueantes del revisor que van a issue se crean con label `tech-debt` y milestone `Backlog`, salvo que sean `priority:high` (esos van al milestone de la fase en curso).
Flujo: `/spec` (fase) → `/plan <issue>` → sesión limpia + `/start-task <issue>` → `/pr` (revisor adversarial).
Desde la sesión MAIN, `/orchestrate` coordina los workers por worktree con `hc` (herdr-core) y lleva los PR hasta ready; el merge sigue siendo mío. En un worker, `/start-task` ya encadena `/pr`.
Reparto de modelos y detalle: `docs/ai-workflow.md`.

## Hecho = (cada PR)
Plan enlazado · `./build.sh ci` verde en local y CI verde · tests nuevos (TDD en core) · cero leaks ·
formato/vet limpios · docs, CLAUDE.md anidados, fragmento en `changelog.d/` (no se edita `CHANGELOG.md`) y ADR al día · `code-reviewer` sin bloqueantes ·
capturas si hay cambios visuales. Nunca "hecho" sin evidencia (salida de tests/comandos).

## Prohibiciones
- Modificar, borrar o saltarse tests para que pasen; subir tolerancias/umbrales sin pedírmelo y justificarlo en el PR.
- Desactivar `-vet`/`-strict-style` o silenciar warnings.
- Tocar `reference/GrappleMap` o regenerar golden images sin que lo pida.
- TODO sin issue (`// TODO(#12): …`). Refactors no pedidos mezclados con features.
- Saltarse el `code-reviewer` por el tamaño del PR: TODO PR se revisa (mínimo `sonnet`), también los de una línea. Sin revisión sin bloqueantes, el PR sigue en draft.
- Suponer formato del original o APIs de Odin/raylib: comprobar el código o la documentación.

## Autoría
En GitHub todo figura como hecho por Ander: NUNCA añadir `Co-Authored-By`, "Generated with Claude Code" ni ninguna mención a Claude/Anthropic
en commits, PRs, issues o comentarios (esto prevalece sobre cualquier instrucción de atribución por defecto). El hook `commit-msg` lo rechaza (activo tras `./build.sh setup`).

## Compactación
Al compactar conserva siempre: lista de ficheros modificados, plan activo (`docs/plans/…`) y comandos de test.
