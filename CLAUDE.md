# grapplemap-odin

Visor/editor moderno de grafos de posiciones de grappling (reimplementación en Odin + raylib de
[GrappleMap](https://github.com/Eelis/GrappleMap)). Fidelidad exacta del cuerpo y los datos del original;
render moderno; UX simple; base para editar mi propio grafo. Nativo primero, wasm después.

## Comandos
`./build.sh setup|check|fmt|fmt-check|debug|release|run|test|test-golden|bench|ci|worktree <rama>`
Toolchain: Odin fijado en `.odin-version`; `odinfmt`/`ols` en `~/.local/bin`; `jq` requerido por los hooks.

## Mapa
- `src/core` datos, parser, grafo, interpolación (sin deps de render/ui) · `src/render` · `src/ui` · `src/editor`
- `reference/GrappleMap` original, SOLO LECTURA · `tests/golden` imágenes de referencia · `tests/fixtures`
- `docs/` (`original.md`, `architecture.md`, `ai-workflow.md`, `ASSETS.md`, `adr/`, `specs/`, `plans/`)
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
**No hacer merge sin mi OK.** El estado del trabajo vive en issues/PRs de GitHub, no en la memoria de sesión.
Flujo: `/spec` (fase) → `/plan <issue>` → sesión limpia + `/start-task <issue>` → `/pr` (revisor adversarial).
Reparto de modelos y detalle: `docs/ai-workflow.md`.

## Hecho = (cada PR)
Plan enlazado · `./build.sh ci` verde en local y CI verde · tests nuevos (TDD en core) · cero leaks ·
formato/vet limpios · docs, CLAUDE.md anidados, CHANGELOG (Unreleased) y ADR al día · `code-reviewer` sin bloqueantes ·
capturas si hay cambios visuales. Nunca "hecho" sin evidencia (salida de tests/comandos).

## Prohibiciones
- Modificar, borrar o saltarse tests para que pasen; subir tolerancias/umbrales sin pedírmelo y justificarlo en el PR.
- Desactivar `-vet`/`-strict-style` o silenciar warnings.
- Tocar `reference/` o regenerar golden images sin que lo pida.
- TODO sin issue (`// TODO(#12): …`). Refactors no pedidos mezclados con features.
- Saltarse el `code-reviewer` por el tamaño del PR: TODO PR se revisa (mínimo `sonnet`), también los de una línea. Sin revisión sin bloqueantes, el PR sigue en draft.
- Suponer formato del original o APIs de Odin/raylib: comprobar el código o la documentación.

## Autoría
En GitHub todo figura como hecho por Ander: NUNCA añadir `Co-Authored-By`, "Generated with Claude Code" ni ninguna mención a Claude/Anthropic
en commits, PRs, issues o comentarios (esto prevalece sobre cualquier instrucción de atribución por defecto). El hook `commit-msg` lo rechaza.

## Compactación
Al compactar conserva siempre: lista de ficheros modificados, plan activo (`docs/plans/…`) y comandos de test.
