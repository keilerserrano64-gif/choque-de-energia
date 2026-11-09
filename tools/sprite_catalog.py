"""Genera los sprites (tools/sprite_gen.py) y escribe sus entradas en scripts/data/catalog.gd.

Uso (desde la carpeta del proyecto): python tools/sprite_catalog.py
Cada luchador queda con "sprites", "sprite_anchor", "sprite_frame_time",
"sprite_height" y "sprite_head", igual que Volt. Se puede volver a ejecutar:
reemplaza el bloque generado anterior.
"""
import pathlib
import re
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import sprite_gen as g  # noqa: E402

ROOT = pathlib.Path(__file__).resolve().parent.parent
CATALOG = ROOT / "scripts" / "data" / "catalog.gd"
BEGIN = "\t\t# --- sprites generados (tools/sprite_catalog.py) ---"
END = "\t\t# --- fin sprites generados ---"
# Altura final en pantalla (px de la arena) de cada luchador, calibrada junto a Volt.
TARGET = {"brasa": 86.0, "marea": 87.0, "cobalto": 90.0, "espejo": 89.0, "pedernal": 95.0, "luma": 86.0, "onix": 93.0}
POSE_KEYS = [
    "idle", "stance", "run_a", "run_b", "jump", "block", "jab", "cross", "hook", "uppercut", "kick_chamber",
    "kick_low", "kick_mid", "kick_high", "kick_spin", "sweep", "air_kick", "air_punch", "throw", "special",
    "charge", "hurt", "victory", "intro",
]


def figure_top(cv):
    for y in range(g.SIZE):
        for x in range(g.SIZE):
            if cv.px[y * g.SIZE + x] is not None:
                return y
    return 0


def touches_edge(cv):
    """Devuelve qué bordes toca la figura (arriba, izquierda, derecha): estaría recortada."""
    sides = []
    if any(cv.px[x] is not None and cv.px[x][3] > 200 for x in range(g.SIZE)):
        sides.append("arriba")
    if any(cv.px[y * g.SIZE] is not None and cv.px[y * g.SIZE][3] > 200 for y in range(g.SIZE)):
        sides.append("izquierda")
    if any(cv.px[y * g.SIZE + g.SIZE - 1] is not None and cv.px[y * g.SIZE + g.SIZE - 1][3] > 200 for y in range(g.SIZE)):
        sides.append("derecha")
    return sides


def main():
    text = CATALOG.read_text(encoding="utf-8")
    text = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n", "", text, flags=re.S)
    for fid, cfg in g.FIGHTERS.items():
        folder = g.OUT / fid
        folder.mkdir(parents=True, exist_ok=True)
        head = None
        top = 0
        clipped = []
        for name, pose in g.POSES.items():
            cv, h = g.draw_fighter(cfg, pose, name)
            g.save_png(cv, folder / ("%s_%s.png" % (fid, name)))
            if touches_edge(cv):
                clipped.append("%s(%s)" % (name, ",".join(touches_edge(cv))))
            if name == "idle":
                head = h
                top = figure_top(cv)
        for name, (pose, streaks) in g.PHASES.items():
            cv, _ = g.draw_fighter(cfg, pose, name, streaks)
            g.save_png(cv, folder / ("%s_%s.png" % (fid, name)))
            if touches_edge(cv):
                clipped.append("%s(%s)" % (name, ",".join(touches_edge(cv))))
        if clipped:
            print("  aviso %s: tocan el borde -> %s" % (fid, " ".join(clipped)))
        path = lambda key: '"res://assets/fighters/%s/%s_%s.png"' % (fid, fid, key)  # noqa: E731
        entries = ['"%s": %s' % ("run" if k == "run_a" else ("run_alt" if k == "run_b" else k), path(k)) for k in POSE_KEYS]
        entries.append('"walk": [%s]' % ", ".join(path("walk_%d" % i) for i in range(4)))
        for name in g.PHASES:
            entries.append('"%s": %s' % (name, path(name)))
        for alias, key in g.ALIASES.items():
            entries.append('"%s": %s' % (alias, path(key)))
        # Escala: la figura (de la coronilla a los pies) debe medir TARGET px en la arena.
        m = re.search(r'"id": "%s".*?"sprite_scale": ([^,]+),' % fid, text, re.S)
        sprite_scale = eval(m.group(1).replace("/", "/ "))
        figure_px = 127 - top
        units = TARGET[fid] / sprite_scale
        sprite_height = round(units * 128.0 / figure_px, 2)
        block = [BEGIN,
                 '\t\t"sprites": {\n\t\t\t' + ",\n\t\t\t".join(entries) + ",\n\t\t},",
                 '\t\t"sprite_anchor": Vector2(60, 127),',
                 '\t\t"sprite_frame_time": {"walk": 0.11},',
                 '\t\t"sprite_height": %s,' % sprite_height,
                 '\t\t"sprite_head": Vector2(%d, %d),' % (round(head[0]), round(head[1])),
                 END]
        anchor = re.search(r'("id": "%s".*?"voice_fx": [^\n]*\n)' % fid, text, re.S)
        insert_at = anchor.end()
        text = text[:insert_at] + "\n".join(block) + "\n" + text[insert_at:]
        print("%-9s figura %3d px  sprite_height %.2f" % (fid, figure_px, sprite_height))
    CATALOG.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    main()
