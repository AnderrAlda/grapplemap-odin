# 0001. Registro de decisiones de arquitectura
Estado: aceptado
Fecha: 2026-11-20
## Contexto
El código lo escribe en gran parte una IA; las decisiones de arquitectura deben quedar fuera de la memoria de sesión y ser revisables.
## Decisión
Cada decisión de arquitectura (formato de datos, técnica de render de cuerpos, librería de UI, etc.) se registra como ADR en `docs/adr/NNNN-titulo.md` usando `TEMPLATE.md`, y se revisa en el PR que la introduce.
## Alternativas consideradas
Wiki externa (se desincroniza del código); comentarios en el código (sin contexto ni alternativas).
## Consecuencias
Un fichero más por decisión; CLAUDE.md referencia los ADR relevantes.
