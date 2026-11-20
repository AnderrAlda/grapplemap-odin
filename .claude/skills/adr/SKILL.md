---
name: adr
description: Crea un ADR nuevo a partir de la plantilla en docs/adr/.
argument-hint: "<título>"
disable-model-invocation: true
model: opus
---
Crea `docs/adr/NNNN-<slug>.md` (siguiente número libre) desde `docs/adr/TEMPLATE.md` para: $ARGUMENTS.
Rellena contexto, decisión, alternativas y consecuencias con lo conocido; marca lo dudoso para que lo decida el usuario. Enlázalo desde CLAUDE.md si es una decisión estructural.
