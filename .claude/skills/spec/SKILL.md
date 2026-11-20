---
name: spec
description: Entrevista al usuario sobre una fase o feature y escribe la spec en docs/specs/.
argument-hint: "<fase o feature>"
disable-model-invocation: true
model: opus
---
Spec de: $ARGUMENTS

1. Lee `docs/architecture.md`, `docs/original.md` y las specs previas relevantes.
2. Entrevista al usuario con AskUserQuestion (opción múltiple) sobre: implementación, UX, casos límite y trade-offs. Una ronda por tema, sin preguntar lo que el código o los docs ya responden.
3. Escribe `docs/specs/<slug>.md` desde `docs/specs/TEMPLATE.md`: autocontenida, con ficheros e interfaces implicados, fuera de alcance y una verificación de punta a punta.
4. No implementes. Propón abrir un PR de solo docs (rama `docs/spec-<slug>`).
