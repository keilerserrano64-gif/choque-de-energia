<!-- colab:inicio -->
## Trabajo en equipo con Claude Code (protocolo colab)

En este proyecto trabajan dos IAs a la vez: **Codex** (tú, `--ia codex`) y **Claude Code** (`--ia claude`).
Se coordinan con `colab.py` para no sobrescribirse y apoyarse. Reglas obligatorias:

1. **Al empezar cada tarea** ejecuta `python colab.py estado --ia codex`: verás mensajes nuevos de Claude Code, tareas abiertas y qué archivos tiene tomados.
2. **ANTES de modificar cualquier archivo, tómalo**: `python colab.py tomar RUTA1 RUTA2 --ia codex --motivo "qué vas a hacer"`.
   - Si el comando falla porque Claude tiene el archivo, NO lo edites, ni lo borres, ni lo renombres (tampoco con comandos de shell). Trabaja en otra parte, deja una nota o espera con `python colab.py esperar RUTA --ia codex --tomar`.
   - Si trabajas más de 30 minutos en un archivo, vuelve a ejecutar `tomar` para renovar el bloqueo.
3. **Al terminar, suelta lo que tomaste**: `python colab.py soltar --ia codex --todo`.
4. **Comunícate**: `python colab.py nota --ia codex "texto"` para avisar cambios de API, nombres, decisiones, bugs o preguntas (usa `@claude` para dirigirte a Claude Code).
5. **Reparte el trabajo** con el tablero: `python colab.py tarea lista`, `tarea nueva "título" --ia codex --para claude`, `tarea tomar N --ia codex`, `tarea revision N --ia codex` (pide revisión a Claude Code), `tarea hecha N --ia codex`.
6. **Apóyate en Claude Code**: antes de cambiar algo que Claude Code hizo, lee sus notas; si revisas su trabajo, deja las sugerencias como nota y edita solo después de tomar el archivo.
7. Nunca borres `.colab/` ni edites `estado.json` a mano. Si algo se dañó: `python colab.py respaldos RUTA` y `python colab.py restaurar RUTA N --ia codex`.
<!-- colab:fin -->
