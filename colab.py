#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
colab.py - Coordina a Claude Code y Codex trabajando en el MISMO proyecto
sin pisarse el trabajo.

Los dos agentes comparten una carpeta .colab/ con:
  - bloqueos por archivo  -> nadie edita lo que el otro tiene tomado
  - tablero de tareas     -> se reparten el trabajo y se piden revisiones
  - bitacora de mensajes  -> se avisan cambios, dudas y hallazgos
  - respaldos automaticos -> antes de cada edicion se guarda una copia

Claude Code queda integrado con hooks (bloqueo automatico).
Codex sigue el protocolo que se escribe en AGENTS.md.

Solo usa la libreria estandar de Python 3.8+.
Uso rapido:  python colab.py init      (en la raiz de tu proyecto)
             python colab.py --help
"""
import argparse
import datetime
import hashlib
import json
import os
import shutil
import sys
import time

CARPETA = ".colab"
TTL_MIN = 30            # minutos que dura un bloqueo sin renovarse
MAX_MENSAJES = 300
MAX_RESPALDOS = 20      # respaldos guardados por archivo
IAS = ("claude", "codex", "humano")
MARCA_INI = "<!-- colab:inicio -->"
MARCA_FIN = "<!-- colab:fin -->"
ES_WIN = os.name == "nt"
PY = "python" if ES_WIN else "python3"

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except Exception:
        pass


# ----------------------------------------------------------------- utilidades
def salir(msg, codigo=1):
    print(msg, file=sys.stderr)
    sys.exit(codigo)


def hora(ts, corta=False):
    fmt = "%H:%M" if corta else "%Y-%m-%d %H:%M"
    return datetime.datetime.fromtimestamp(ts).strftime(fmt)


def otra(ia):
    return {"claude": "codex", "codex": "claude"}.get(ia, "claude")


def buscar_raiz(obligatoria=True):
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env and os.path.isfile(os.path.join(env, CARPETA, "estado.json")):
        return os.path.abspath(env)
    d = os.getcwd()
    while True:
        if os.path.isfile(os.path.join(d, CARPETA, "estado.json")):
            return d
        padre = os.path.dirname(d)
        if padre == d:
            break
        d = padre
    if obligatoria:
        salir("No encontré la carpeta .colab/ en este proyecto.\n"
              f"Ejecuta primero en la raíz del proyecto:  {PY} colab.py init")
    return None


def clave(root, ruta, base=None):
    """Convierte cualquier ruta en una clave relativa a la raíz del proyecto."""
    if not os.path.isabs(ruta):
        ruta = os.path.join(base or os.getcwd(), ruta)
    try:
        r = os.path.relpath(os.path.abspath(ruta), root)
    except ValueError:          # otra unidad en Windows
        return None
    if r == ".." or r.startswith(".." + os.sep):
        return None
    r = r.replace(os.sep, "/")
    return r.lower() if ES_WIN else r


def hash_archivo(path):
    if not os.path.isfile(path):
        return None
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for bloque in iter(lambda: f.read(65536), b""):
            h.update(bloque)
    return h.hexdigest()


# ------------------------------------------------- exclusión mutua del estado
class Mutex:
    """Evita que Claude y Codex escriban estado.json al mismo tiempo."""

    def __init__(self, root):
        self.p = os.path.join(root, CARPETA, ".mutex")

    def __enter__(self):
        inicio = time.time()
        while True:
            try:
                fd = os.open(self.p, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.write(fd, str(os.getpid()).encode())
                os.close(fd)
                return self
            except FileExistsError:
                try:
                    if time.time() - os.path.getmtime(self.p) > 10:   # mutex huérfano
                        os.remove(self.p)
                        continue
                except FileNotFoundError:
                    continue
                if time.time() - inicio > 20:
                    salir("colab: el estado está ocupado; intenta de nuevo.")
                time.sleep(0.05)

    def __exit__(self, *exc):
        try:
            os.remove(self.p)
        except FileNotFoundError:
            pass


def estado_inicial():
    return {"version": 1, "bloqueos": {}, "tareas": [], "sig_tarea": 1,
            "mensajes": [], "sig_msg": 1, "leido": {}}


def cargar(root):
    with open(os.path.join(root, CARPETA, "estado.json"), encoding="utf-8") as f:
        return json.load(f)


def guardar(root, est):
    p = os.path.join(root, CARPETA, "estado.json")
    tmp = f"{p}.{os.getpid()}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(est, f, ensure_ascii=False, indent=2)
    for intento in range(20):          # Windows a veces tiene el archivo abierto
        try:
            os.replace(tmp, p)
            return
        except PermissionError:
            time.sleep(0.05)
    os.replace(tmp, p)


# ------------------------------------------------------------ piezas internas
def mensaje(root, est, ia, texto):
    m = {"id": est["sig_msg"], "ia": ia, "ts": time.time(), "texto": texto}
    est["sig_msg"] += 1
    est["mensajes"].append(m)
    est["mensajes"] = est["mensajes"][-MAX_MENSAJES:]
    with open(os.path.join(root, CARPETA, "bitacora.md"), "a", encoding="utf-8") as f:
        f.write(f"- `{hora(m['ts'])}` **{ia}**: {texto}\n")


def limpiar_vencidos(root, est):
    t = time.time()
    for k, b in list(est["bloqueos"].items()):
        if b["vence"] < t:
            del est["bloqueos"][k]
            mensaje(root, est, "colab", f"venció el bloqueo de `{k}` que tenía {b['ia']}")


def respaldar(root, k, ia):
    origen = os.path.join(root, k)
    if not os.path.isfile(origen):
        return None
    carpeta = os.path.join(root, CARPETA, "respaldos", k.replace("/", "__"))
    os.makedirs(carpeta, exist_ok=True)
    nombre = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")[:-3] + f"_{ia}"
    shutil.copy2(origen, os.path.join(carpeta, nombre))
    viejos = sorted(os.listdir(carpeta))[:-MAX_RESPALDOS]
    for v in viejos:
        os.remove(os.path.join(carpeta, v))
    return nombre


def tomar_interno(root, est, claves, ia, motivo, minutos=TTL_MIN, registrar=True):
    """Toma todos los archivos o ninguno. Devuelve la lista de conflictos."""
    conflictos = [(k, est["bloqueos"][k]) for k in claves
                  if k in est["bloqueos"] and est["bloqueos"][k]["ia"] != ia]
    if conflictos:
        return conflictos
    nuevos = []
    t = time.time()
    for k in claves:
        b = est["bloqueos"].get(k)
        if b:                                   # ya era mío: solo renuevo
            b["vence"] = t + minutos * 60
            continue
        est["bloqueos"][k] = {
            "ia": ia, "motivo": motivo, "desde": t, "vence": t + minutos * 60,
            "hash": hash_archivo(os.path.join(root, k)),
            "respaldo": respaldar(root, k, ia),
        }
        nuevos.append(k)
    if nuevos and registrar:
        lista = ", ".join(f"`{k}`" for k in nuevos)
        mensaje(root, est, ia, f"tomó {lista}" + (f" — {motivo}" if motivo else ""))
    return []


def soltar_interno(root, est, ia, claves=None):
    res = []
    for k, b in list(est["bloqueos"].items()):
        if b["ia"] != ia or (claves is not None and k not in claves):
            continue
        cambio = hash_archivo(os.path.join(root, k)) != b.get("hash")
        res.append((k, cambio))
        del est["bloqueos"][k]
    return res


def describir_bloqueo(k, b):
    motivo = f'  "{b["motivo"]}"' if b.get("motivo") else ""
    return (f"  {k}  ->  {b['ia']} (desde {hora(b['desde'], True)}, "
            f"vence {hora(b['vence'], True)}){motivo}")


def describir_tarea(t):
    extra = f" ({t['ia']})" if t.get("ia") else ""
    if t["estado"] == "revision" and t.get("revisor"):
        extra += f" -> revisa: {t['revisor']}"
    if t.get("para") and not t.get("ia"):
        extra += f" (sugerida para {t['para']})"
    return f"  #{t['id']} [{t['estado']}]{extra} {t['titulo']}"


def mensajes_nuevos(est, ia, marcar=True):
    visto = est["leido"].get(ia, 0)
    nuevos = [m for m in est["mensajes"] if m["id"] > visto and m["ia"] != ia]
    if marcar and est["mensajes"]:
        est["leido"][ia] = est["mensajes"][-1]["id"]
    return nuevos


# ------------------------------------------------------------------- comandos
def protocolo(yo):
    el = "Claude Code" if yo == "codex" else "Codex"
    nombre = "Codex" if yo == "codex" else "Claude Code"
    c = f"{PY} colab.py"
    texto = f"""{MARCA_INI}
## Trabajo en equipo con {el} (protocolo colab)

En este proyecto trabajan dos IAs a la vez: **{nombre}** (tú, `--ia {yo}`) y **{el}** (`--ia {otra(yo)}`).
Se coordinan con `colab.py` para no sobrescribirse y apoyarse. Reglas obligatorias:

1. **Al empezar cada tarea** ejecuta `{c} estado --ia {yo}`: verás mensajes nuevos de {el}, tareas abiertas y qué archivos tiene tomados.
"""
    if yo == "claude":
        texto += f"""2. **Bloqueo automático**: un hook toma cada archivo cuando lo editas con Edit/Write y lo suelta al terminar tu turno.
   - Si el hook te bloquea porque Codex tiene el archivo, NO intentes editarlo por otro camino (Bash, sed, cp, mv, rm…). Trabaja en otra parte, deja una nota o espera con `{c} esperar RUTA --ia claude --tomar`.
   - Si vas a modificar archivos con Bash (scripts, generadores, mv, rm), tómalos antes: `{c} tomar RUTA... --ia claude --motivo "..."`.
"""
    else:
        texto += f"""2. **ANTES de modificar cualquier archivo, tómalo**: `{c} tomar RUTA1 RUTA2 --ia codex --motivo "qué vas a hacer"`.
   - Si el comando falla porque Claude tiene el archivo, NO lo edites, ni lo borres, ni lo renombres (tampoco con comandos de shell). Trabaja en otra parte, deja una nota o espera con `{c} esperar RUTA --ia codex --tomar`.
   - Si trabajas más de {TTL_MIN} minutos en un archivo, vuelve a ejecutar `tomar` para renovar el bloqueo.
3. **Al terminar, suelta lo que tomaste**: `{c} soltar --ia codex --todo`.
"""
    n = 3 if yo == "claude" else 4
    texto += f"""{n}. **Comunícate**: `{c} nota --ia {yo} "texto"` para avisar cambios de API, nombres, decisiones, bugs o preguntas (usa `@{otra(yo)}` para dirigirte a {el}).
{n+1}. **Reparte el trabajo** con el tablero: `{c} tarea lista`, `tarea nueva "título" --ia {yo} --para {otra(yo)}`, `tarea tomar N --ia {yo}`, `tarea revision N --ia {yo}` (pide revisión a {el}), `tarea hecha N --ia {yo}`.
{n+2}. **Apóyate en {el}**: antes de cambiar algo que {el} hizo, lee sus notas; si revisas su trabajo, deja las sugerencias como nota y edita solo después de tomar el archivo.
{n+3}. Nunca borres `.colab/` ni edites `estado.json` a mano. Si algo se dañó: `{c} respaldos RUTA` y `{c} restaurar RUTA N --ia {yo}`.
{MARCA_FIN}
"""
    return texto


def escribir_bloque(ruta, bloque):
    """Inserta/actualiza el bloque del protocolo sin tocar el resto del archivo."""
    previo = ""
    if os.path.isfile(ruta):
        with open(ruta, encoding="utf-8") as f:
            previo = f.read()
    if MARCA_INI in previo and MARCA_FIN in previo:
        a = previo.index(MARCA_INI)
        b = previo.index(MARCA_FIN) + len(MARCA_FIN)
        nuevo = previo[:a] + bloque.strip() + previo[b:]
    else:
        nuevo = (previo.rstrip() + "\n\n" if previo.strip() else "") + bloque
    with open(ruta, "w", encoding="utf-8") as f:
        f.write(nuevo)


def instalar_hooks(root):
    ruta = os.path.join(root, ".claude", "settings.json")
    cfg = {}
    if os.path.isfile(ruta):
        with open(ruta, encoding="utf-8") as f:
            try:
                cfg = json.load(f)
            except json.JSONDecodeError:
                salir(f"{ruta} no es JSON válido; arréglalo o usa init --sin-hooks")
    os.makedirs(os.path.dirname(ruta), exist_ok=True)
    cmd = lambda sub: f'{PY} "$CLAUDE_PROJECT_DIR/colab.py" {sub}'
    eventos = [
        ("PreToolUse", "Edit|Write|MultiEdit|NotebookEdit", cmd("hook-pre")),
        ("Stop", None, cmd("hook-stop")),
        ("UserPromptSubmit", None, cmd("hook-prompt")),
    ]
    hooks = cfg.setdefault("hooks", {})
    for evento, matcher, comando in eventos:
        lista = hooks.setdefault(evento, [])
        ya = any("colab.py" in h.get("command", "")
                 for g in lista for h in g.get("hooks", []))
        if ya:
            continue
        grupo = {"hooks": [{"type": "command", "command": comando}]}
        if matcher:
            grupo = {"matcher": matcher, **grupo}
        lista.append(grupo)
    with open(ruta, "w", encoding="utf-8") as f:
        json.dump(cfg, f, ensure_ascii=False, indent=2)


def cmd_init(a):
    root = os.getcwd()
    base = os.path.join(root, CARPETA)
    os.makedirs(os.path.join(base, "respaldos"), exist_ok=True)
    if not os.path.isfile(os.path.join(base, "estado.json")):
        guardar(root, estado_inicial())
    bit = os.path.join(base, "bitacora.md")
    if not os.path.isfile(bit):
        with open(bit, "w", encoding="utf-8") as f:
            f.write("# Bitácora compartida Claude Code + Codex\n\n")
    with open(os.path.join(base, ".gitignore"), "w", encoding="utf-8") as f:
        f.write("respaldos/\n.mutex\n*.tmp\n")
    destino = os.path.join(root, "colab.py")
    if os.path.abspath(__file__) != os.path.abspath(destino):
        shutil.copy2(os.path.abspath(__file__), destino)
    escribir_bloque(os.path.join(root, "CLAUDE.md"), protocolo("claude"))
    escribir_bloque(os.path.join(root, "AGENTS.md"), protocolo("codex"))
    if not a.sin_hooks:
        instalar_hooks(root)
    print("Listo. Proyecto preparado para Claude Code + Codex:")
    print("  .colab/                estado, bitácora y respaldos compartidos")
    print("  CLAUDE.md / AGENTS.md  protocolo para cada IA (tu contenido anterior se conserva)")
    if not a.sin_hooks:
        print("  .claude/settings.json  hooks de bloqueo automático para Claude Code")
    print(f"\nPrueba:  {PY} colab.py estado")


def cmd_estado(a):
    root = buscar_raiz()
    with Mutex(root):
        est = cargar(root)
        limpiar_vencidos(root, est)
        nuevos = mensajes_nuevos(est, a.ia) if a.ia else None
        guardar(root, est)
    print("=== COLAB · estado del proyecto ===")
    print("\nArchivos tomados:")
    if est["bloqueos"]:
        for k, b in sorted(est["bloqueos"].items()):
            print(describir_bloqueo(k, b))
    else:
        print("  (ninguno: todo está libre)")
    abiertas = [t for t in est["tareas"] if t["estado"] != "hecha"]
    print("\nTareas abiertas:")
    print("\n".join(describir_tarea(t) for t in abiertas) if abiertas else "  (ninguna)")
    if a.ia:
        print(f"\nMensajes nuevos para {a.ia}:")
        lista = nuevos
    else:
        print("\nÚltimos mensajes:")
        lista = est["mensajes"][-10:]
    if lista:
        for m in lista:
            print(f"  [{hora(m['ts'], True)}] {m['ia']}: {m['texto']}")
    else:
        print("  (sin mensajes nuevos)")


def cmd_tomar(a):
    root = buscar_raiz()
    claves = []
    for r in a.archivos:
        k = clave(root, r)
        if not k:
            salir(f"'{r}' está fuera del proyecto.")
        claves.append(k)
    with Mutex(root):
        est = cargar(root)
        limpiar_vencidos(root, est)
        conflictos = tomar_interno(root, est, claves, a.ia, a.motivo or "", a.min)
        guardar(root, est)
    if conflictos:
        print("NO SE TOMÓ NADA. Estos archivos los tiene la otra IA:", file=sys.stderr)
        for k, b in conflictos:
            print(describir_bloqueo(k, b), file=sys.stderr)
        salir(f"No los edites. Trabaja en otra cosa, deja una nota, o espera con:\n"
              f"  {PY} colab.py esperar {conflictos[0][0]} --ia {a.ia} --tomar", 3)
    print(f"Tomados por {a.ia} (vencen en {a.min} min): " + ", ".join(claves))


def cmd_soltar(a):
    root = buscar_raiz()
    claves = None if a.todo else [clave(root, r) for r in a.archivos]
    if claves is not None and not claves:
        salir("Indica archivos o usa --todo.")
    with Mutex(root):
        est = cargar(root)
        res = soltar_interno(root, est, a.ia, claves)
        if res:
            partes = [f"`{k}`" + (" (modificado)" if c else " (sin cambios)") for k, c in res]
            mensaje(root, est, a.ia, "soltó " + ", ".join(partes))
        guardar(root, est)
    print("Soltados: " + (", ".join(k for k, _ in res) if res else "(nada que soltar)"))


def cmd_esperar(a):
    root = buscar_raiz()
    k = clave(root, a.archivo)
    if not k:
        salir(f"'{a.archivo}' está fuera del proyecto.")
    limite = time.time() + a.max
    avisado = False
    while True:
        with Mutex(root):
            est = cargar(root)
            limpiar_vencidos(root, est)
            b = est["bloqueos"].get(k)
            libre = not b or b["ia"] == a.ia
            if libre and a.tomar:
                tomar_interno(root, est, [k], a.ia, a.motivo or "")
            guardar(root, est)
        if libre:
            print(f"`{k}` está libre" + (f" y ahora lo tiene {a.ia}." if a.tomar else "."))
            return
        if not avisado:
            print(f"Esperando a que {b['ia']} suelte `{k}`... (máx {a.max}s)")
            avisado = True
        if time.time() > limite:
            salir(f"Se acabó la espera: `{k}` sigue tomado por {b['ia']}.", 3)
        time.sleep(3)


def cmd_nota(a):
    root = buscar_raiz()
    with Mutex(root):
        est = cargar(root)
        mensaje(root, est, a.ia, " ".join(a.texto))
        guardar(root, est)
    print("Nota guardada en la bitácora.")


def buscar_tarea(est, n):
    for t in est["tareas"]:
        if t["id"] == n:
            return t
    salir(f"No existe la tarea #{n}.")


def cmd_tarea(a):
    root = buscar_raiz()
    with Mutex(root):
        est = cargar(root)
        if a.accion == "lista":
            tareas = est["tareas"] if a.todas else [t for t in est["tareas"] if t["estado"] != "hecha"]
            print("\n".join(describir_tarea(t) for t in tareas) if tareas else "(sin tareas)")
            return
        if not a.ia:
            salir("Indica quién eres con --ia claude|codex|humano")
        if a.accion == "nueva":
            titulo = " ".join(a.args)
            if not titulo:
                salir("Escribe el título de la tarea.")
            t = {"id": est["sig_tarea"], "titulo": titulo, "estado": "pendiente",
                 "ia": None, "para": a.para, "creada_por": a.ia, "revisor": None}
            est["sig_tarea"] += 1
            est["tareas"].append(t)
            dest = f" para @{a.para}" if a.para else ""
            mensaje(root, est, a.ia, f"creó la tarea #{t['id']}{dest}: {titulo}")
        else:
            if not a.args or not a.args[0].lstrip("#").isdigit():
                salir("Indica el número de la tarea, p. ej.: tarea tomar 3 --ia codex")
            t = buscar_tarea(est, int(a.args[0].lstrip("#")))
            nota = f" — {a.nota}" if a.nota else ""
            if a.accion == "tomar":
                t.update(estado="en_progreso", ia=a.ia)
                mensaje(root, est, a.ia, f"empezó la tarea #{t['id']}: {t['titulo']}{nota}")
            elif a.accion == "revision":
                t.update(estado="revision", revisor=otra(a.ia))
                mensaje(root, est, a.ia, f"@{otra(a.ia)} por favor revisa la tarea #{t['id']}: {t['titulo']}{nota}")
            elif a.accion == "hecha":
                t.update(estado="hecha")
                mensaje(root, est, a.ia, f"terminó la tarea #{t['id']}: {t['titulo']}{nota}")
            elif a.accion == "reabrir":
                t.update(estado="pendiente", ia=None, revisor=None)
                mensaje(root, est, a.ia, f"reabrió la tarea #{t['id']}: {t['titulo']}{nota}")
        guardar(root, est)
    print(describir_tarea(t))


def listar_respaldos(root, k):
    carpeta = os.path.join(root, CARPETA, "respaldos", k.replace("/", "__"))
    if not os.path.isdir(carpeta):
        return carpeta, []
    return carpeta, sorted(os.listdir(carpeta), reverse=True)


def cmd_respaldos(a):
    root = buscar_raiz()
    k = clave(root, a.archivo)
    _, lista = listar_respaldos(root, k or "")
    if not lista:
        print(f"No hay respaldos de `{k}`.")
        return
    print(f"Respaldos de `{k}` (1 = el más reciente):")
    for i, n in enumerate(lista, 1):
        fecha, ia = n.rsplit("_", 1)
        d = datetime.datetime.strptime(fecha, "%Y%m%d-%H%M%S-%f")
        print(f"  {i:>2}. {d:%Y-%m-%d %H:%M:%S}  antes de que lo editara {ia}")


def cmd_restaurar(a):
    root = buscar_raiz()
    k = clave(root, a.archivo)
    carpeta, lista = listar_respaldos(root, k or "")
    if not lista or not (1 <= a.n <= len(lista)):
        salir(f"No existe el respaldo {a.n} de `{k}`. Mira la lista con: {PY} colab.py respaldos {a.archivo}")
    with Mutex(root):
        est = cargar(root)
        limpiar_vencidos(root, est)
        b = est["bloqueos"].get(k)
        if b and b["ia"] != a.ia:
            salir(f"`{k}` está tomado por {b['ia']}; no se puede restaurar ahora.", 3)
        respaldar(root, k, a.ia)                     # guarda la versión actual también
        os.makedirs(os.path.dirname(os.path.join(root, k)) or root, exist_ok=True)
        shutil.copy2(os.path.join(carpeta, lista[a.n - 1]), os.path.join(root, k))
        mensaje(root, est, a.ia, f"restauró `{k}` al respaldo {lista[a.n - 1]}")
        guardar(root, est)
    print(f"`{k}` restaurado. La versión que había quedó como respaldo nuevo.")


# ---------------------------------------------------- hooks de Claude Code
def leer_entrada_hook():
    try:
        return json.loads(sys.stdin.read() or "{}")
    except Exception:
        return {}


def cmd_hook_pre(a):
    data = leer_entrada_hook()
    ti = data.get("tool_input") or {}
    ruta = ti.get("file_path") or ti.get("notebook_path")
    root = buscar_raiz(False)
    if not ruta or not root:
        sys.exit(0)
    k = clave(root, ruta, data.get("cwd"))
    if not k or k.startswith(CARPETA + "/"):
        sys.exit(0)
    with Mutex(root):
        est = cargar(root)
        limpiar_vencidos(root, est)
        conflictos = tomar_interno(root, est, [k], "claude", "edición desde Claude Code")
        guardar(root, est)
    if conflictos:
        b = conflictos[0][1]
        motivo = f' ("{b["motivo"]}")' if b.get("motivo") else ""
        print(f"BLOQUEADO por colab: `{k}` lo está editando {b['ia']} desde las "
              f"{hora(b['desde'], True)}{motivo}. No lo modifiques por ningún medio.\n"
              f"Opciones: trabaja en otro archivo; deja una nota con "
              f"`{PY} colab.py nota --ia claude \"@{b['ia']} ...\"`; "
              f"o espera con `{PY} colab.py esperar {k} --ia claude --tomar`.",
              file=sys.stderr)
        sys.exit(2)
    sys.exit(0)


def cmd_hook_stop(a):
    leer_entrada_hook()
    root = buscar_raiz(False)
    if not root:
        sys.exit(0)
    with Mutex(root):
        est = cargar(root)
        res = soltar_interno(root, est, "claude")
        if res:
            mod = [f"`{k}`" for k, c in res if c]
            sin = [f"`{k}`" for k, c in res if not c]
            texto = "terminó su turno y soltó sus archivos."
            if mod:
                texto += " Modificó: " + ", ".join(mod) + "."
            if sin:
                texto += " Sin cambios: " + ", ".join(sin) + "."
            mensaje(root, est, "claude", texto)
        guardar(root, est)
    sys.exit(0)


def cmd_hook_prompt(a):
    leer_entrada_hook()
    root = buscar_raiz(False)
    if not root:
        sys.exit(0)
    with Mutex(root):
        est = cargar(root)
        limpiar_vencidos(root, est)
        nuevos = mensajes_nuevos(est, "claude")
        guardar(root, est)
    ajenos = {k: b for k, b in est["bloqueos"].items() if b["ia"] != "claude"}
    mias = [t for t in est["tareas"] if t["estado"] != "hecha" and
            ("claude" in (t.get("para"), t.get("ia"), t.get("revisor")))]
    if not (nuevos or ajenos or mias):
        sys.exit(0)
    out = ["[colab] Contexto compartido con Codex:"]
    if nuevos:
        out.append("Mensajes nuevos:")
        out += [f"  [{hora(m['ts'], True)}] {m['ia']}: {m['texto']}" for m in nuevos]
    if ajenos:
        out.append("Archivos que NO puedes editar ahora (los tiene otra IA):")
        out += [describir_bloqueo(k, b) for k, b in sorted(ajenos.items())]
    if mias:
        out.append("Tareas que te tocan:")
        out += [describir_tarea(t) for t in mias]
    print("\n".join(out))
    sys.exit(0)


# ------------------------------------------------------------------- CLI
def main():
    p = argparse.ArgumentParser(
        prog="colab.py",
        description="Coordina a Claude Code y Codex en el mismo proyecto sin sobrescribirse.")
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("init", help="prepara el proyecto (ejecútalo en la raíz)")
    s.add_argument("--sin-hooks", action="store_true", help="no instalar hooks de Claude Code")
    s.set_defaults(f=cmd_init)

    s = sub.add_parser("estado", help="archivos tomados, tareas y mensajes")
    s.add_argument("--ia", choices=IAS, help="muestra solo tus mensajes no leídos")
    s.set_defaults(f=cmd_estado)

    s = sub.add_parser("tomar", help="bloquea archivos antes de editarlos")
    s.add_argument("archivos", nargs="+")
    s.add_argument("--ia", choices=IAS, required=True)
    s.add_argument("--motivo", default="")
    s.add_argument("--min", type=int, default=TTL_MIN, help=f"minutos de bloqueo (def. {TTL_MIN})")
    s.set_defaults(f=cmd_tomar)

    s = sub.add_parser("soltar", help="libera archivos al terminar")
    s.add_argument("archivos", nargs="*")
    s.add_argument("--ia", choices=IAS, required=True)
    s.add_argument("--todo", action="store_true", help="suelta todo lo tuyo")
    s.set_defaults(f=cmd_soltar)

    s = sub.add_parser("esperar", help="espera a que un archivo quede libre")
    s.add_argument("archivo")
    s.add_argument("--ia", choices=IAS, required=True)
    s.add_argument("--tomar", action="store_true", help="tomarlo en cuanto se libere")
    s.add_argument("--motivo", default="")
    s.add_argument("--max", type=int, default=600, help="segundos máximos (def. 600)")
    s.set_defaults(f=cmd_esperar)

    s = sub.add_parser("nota", help="deja un mensaje en la bitácora")
    s.add_argument("texto", nargs="+")
    s.add_argument("--ia", choices=IAS, required=True)
    s.set_defaults(f=cmd_nota)

    s = sub.add_parser("tarea", help="tablero: nueva | lista | tomar | revision | hecha | reabrir")
    s.add_argument("accion", choices=["nueva", "lista", "tomar", "revision", "hecha", "reabrir"])
    s.add_argument("args", nargs="*", help="título (nueva) o número de tarea")
    s.add_argument("--ia", choices=IAS)
    s.add_argument("--para", choices=IAS, help="a quién se le sugiere la tarea")
    s.add_argument("--nota", default="")
    s.add_argument("--todas", action="store_true", help="incluir tareas hechas en la lista")
    s.set_defaults(f=cmd_tarea)

    s = sub.add_parser("respaldos", help="lista los respaldos de un archivo")
    s.add_argument("archivo")
    s.set_defaults(f=cmd_respaldos)

    s = sub.add_parser("restaurar", help="vuelve un archivo a un respaldo")
    s.add_argument("archivo")
    s.add_argument("n", type=int, nargs="?", default=1, help="número de respaldo (1 = más reciente)")
    s.add_argument("--ia", choices=IAS, required=True)
    s.set_defaults(f=cmd_restaurar)

    for nombre, f in (("hook-pre", cmd_hook_pre), ("hook-stop", cmd_hook_stop),
                      ("hook-prompt", cmd_hook_prompt)):
        sub.add_parser(nombre, help=argparse.SUPPRESS).set_defaults(f=f)

    a = p.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
