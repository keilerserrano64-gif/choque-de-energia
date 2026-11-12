<!-- colab:inicio -->
## Trabajo en equipo con Codex (protocolo colab)

En este proyecto trabajan dos IAs a la vez: **Claude Code** (tú, `--ia claude`) y **Codex** (`--ia codex`).
Se coordinan con `colab.py` para no sobrescribirse y apoyarse. Reglas obligatorias:

1. **Al empezar cada tarea** ejecuta `python colab.py estado --ia claude`: verás mensajes nuevos de Codex, tareas abiertas y qué archivos tiene tomados.
2. **Bloqueo automático**: un hook toma cada archivo cuando lo editas con Edit/Write y lo suelta al terminar tu turno.
   - Si el hook te bloquea porque Codex tiene el archivo, NO intentes editarlo por otro camino (Bash, sed, cp, mv, rm…). Trabaja en otra parte, deja una nota o espera con `python colab.py esperar RUTA --ia claude --tomar`.
   - Si vas a modificar archivos con Bash (scripts, generadores, mv, rm), tómalos antes: `python colab.py tomar RUTA... --ia claude --motivo "..."`.
3. **Comunícate**: `python colab.py nota --ia claude "texto"` para avisar cambios de API, nombres, decisiones, bugs o preguntas (usa `@codex` para dirigirte a Codex).
4. **Reparte el trabajo** con el tablero: `python colab.py tarea lista`, `tarea nueva "título" --ia claude --para codex`, `tarea tomar N --ia claude`, `tarea revision N --ia claude` (pide revisión a Codex), `tarea hecha N --ia claude`.
5. **Apóyate en Codex**: antes de cambiar algo que Codex hizo, lee sus notas; si revisas su trabajo, deja las sugerencias como nota y edita solo después de tomar el archivo.
6. Nunca borres `.colab/` ni edites `estado.json` a mano. Si algo se dañó: `python colab.py respaldos RUTA` y `python colab.py restaurar RUTA N --ia claude`.
<!-- colab:fin -->
