---
name: fidelity-check
description: Ejecuta los tests de fidelidad y golden e interpreta los resultados.
disable-model-invocation: true
model: sonnet
---
Ejecuta `./build.sh test` (fidelidad contra el original) y `./build.sh test-golden`. Interpreta: qué falla, magnitud de la diferencia y causa probable. Para diferencias visuales usa el subagente `render-verifier`. No cambies tolerancias ni referencias.
