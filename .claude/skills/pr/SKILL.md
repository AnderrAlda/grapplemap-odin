---
name: pr
description: Ejecuta ./build.sh ci, lanza el code-reviewer, rellena la plantilla y abre el PR como draft.
disable-model-invocation: true
model: sonnet
---
1. Verifica que no estás en `main` y ejecuta `./build.sh ci`; si falla, para.
2. Mira las áreas tocadas (`git diff --stat main...HEAD`). Lanza el subagente `code-reviewer` con `model: opus` si toca `src/core`, `src/render`, shaders o ADRs/arquitectura; con `model: sonnet` en el resto.
3. Corrige los bloqueantes y vuelve a revisar.
4. Rellena `.github/pull_request_template.md` (plan enlazado, `Closes #N`, cómo probar, capturas si hay cambios visuales). Título Conventional Commit.
5. Sin ninguna mención a Claude/Anthropic ni "Generated with" en el título o cuerpo. Pide confirmación y abre con `gh pr create --draft`. No marques ready hasta que la CI esté verde. NO hagas merge.
