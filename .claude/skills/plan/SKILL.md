---
name: plan
description: En plan mode, explora el código y escribe el plan de una tarea en docs/plans/<issue>-<slug>.md.
argument-hint: "<nº de issue>"
disable-model-invocation: true
model: opus
---
Plan del issue #$ARGUMENTS

1. Entra en plan mode. Lee el issue (`gh issue view $ARGUMENTS`) y la spec de la fase. Explora con el subagente `explorer`, no leyendo cientos de ficheros.
2. Escribe `docs/plans/$ARGUMENTS-<slug>.md` desde `docs/plans/TEMPLATE.md`: pasos, ficheros a tocar, tests a escribir primero, riesgos y criterio de "hecho".
3. Para y espera mi revisión. No edites código.
