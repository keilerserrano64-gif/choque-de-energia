"""Generador de sprites 128x128 en pixel art para los luchadores (estilo Volt), versión 2.

Cada luchador se monta sobre un esqueleto (cadera, cuello, hombros, codos, manos,
rodillas, pies) y se dibuja por capas, de atrás hacia delante:
    capa/abrigo -> brazo trasero -> pierna trasera -> torso -> pierna delantera ->
    cinturón -> cuello, cuello alto y cabeza -> brazo delantero y hombrera.

Tipos de pieza:
  * cuerpo orgánico (traje, piel): cápsulas con sombreado cilíndrico en 5 tonos y tramado
  * armadura (peto, abdominales, guanteletes, grebas, rodilleras, hombreras, puños):
    placas poligonales con bisel (borde claro hacia la luz, oscuro al otro lado) y brillo
  * pelo: mechones afilados con degradado de la raíz a la punta
  * tela (capa, abrigo, bufanda, faldones): pliegues en bandas
  * líneas de energía que brillan con halo, como los rayos de Volt
Al final: contorno selectivo, líneas interiores entre piezas, luz de borde, estelas de
movimiento y los efectos del elemento de cada luchador.

Uso (desde la carpeta del proyecto):  python tools/sprite_catalog.py
(genera todas las imágenes y actualiza scripts/data/catalog.gd). Solo biblioteca estándar.
"""
import math
import pathlib
import struct
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "fighters"
SIZE = 128
GROUND = 126
SX, SY, RS = 1.1, 1.16, 1.16   # escala del espacio de diseño a la imagen
_L3 = (0.5, -0.55, 0.67)
_N3 = math.sqrt(sum(c * c for c in _L3))
LIGHT = tuple(c / _N3 for c in _L3)          # luz 3D para cápsulas y esferas
_L2 = (0.45, -0.89)
_N2 = math.hypot(*_L2)
LP = (_L2[0] / _N2, _L2[1] / _N2)            # luz 2D para placas y mechones
OUTLINE = (20, 18, 30, 255)
COOL = (28, 22, 60)                          # las sombras tiran hacia este tono frío
N4 = ((1, 0), (-1, 0), (0, 1), (0, -1))


# ----------------------------------------------------------------- colores
def hexc(h):
    if not isinstance(h, str):
        return tuple(h)
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def ramp(base):
    """Material orgánico: sombra profunda, sombra, base, luz y brillo."""
    b = hexc(base)
    deep = mix(mix(b, (0, 0, 0), 0.46), COOL, 0.16)
    shadow = mix(mix(b, (0, 0, 0), 0.22), COOL, 0.07)
    light = mix(b, (255, 250, 225), 0.32)
    spec = mix(b, (255, 255, 245), 0.72)
    return [deep, shadow, b, light, spec]


def metal(base):
    """Metal: más contraste entre sombra y luz y un brillo casi blanco."""
    b = hexc(base)
    deep = mix(mix(b, (0, 0, 0), 0.6), COOL, 0.2)
    shadow = mix(mix(b, (0, 0, 0), 0.3), COOL, 0.1)
    light = mix(b, (255, 252, 235), 0.4)
    spec = mix(b, (255, 255, 255), 0.86)
    return [deep, shadow, b, light, spec]


def skin_ramp(base):
    """Piel: sombras cálidas (rojizas) en vez de frías, como en el arte de Volt."""
    b = hexc(base)
    deep = mix(b, (96, 42, 52), 0.55)
    shadow = mix(b, (160, 82, 72), 0.3)
    light = mix(b, (255, 238, 214), 0.35)
    spec = mix(b, (255, 250, 240), 0.7)
    return [deep, shadow, b, light, spec]


def dim(pal, k=0.22):
    """Versión más oscura y fría (piezas del lado de atrás)."""
    if k <= 0:
        return pal
    return [mix(c, COOL, k) for c in pal]


# ----------------------------------------------------------------- vectores
def add(a, b):
    return (a[0] + b[0], a[1] + b[1])


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1])


def mul(a, k):
    return (a[0] * k, a[1] * k)


def neg(a):
    return (-a[0], -a[1])


def length(a):
    return math.hypot(a[0], a[1])


def unit(a):
    n = math.hypot(a[0], a[1]) or 1e-6
    return (a[0] / n, a[1] / n)


def perp(a):
    return (-a[1], a[0])


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def loc(c, d, n, along, across):
    """Punto en el sistema local (d = a lo largo, n = de través) con origen c."""
    return (c[0] + d[0] * along + n[0] * across, c[1] + d[1] * along + n[1] * across)


def upward(n):
    """De n y -n, el que apunta más hacia arriba."""
    return n if n[1] < 0 or (n[1] == 0 and n[0] < 0) else neg(n)


def frontward(n):
    """De n y -n, el que apunta hacia delante (+x)."""
    return n if n[0] >= 0 else neg(n)


# ----------------------------------------------------------------- lienzo
class Canvas:
    def __init__(self):
        self.px = [None] * (SIZE * SIZE)
        self.layer = [-99.0] * (SIZE * SIZE)
        self.glow = {}

    def put(self, x, y, color, layer, glow=False):
        x, y = int(x), int(y)
        if 0 <= x < SIZE and 0 <= y < SIZE:
            i = y * SIZE + x
            self.px[i] = tuple(color) if len(color) == 4 else tuple(color) + (255,)
            self.layer[i] = layer
            if glow:
                self.glow[i] = tuple(color[:3])
            else:
                self.glow.pop(i, None)

    def get(self, x, y):
        if 0 <= x < SIZE and 0 <= y < SIZE:
            return self.px[y * SIZE + x]
        return None


THRESHOLDS = (-0.05, 0.32, 0.74)
DITHER = 0.045


def tone_index(intensity, x=0, y=0, shiny=False):
    """Tono 0-3 (4 = brillo) con tramado en damero cerca de cada umbral."""
    idx = 0
    for th in THRESHOLDS:
        if intensity > th:
            idx += 1
    for k, th in enumerate(THRESHOLDS):
        if abs(intensity - th) < DITHER and (x + y) % 2 == 0:
            idx = k if intensity > th else k + 1
            break
    if shiny and intensity > 0.9:
        idx = 4
    return idx


def _inside(pts, x, y):
    inside = False
    n = len(pts)
    j = n - 1
    for i in range(n):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-9) + xi:
            inside = not inside
        j = i
    return inside


def _bbox(pts):
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    return (max(0, int(min(xs)) - 1), min(SIZE - 1, int(max(xs)) + 1),
            max(0, int(min(ys)) - 1), min(SIZE - 1, int(max(ys)) + 1))


# ----------------------------------------------------------------- primitivas
def capsule(cv, a, b, ra, rb, pal, layer, flat=False, shiny=False):
    """Cilindro redondeado (miembros, torso): sombreado cilíndrico."""
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    l2 = dx * dx + dy * dy or 1e-6
    r = max(ra, rb)
    for y in range(max(0, int(min(ay, by) - r - 1)), min(SIZE, int(max(ay, by) + r + 2))):
        for x in range(max(0, int(min(ax, bx) - r - 1)), min(SIZE, int(max(ax, bx) + r + 2))):
            px, py = x + 0.5, y + 0.5
            t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / l2))
            cx, cy = ax + dx * t, ay + dy * t
            rr = ra + (rb - ra) * t
            vx, vy = px - cx, py - cy
            d = math.sqrt(vx * vx + vy * vy)
            if d > rr:
                continue
            if flat:
                idx = 2
            else:
                k = d / rr
                nz = math.sqrt(max(0.0, 1 - k * k))
                idx = tone_index(vx / rr * LIGHT[0] + vy / rr * LIGHT[1] + nz * LIGHT[2], x, y, shiny)
            cv.put(x, y, pal[idx], layer)


def ellipse(cv, c, rx, ry, pal, layer, flat=False, shiny=False):
    cx, cy = c
    for y in range(int(cy - ry - 1), int(cy + ry + 2)):
        for x in range(int(cx - rx - 1), int(cx + rx + 2)):
            nx = (x + 0.5 - cx) / rx
            ny = (y + 0.5 - cy) / ry
            d2 = nx * nx + ny * ny
            if d2 > 1:
                continue
            if flat:
                idx = 2
            else:
                nz = math.sqrt(max(0.0, 1 - d2))
                idx = tone_index(nx * LIGHT[0] + ny * LIGHT[1] + nz * LIGHT[2], x, y, shiny)
            cv.put(x, y, pal[idx], layer)


def polygon(cv, pts, pal, layer, shade_axis=None):
    """Polígono relleno; con shade_axis=(x0, x1) se sombrea por bandas horizontales."""
    x0, x1, y0, y1 = _bbox(pts)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if not _inside(pts, x + 0.5, y + 0.5):
                continue
            idx = 2
            if shade_axis is not None:
                a0, a1 = shade_axis
                t = (x + 0.5 - a0) / max(1.0, (a1 - a0))
                t += 0.06 if (x + y) % 2 == 0 else -0.06
                idx = 0 if t < 0.15 else (1 if t < 0.45 else (2 if t < 0.85 else 3))
            cv.put(x, y, pal[idx], layer)


def plate(cv, pts, pal, layer, bevel=1.3, spec=True):
    """Placa de armadura: bisel claro en los bordes que miran a la luz, oscuro en los
    contrarios, degradado suave en el centro y un brillo en la esquina más iluminada."""
    n = len(pts)
    if n < 3:
        return
    cx = sum(p[0] for p in pts) / n
    cy = sum(p[1] for p in pts) / n
    edges = []
    for i in range(n):
        a = pts[i]
        b = pts[(i + 1) % n]
        e = sub(b, a)
        ln = length(e)
        if ln < 1e-6:
            continue
        nrm = (-e[1] / ln, e[0] / ln)
        mid = ((a[0] + b[0]) / 2 + nrm[0] * 0.7, (a[1] + b[1]) / 2 + nrm[1] * 0.7)
        if not _inside(pts, mid[0], mid[1]):
            nrm = neg(nrm)
        facing = -(nrm[0] * LP[0] + nrm[1] * LP[1])  # normal exterior · luz
        edges.append((a, nrm, facing))
    rad = max(math.hypot(p[0] - cx, p[1] - cy) for p in pts) or 1.0
    x0, x1, y0, y1 = _bbox(pts)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px, py = x + 0.5, y + 0.5
            if not _inside(pts, px, py):
                continue
            dmin = 1e9
            facing = 0.0
            for a, nrm, f in edges:
                d = (px - a[0]) * nrm[0] + (py - a[1]) * nrm[1]
                if d < dmin:
                    dmin = d
                    facing = f
            g = ((px - cx) * LP[0] + (py - cy) * LP[1]) / rad
            g += 0.07 if (x + y) % 2 == 0 else -0.07
            idx = 3 if g > 0.45 else (2 if g > -0.3 else 1)
            if dmin < bevel:
                if facing > 0.3:
                    idx = 3
                elif facing < -0.55:
                    idx = 0
                elif facing < -0.12:
                    idx = 1
            if spec and dmin < bevel + 0.6 and facing > 0.5 and g > 0.42:
                idx = 4
            cv.put(x, y, pal[idx], layer)


def strand(cv, root, tip, width, pal_root, pal_tip, layer, bend=0.0, glow=False):
    """Mechón de pelo (o llama): afilado, curvado y con degradado de raíz a punta."""
    d = sub(tip, root)
    ln = length(d) or 1e-6
    u = (d[0] / ln, d[1] / ln)
    n = perp(u)
    w = width / 2.0
    mid = add(add(root, mul(u, ln * 0.5)), mul(n, bend))
    pts = [add(root, mul(n, w)), add(mid, mul(n, w * 0.62)), tip, add(mid, mul(n, -w * 0.62)), add(root, mul(n, -w))]
    toward_light = 1.0 if (n[0] * LP[0] + n[1] * LP[1]) > 0 else -1.0
    x0, x1, y0, y1 = _bbox(pts)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px, py = x + 0.5, y + 0.5
            if not _inside(pts, px, py):
                continue
            rx, ry = px - root[0], py - root[1]
            t = max(0.0, min(1.0, (rx * u[0] + ry * u[1]) / ln))
            off = bend * 4 * t * (1 - t)
            s = ((rx * n[0] + ry * n[1]) - off) / max(0.6, w * (1 - 0.75 * t))
            side = s * toward_light
            idx = 1 if t < 0.22 else (2 if t < 0.7 else 3)
            if side > 0.4:
                idx = min(3, idx + 1)
            elif side < -0.45:
                idx = max(0, idx - 1)
            pal = pal_root if t < 0.55 else pal_tip
            cv.put(x, y, pal[idx], layer, glow=glow)


def cloth(cv, pts, pal, layer, fold=(1.0, 0.2), spacing=6.0, phase=0.0):
    """Tela con pliegues: bandas alternas de luz y sombra."""
    fl = math.hypot(*fold) or 1.0
    fx, fy = fold[0] / fl, fold[1] / fl
    x0, x1, y0, y1 = _bbox(pts)
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if not _inside(pts, x + 0.5, y + 0.5):
                continue
            s = math.sin(((x * fx + y * fy) / spacing + phase) * math.tau)
            s += 0.08 if (x + y) % 2 == 0 else -0.08
            idx = 3 if s > 0.8 else (2 if s > -0.45 else (1 if s > -0.9 else 0))
            cv.put(x, y, pal[idx], layer)


def ribbon(cv, start, ang_deg, ln, width, waves, amp, pal, layer, phase=0.0):
    """Cinta que ondea (colas de bufanda, fajín)."""
    a = math.radians(ang_deg)
    u = (math.cos(a), math.sin(a))
    n = perp(u)
    left, right = [], []
    steps = 12
    for i in range(steps + 1):
        t = i / steps
        off = math.sin(t * waves * math.tau + phase) * amp * t
        c = add(add(start, mul(u, ln * t)), mul(n, off))
        w = width * (1 - 0.35 * t) / 2
        left.append(add(c, mul(n, w)))
        right.append(sub(c, mul(n, w)))
    pts = left + right[::-1]
    cloth(cv, pts, pal, layer, fold=u, spacing=7.0, phase=phase)


def line(cv, a, b, color, layer, width=1, glow=False):
    color = hexc(color)
    steps = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) + 1
    for i in range(steps + 1):
        t = i / max(1, steps)
        x = int(round(a[0] + (b[0] - a[0]) * t))
        y = int(round(a[1] + (b[1] - a[1]) * t))
        for w in range(width):
            cv.put(x, y + w, color, layer, glow=glow)


def ellipse_pts(c, d, n, ra, rb, steps=16, start=0.0):
    pts = []
    for i in range(steps):
        th = start + i / steps * math.tau
        pts.append(loc(c, d, n, math.cos(th) * ra, math.sin(th) * rb))
    return pts


def hexagon(c, r, rot=0.0):
    return [(c[0] + math.cos(rot + i * math.pi / 3) * r, c[1] + math.sin(rot + i * math.pi / 3) * r) for i in range(6)]


def blend(cv, x, y, color, alpha):
    x, y = int(x), int(y)
    if not (0 <= x < SIZE and 0 <= y < SIZE):
        return
    i = y * SIZE + x
    old = cv.px[i]
    if old is None:
        cv.px[i] = tuple(color) + (int(alpha * 255),)
    else:
        cv.px[i] = mix(old[:3], color, alpha) + (max(old[3], int(alpha * 255)),)


def finish(cv, back_rim=None):
    """Contorno selectivo, líneas interiores, luces de borde y halo de la energía."""
    src = cv.px
    out = list(src)
    for y in range(SIZE):
        for x in range(SIZE):
            i = y * SIZE + x
            c = src[i]
            if c is None:
                for dx, dy in N4:
                    xx, yy = x + dx, y + dy
                    if 0 <= xx < SIZE and 0 <= yy < SIZE:
                        nb = src[yy * SIZE + xx]
                        if nb is not None and nb[3] == 255:
                            # Contorno oscuro pero con el tono de la pieza vecina.
                            out[i] = mix(nb[:3], OUTLINE[:3], 0.74) + (255,)
                            break
                continue
            my = cv.layer[i]
            for dx, dy in N4:
                xx, yy = x + dx, y + dy
                if 0 <= xx < SIZE and 0 <= yy < SIZE:
                    j = yy * SIZE + xx
                    if src[j] is not None and cv.layer[j] >= my + 1 and j not in cv.glow:
                        out[i] = mix(c[:3], OUTLINE[:3], 0.6) + (255,)
                        break
    # Luz de borde: el píxel opaco junto al vacío por delante (derecha) se aclara.
    rim = list(out)
    for y in range(SIZE):
        for x in range(SIZE):
            i = y * SIZE + x
            if src[i] is None or i in cv.glow:
                continue
            right = src[i + 1] if x + 1 < SIZE else None
            left = src[i - 1] if x > 0 else None
            above = src[i - SIZE] if y > 0 else None
            c = out[i][:3]
            if right is None:
                c = mix(c, (255, 248, 230), 0.34)
            elif left is None and back_rim is not None:
                c = mix(c, back_rim, 0.42)
            if above is None:
                c = mix(c, (255, 250, 240), 0.16)
            rim[i] = c + (255,)
    cv.px = rim
    # Halo de las líneas de energía (también fuera de la silueta, semitransparente).
    for i, col in list(cv.glow.items()):
        x, y = i % SIZE, i // SIZE
        for dy in (-2, -1, 0, 1, 2):
            for dx in (-2, -1, 0, 1, 2):
                if dx == 0 and dy == 0:
                    continue
                j = (y + dy) * SIZE + (x + dx)
                if j in cv.glow or not (0 <= x + dx < SIZE and 0 <= y + dy < SIZE):
                    continue
                blend(cv, x + dx, y + dy, col, 0.3 if max(abs(dx), abs(dy)) == 1 else 0.11)
    for i, col in cv.glow.items():
        cv.px[i] = mix(col, (255, 255, 255), 0.22) + (255,)


def save_png(cv, path):
    raw = bytearray()
    for y in range(SIZE):
        raw.append(0)
        for x in range(SIZE):
            c = cv.px[y * SIZE + x]
            raw.extend(c if c is not None else (0, 0, 0, 0))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9)) + chunk(b"IEND", b"")
    path.write_bytes(png)


# ----------------------------------------------------------------- poses
# Espacio de diseño: mirando a la derecha, suelo en y=126. Claves:
# hip, neck, head (opcional), el_f/ha_f (brazo delantero), el_b/ha_b (trasero),
# kn_f/ft_f (pierna delantera), kn_b/ft_b (trasera), back_arm_front (brazo trasero delante).
BASE_LEGS = {"kn_f": (73, 104), "ft_f": (80, 125), "kn_b": (48, 105), "ft_b": (42, 125)}
STANCE_LEGS = {"kn_f": (76, 105), "ft_f": (84, 125), "kn_b": (46, 106), "ft_b": (38, 125)}
SUPPORT = {"kn_b": (54, 104), "ft_b": (50, 125)}


def P(**kw):
    return kw


POSES = {
    "idle": P(hip=(60, 85), neck=(62, 50), el_f=(77, 66), ha_f=(85, 55), el_b=(50, 68), ha_b=(61, 61), **BASE_LEGS),
    "stance": P(hip=(60, 87), neck=(64, 52), el_f=(81, 67), ha_f=(90, 54), el_b=(53, 69), ha_b=(66, 59), **STANCE_LEGS),
    "walk_0": P(hip=(60, 85), neck=(63, 50), el_f=(76, 66), ha_f=(85, 56), el_b=(52, 68), ha_b=(62, 61),
                kn_f=(72, 104), ft_f=(82, 125), kn_b=(50, 104), ft_b=(40, 125)),
    "walk_1": P(hip=(60, 83), neck=(63, 48), el_f=(75, 64), ha_f=(84, 54), el_b=(53, 66), ha_b=(63, 59),
                kn_f=(66, 103), ft_f=(64, 125), kn_b=(60, 101), ft_b=(54, 117)),
    "walk_2": P(hip=(60, 85), neck=(63, 50), el_f=(77, 66), ha_f=(86, 55), el_b=(51, 68), ha_b=(61, 61),
                kn_f=(52, 104), ft_f=(42, 125), kn_b=(70, 104), ft_b=(80, 125)),
    "walk_3": P(hip=(60, 83), neck=(63, 48), el_f=(76, 64), ha_f=(85, 54), el_b=(52, 66), ha_b=(62, 59),
                kn_f=(64, 101), ft_f=(58, 117), kn_b=(58, 103), ft_b=(60, 125)),
    "run_a": P(hip=(62, 83), neck=(72, 50), el_f=(64, 68), ha_f=(70, 78), el_b=(82, 62), ha_b=(92, 52),
               kn_f=(82, 96), ft_f=(78, 114), kn_b=(50, 104), ft_b=(34, 116), back_arm_front=True),
    "run_b": P(hip=(62, 83), neck=(72, 50), el_f=(86, 62), ha_f=(94, 52), el_b=(62, 68), ha_b=(56, 78),
               kn_f=(66, 106), ft_f=(56, 122), kn_b=(76, 96), ft_b=(70, 112)),
    "jump": P(drop=10, hip=(60, 74), neck=(62, 40), el_f=(76, 52), ha_f=(84, 42), el_b=(50, 56), ha_b=(60, 48),
              kn_f=(78, 84), ft_f=(72, 101), kn_b=(56, 90), ft_b=(46, 102)),
    "block": P(hip=(58, 87), neck=(58, 52), head=(61, 41), el_f=(76, 63), ha_f=(72, 40), el_b=(72, 68), ha_b=(80, 46),
               back_arm_front=True, **STANCE_LEGS),
    "jab": P(hip=(60, 86), neck=(66, 51), el_f=(88, 52), ha_f=(105, 50), el_b=(56, 67), ha_b=(68, 57), **STANCE_LEGS),
    "cross": P(hip=(63, 86), neck=(71, 51), el_f=(72, 66), ha_f=(80, 60), el_b=(89, 54), ha_b=(110, 52),
               back_arm_front=True, kn_f=(80, 105), ft_f=(88, 125), kn_b=(50, 106), ft_b=(40, 125)),
    "hook": P(hip=(61, 86), neck=(68, 51), el_f=(91, 58), ha_f=(101, 46), el_b=(56, 67), ha_b=(67, 58), **STANCE_LEGS),
    "uppercut": P(hip=(62, 84), neck=(67, 48), head=(70, 37), el_f=(84, 54), ha_f=(88, 31), el_b=(55, 64), ha_b=(64, 58),
                  kn_f=(78, 103), ft_f=(84, 125), kn_b=(50, 104), ft_b=(42, 125)),
    "kick_chamber": P(hip=(58, 83), neck=(54, 49), head=(56, 38), el_f=(70, 62), ha_f=(78, 52), el_b=(46, 64), ha_b=(54, 56),
                      kn_f=(78, 84), ft_f=(80, 102), **SUPPORT),
    "kick_low": P(hip=(56, 85), neck=(50, 50), head=(52, 39), el_f=(66, 62), ha_f=(74, 54), el_b=(42, 64), ha_b=(50, 58),
                  kn_f=(78, 101), ft_f=(101, 118), **SUPPORT),
    "kick_mid": P(hip=(56, 83), neck=(46, 50), head=(47, 39), el_f=(60, 62), ha_f=(68, 54), el_b=(38, 64), ha_b=(46, 58),
                  kn_f=(80, 84), ft_f=(105, 82), **SUPPORT),
    "kick_high": P(hip=(56, 81), neck=(42, 50), head=(42, 39), el_f=(56, 62), ha_f=(64, 54), el_b=(34, 64), ha_b=(40, 58),
                   kn_f=(77, 70), ft_f=(100, 50), **SUPPORT),
    "kick_spin": P(hip=(58, 81), neck=(44, 53), head=(43, 42), el_f=(52, 68), ha_f=(44, 76), el_b=(36, 62), ha_b=(28, 70),
                   kn_f=(80, 72), ft_f=(104, 62), **SUPPORT),
    "sweep": P(hip=(52, 108), neck=(54, 78), head=(58, 67), el_f=(66, 92), ha_f=(70, 104), el_b=(44, 96), ha_b=(40, 118),
               kn_f=(76, 117), ft_f=(105, 123), kn_b=(40, 110), ft_b=(46, 125)),
    "air_kick": P(drop=10, hip=(58, 72), neck=(54, 41), head=(56, 30), el_f=(68, 54), ha_f=(76, 46), el_b=(44, 56), ha_b=(50, 48),
                  kn_f=(78, 85), ft_f=(99, 101), kn_b=(56, 90), ft_b=(46, 98)),
    "air_punch": P(drop=10, hip=(58, 74), neck=(64, 41), head=(68, 31), el_f=(83, 54), ha_f=(99, 64), el_b=(52, 56), ha_b=(62, 48),
                   kn_f=(74, 86), ft_f=(68, 101), kn_b=(54, 90), ft_b=(44, 101)),
    "throw": P(hip=(62, 86), neck=(69, 51), el_f=(86, 59), ha_f=(99, 53), el_b=(80, 63), ha_b=(95, 60),
               back_arm_front=True, **STANCE_LEGS),
    "special": P(hip=(60, 86), neck=(65, 51), el_f=(86, 49), ha_f=(103, 43), el_b=(54, 64), ha_b=(65, 72), **STANCE_LEGS),
    "charge": P(hip=(58, 89), neck=(58, 55), head=(61, 44), el_f=(66, 72), ha_f=(56, 79), el_b=(48, 70), ha_b=(44, 80),
                kn_f=(76, 107), ft_f=(84, 125), kn_b=(44, 107), ft_b=(36, 125)),
    "hurt": P(hip=(56, 86), neck=(48, 53), head=(44, 43), el_f=(62, 64), ha_f=(72, 74), el_b=(42, 62), ha_b=(34, 68),
              kn_f=(70, 105), ft_f=(78, 125), kn_b=(46, 105), ft_b=(38, 125)),
    "victory": P(hip=(60, 85), neck=(62, 50), el_f=(73, 42), ha_f=(76, 27), el_b=(48, 70), ha_b=(55, 82), **BASE_LEGS),
    "intro": P(hip=(60, 86), neck=(62, 51), el_f=(76, 64), ha_f=(70, 56), el_b=(56, 66), ha_b=(68, 62),
               back_arm_front=True, **BASE_LEGS),
}

UPPER = ("hip", "neck", "head", "el_f", "ha_f", "el_b", "ha_b")


def tf(p, key=""):
    x, y = p
    # Piernas algo más cortas y torso más largo: proporción heroica como Volt.
    if key in UPPER:
        y += 3.5
    elif key in ("kn_f", "kn_b"):
        y += 1.5
    return (60 + (x - 60) * SX, GROUND - (GROUND - y) * SY)


# ----------------------------------------------------------------- luchadores
# Colores con mucho contraste (como Volt): traje interior oscuro, armadura de color,
# metal secundario (trim) y energía que brilla (glow).
FIGHTERS = {
    "brasa": dict(element="fire", face="fierce_f", female=True, bulk=0.95,
                  skin="#f4c39c", hair="#ffae3a", hair2="#e8402a", hair_style="flame", iris="#ff9a3a",
                  under="#5a2430", legs="#4e2029", armor="#d4452c", trim="#ffc34d", glow="#ffd36e",
                  gloves="trim", boots="#5c1f24", pauldron="dome", thigh_plate=False, elbow=False,
                  cloth="scarf", cloth_color="#ff8a2a", cloth_in="#ffd36e", flap=None, bare_arms=False),
    "marea": dict(element="water", face="calm_f", female=True, bulk=0.92,
                  skin="#e9bf98", hair="#1f4c58", hair2="#2f7a86", hair_style="hood", iris="#7ff5e6",
                  under="#16404c", legs="#123842", armor="#2b8c9c", trim="#d9fff4", glow="#7ff5e6",
                  gloves="armor", boots="#163f4a", pauldron="shell", thigh_plate=False, elbow=False,
                  cloth="cape", cloth_color="#1b5c6c", cloth_in="#8cebd9", flap=None, bare_arms=False),
    "cobalto": dict(element="prism", face="stern", female=False, bulk=1.02,
                    skin="#e8b994", hair="#2b2048", hair2="#5a4a8a", hair_style="short", iris="#e2c4ff",
                    under="#2a2048", legs="#2e2450", armor="#6b4fc4", trim="#e9dcff", glow="#e2c4ff",
                    gloves="armor", boots="#2b2142", pauldron="angular", thigh_plate=True, elbow=True,
                    cloth="coat", cloth_color="#2c1f52", cloth_in="#9d7be8", flap=None, bare_arms=False),
    "espejo": dict(element="mirror", face="smirk", female=False, bulk=0.94,
                   skin="#f0c8a8", hair="#4e1c3e", hair2="#8a3470", hair_style="long", iris="#ffc4ea",
                   under="#401a38", legs="#4a1e42", armor="#c4508e", trim="#fff0fa", glow="#ffc4ea",
                   gloves="trim", boots="#3e1636", pauldron=None, thigh_plate=False, elbow=False,
                   cloth="scarf", cloth_color="#ff9fd2", cloth_in="#fff0fa", flap=None, bare_arms=False),
    "pedernal": dict(element="rock", face="scar", female=False, bulk=1.28,
                     skin="#d9a074", hair="#4a3222", hair2="#6e4c32", hair_style="rough", iris="#8a5a3a",
                     under="#5e3e28", legs="#4c3220", armor="#9a8c7a", trim="#d4ae74", glow="#ffb35a",
                     gloves="armor", boots="#3a2a22", pauldron="rock", thigh_plate=False, elbow=False,
                     cloth=None, cloth_color=None, cloth_in=None, flap="#6e4a2c", bare_arms=True),
    "luma": dict(element="light", face="soft_f", female=True, bulk=0.9,
                 skin="#f2c9a2", hair="#234f3a", hair2="#3f8a60", hair_style="ponytail", iris="#d8ffb0",
                 under="#1c4a33", legs="#1f5238", armor="#4fae7c", trim="#f6f0d0", glow="#d8ffb0",
                 gloves="trim", boots="#1d4a33", pauldron="leaf", thigh_plate=False, elbow=False,
                 cloth="sash", cloth_color="#c4ffad", cloth_in="#f0ffe0", flap="#c4ffad", bare_arms=False),
    "onix": dict(element="ember", face="glow", female=False, bulk=1.18,
                 skin="#d8a885", hair="#ff7a3a", hair2="#ffd06a", hair_cap="#2a2228", hair_style="crown", iris="#ffb35a",
                 under="#262a34", legs="#2a2e3a", armor="#5c6678", trim="#9aa3b6", glow="#ff8a3d",
                 gloves="armor", boots="#22252e", pauldron="spike", thigh_plate=True, elbow=True,
                 cloth="half_cape", cloth_color="#1d1f27", cloth_in="#ff7a3a", flap=None, bare_arms=False),
}


def palettes(cfg):
    p = {
        "skin": skin_ramp(cfg["skin"]), "under": ramp(cfg["under"]), "legs": ramp(cfg["legs"]),
        "armor": metal(cfg["armor"]), "armor2": metal(mix(hexc(cfg["armor"]), COOL, 0.2)),
        "trim": metal(cfg["trim"]), "boots": metal(cfg["boots"]),
        "hair": ramp(cfg["hair"]), "hair2": ramp(cfg["hair2"]), "hair_cap": ramp(cfg.get("hair_cap", cfg["hair"])),
    }
    p["glove"] = p["trim"] if cfg["gloves"] == "trim" else p["armor"]
    if cfg.get("cloth_color"):
        p["cloth"] = ramp(cfg["cloth_color"])
        p["cloth_in"] = ramp(cfg["cloth_in"])
    if cfg.get("flap"):
        p["flap"] = ramp(cfg["flap"])
    return p


# ----------------------------------------------------------------- piezas del cuerpo
def draw_fist(cv, el, ha, pal, layer, bulk):
    """Puño cerrado: placa con dedos doblados, nudillos claros y pulgar encima."""
    R = RS
    d = unit(sub(ha, el))
    n = perp(d)
    c = add(ha, mul(d, 0.8 * R))
    hl, hw, ch = 4.9 * R * bulk, 4.6 * R * bulk, 1.7 * R
    pts = [loc(c, d, n, hl, hw - ch), loc(c, d, n, hl - ch, hw), loc(c, d, n, -(hl - ch), hw), loc(c, d, n, -hl, hw - ch),
           loc(c, d, n, -hl, -(hw - ch)), loc(c, d, n, -(hl - ch), -hw), loc(c, d, n, hl - ch, -hw), loc(c, d, n, hl, -(hw - ch))]
    plate(cv, pts, pal, layer, bevel=1.2)
    for k in (-0.34, 0.34):
        line(cv, loc(c, d, n, hl * 0.32, hw * k), loc(c, d, n, hl * 0.95, hw * k), pal[0], layer + 0.3)
    line(cv, loc(c, d, n, hl * 0.78, hw * 0.72), loc(c, d, n, hl * 0.78, -hw * 0.72), pal[3], layer + 0.3)
    top = upward(n)
    ellipse(cv, add(sub(c, mul(d, hl * 0.1)), mul(top, hw * 0.8)), 2.4 * R * bulk, 2.4 * R * bulk, pal, layer + 1)


def draw_arm(cv, F, sh, el, ha, L, back):
    P = F["pal"]
    bulk = F["bulk"]
    R = RS
    k = 0.22 if back else 0.0
    flesh = dim(P["skin"] if F["bare_arms"] else P["under"], k)
    capsule(cv, sh, el, 6.3 * R * bulk, 4.9 * R * bulk, flesh, L)
    ellipse(cv, lerp(sh, el, 0.42), 5.5 * R * bulk, 5.5 * R * bulk, flesh, L)      # bíceps
    capsule(cv, el, ha, 5.1 * R * bulk, 4.3 * R * bulk, flesh, L + 1)               # antebrazo
    d = unit(sub(ha, el))
    n = perp(d)
    s = lerp(el, ha, 0.3)
    e = sub(ha, mul(d, 2.2 * R))
    ws, we = 5.5 * R * bulk, 5.9 * R * bulk
    gp = dim(P["armor"], k)
    plate(cv, [add(s, mul(n, ws)), add(e, mul(n, we)), sub(e, mul(n, we)), sub(s, mul(n, ws))], gp, L + 2)
    line(cv, add(s, mul(n, ws * 0.9)), sub(s, mul(n, ws * 0.9)), gp[0], L + 2.2)       # aro del guantelete
    if F["glow"] and not back:
        top = upward(n)
        line(cv, add(lerp(s, e, 0.15), mul(top, ws * 0.45)), add(lerp(s, e, 0.88), mul(top, we * 0.45)),
             F["glow"], L + 2.5, glow=True)
    if F["elbow"]:
        plate(cv, hexagon(el, 3.8 * R * bulk, 0.3), dim(P["armor2"], k), L + 2)
    draw_fist(cv, el, ha, dim(P["glove"], k), L + 3, bulk)


def draw_leg(cv, F, hp, kn, ft, L, back):
    P = F["pal"]
    bulk = F["bulk"]
    R = RS
    k = 0.22 if back else 0.0
    under = dim(P["legs"], k)
    capsule(cv, hp, kn, 7.6 * R * bulk, 5.6 * R * bulk, under, L)
    capsule(cv, kn, ft, 5.6 * R * bulk, 4.4 * R * bulk, under, L + 1)
    td = unit(sub(kn, hp))
    tn = frontward(perp(td))
    if F["thigh_plate"]:
        s, e = lerp(hp, kn, 0.2), lerp(hp, kn, 0.72)
        w0, w1 = 7.4 * R * bulk, 5.8 * R * bulk
        plate(cv, [add(s, mul(tn, w0)), add(e, mul(tn, w1)), sub(e, mul(tn, w1 * 0.3)), sub(s, mul(tn, w0 * 0.35))],
              dim(P["armor2"], k), L + 0.5)
    # greba (espinillera)
    d = unit(sub(ft, kn))
    n = perp(d)
    s, e = lerp(kn, ft, 0.1), lerp(kn, ft, 0.6)
    gp = dim(P["armor"], k)
    plate(cv, [add(s, mul(n, 6.0 * R * bulk)), add(e, mul(n, 5.3 * R * bulk)),
               sub(e, mul(n, 5.3 * R * bulk)), sub(s, mul(n, 6.0 * R * bulk))], gp, L + 2)
    if F["glow"] and not back:
        fs = frontward(n)
        line(cv, add(lerp(s, e, 0.18), mul(fs, 3.0 * R * bulk)), add(lerp(s, e, 0.85), mul(fs, 2.6 * R * bulk)),
             F["glow"], L + 2.5, glow=True)
    # bota con caña, pie, puntera de metal y borde
    bp = dim(P["boots"], k)
    low = lerp(kn, ft, 0.56)
    capsule(cv, low, ft, 5.9 * R * bulk, 5.2 * R * bulk, bp, L + 3)
    fwd = (d[1], -d[0])
    if fwd[0] < 0:
        fwd = neg(fwd)
    toe = add(ft, mul(fwd, 6.5 * R))
    capsule(cv, ft, toe, 5.2 * R * bulk, 4.0 * R * bulk, bp, L + 3)
    ellipse(cv, add(ft, mul(fwd, 4.6 * R)), 3.5 * R * bulk, 3.1 * R * bulk, dim(P["trim"], k), L + 4, shiny=True)
    cw = 6.4 * R * bulk
    plate(cv, [add(sub(low, mul(d, 1.0)), mul(n, cw)), add(add(low, mul(d, 2.4)), mul(n, cw)),
               sub(add(low, mul(d, 2.4)), mul(n, cw)), sub(sub(low, mul(d, 1.0)), mul(n, cw))], dim(P["trim"], k), L + 4)
    # rodillera
    plate(cv, hexagon(add(kn, mul(tn, 1.8 * R * bulk)), 4.4 * R * bulk, 0.2), dim(P["armor"], k), L + 4)


def draw_pauldron(cv, F, sh, el, L, back):
    style = F["pauldron"]
    if not style:
        return
    P = F["pal"]
    R = RS
    bulk = F["bulk"]
    k = 0.22 if back else 0.0
    pal = dim(P["armor"], k)
    pal2 = dim(P["armor2"], k)
    a = unit(sub(el, sh))
    n = perp(a)
    c = sub(sh, mul(a, 1.0 * R))
    glow = F["glow"] if not back else None
    if style in ("dome", "spike"):
        plate(cv, ellipse_pts(add(c, mul(a, 4.2 * R)), a, n, 3.6 * R * bulk, 6.4 * R * bulk), pal2, L)
        plate(cv, ellipse_pts(c, a, n, 5.4 * R * bulk, 7.4 * R * bulk), pal, L + 1)
        edge_a, edge_b = loc(c, a, n, 4.3 * R * bulk, 5.6 * R * bulk), loc(c, a, n, 4.3 * R * bulk, -5.6 * R * bulk)
        if glow:
            line(cv, edge_a, edge_b, glow, L + 1.5, glow=True)
        else:
            line(cv, edge_a, edge_b, dim(P["trim"], k)[2], L + 1.5)
        for s in (-0.5, 0.5):
            cv.put(*loc(c, a, n, 1.5 * R, s * 6.0 * R * bulk), pal[4], L + 1.6)
        if style == "spike":
            back_up = unit(add(neg(a), (-0.5, -0.45)))
            for s, ln in ((-0.5, 7.0), (0.1, 9.5), (0.62, 6.0)):
                base = loc(c, a, n, -2.4 * R, s * 6.5 * R * bulk)
                tip = add(base, mul(back_up, ln * R))
                w = perp(back_up)
                plate(cv, [add(base, mul(w, 2.4 * R)), tip, sub(base, mul(w, 2.4 * R))], pal, L + 2, bevel=1.0)
    elif style == "angular":
        pts = [(-4.5, -5.5), (-1.5, -8.0), (5.0, -7.6), (6.6, 0.0), (5.0, 7.6), (-1.5, 8.0), (-4.5, 5.5)]
        plate(cv, [loc(add(c, mul(a, 4.6 * R)), a, n, x * 0.6 * R * bulk, y * 0.8 * R * bulk) for x, y in pts], pal2, L)
        plate(cv, [loc(c, a, n, x * R * bulk, y * R * bulk) for x, y in pts], pal, L + 1)
        line(cv, loc(c, a, n, 5.2 * R * bulk, 6.2 * R * bulk), loc(c, a, n, 5.2 * R * bulk, -6.2 * R * bulk),
             glow or dim(P["trim"], k)[2], L + 1.5, glow=bool(glow))
    elif style == "shell":
        for i, (off, rb) in enumerate(((7.4, 5.0), (3.8, 6.2), (0.0, 7.3))):
            plate(cv, ellipse_pts(add(c, mul(a, off * R)), a, n, 3.6 * R * bulk, rb * R * bulk), pal if i == 2 else pal2, L + i)
        cv.put(*loc(c, a, n, -1.0 * R, 1.5 * R), dim(P["trim"], k)[4], L + 2.5)
        if glow:
            line(cv, loc(c, a, n, 3.2 * R, 5.2 * R * bulk), loc(c, a, n, 3.2 * R, -5.2 * R * bulk), glow, L + 2.5, glow=True)
    elif style == "leaf":
        for i, (off, rot) in enumerate(((3.6, 0.35), (0.0, 0.0))):
            cc = add(c, mul(a, off * R))
            pts = ellipse_pts(cc, a, n, 3.4 * R * bulk, 7.2 * R * bulk, 14, rot)
            plate(cv, pts, pal2 if i == 0 else pal, L + i)
            line(cv, loc(cc, a, n, 0, 6.2 * R * bulk), loc(cc, a, n, 0, -6.2 * R * bulk), dim(P["trim"], k)[3], L + i + 0.3)
    elif style == "rock":
        stone = dim(P["armor"], k)
        jag = (1.0, 0.82, 1.12, 0.9, 1.06, 0.8, 1.14, 0.92, 0.98)
        for i, (off, sc) in enumerate(((5.0, 0.7), (0.0, 1.0))):
            cc = add(c, mul(a, off * R))
            pts = []
            for m, f in enumerate(jag):
                th = m / len(jag) * math.tau
                pts.append(loc(cc, a, n, math.cos(th) * 6.4 * R * bulk * sc * f, math.sin(th) * 8.2 * R * bulk * sc * f))
            plate(cv, pts, stone if i else dim(P["armor2"], k), L + i, bevel=1.5)
        if glow:
            line(cv, loc(c, a, n, -1.5 * R, -1.0 * R), loc(c, a, n, 2.5 * R, 3.0 * R), glow, L + 1.5, glow=True)
            line(cv, loc(c, a, n, 2.5 * R, 3.0 * R), loc(c, a, n, 1.5 * R, 6.0 * R), glow, L + 1.5, glow=True)


def draw_torso(cv, F, T, cw, ww, hip_b, hip_f):
    P = F["pal"]
    R = RS
    bulk = F["bulk"]
    female = F["female"]
    capsule(cv, T(0.04, 0), T(0.82, 0.06 * cw), ww, cw, P["under"], 30)
    pel = (8.6 if female else 8.0) * R * bulk
    capsule(cv, hip_b, hip_f, pel, pel, P["legs"], 30)
    if female:
        chest = [T(0.52, -0.6 * cw), T(0.5, 0.52 * cw), T(0.58, 0.9 * cw), T(0.68, 1.02 * cw), T(0.8, 0.96 * cw),
                 T(0.9, 0.75 * cw), T(1.0, 0.5 * cw), T(1.0, -0.3 * cw), T(0.82, -0.78 * cw)]
        belly = [[T(0.14, -0.35 * cw), T(0.13, 0.55 * cw), T(0.46, 0.66 * cw), T(0.47, -0.42 * cw)]]
    else:
        chest = [T(0.5, -0.62 * cw), T(0.48, 0.5 * cw), T(0.6, 0.96 * cw), T(0.84, 1.0 * cw), T(1.0, 0.6 * cw),
                 T(1.02, -0.3 * cw), T(0.84, -0.8 * cw)]
        belly = [[T(0.3, -0.4 * cw), T(0.29, 0.62 * cw), T(0.46, 0.72 * cw), T(0.47, -0.45 * cw)],
                 [T(0.13, -0.35 * cw), T(0.12, 0.55 * cw), T(0.28, 0.62 * cw), T(0.28, -0.38 * cw)]]
    plate(cv, chest, P["armor"], 31)
    for pl in belly:
        plate(cv, pl, P["armor2"], 31.4)
    if F["glow"]:
        g = F["glow"]
        c = T(0.74, 0.62 * cw)
        for dx, dy in ((0, -2), (-1, -1), (0, -1), (1, -1), (-2, 0), (-1, 0), (0, 0), (1, 0), (2, 0), (-1, 1), (0, 1), (1, 1), (0, 2)):
            cv.put(c[0] + dx, c[1] + dy, g, 31.8, glow=True)
        line(cv, T(0.53, -0.25 * cw), T(0.51, 0.42 * cw), g, 31.6, glow=True)


def draw_belt(cv, F, T, ww):
    P = F["pal"]
    R = RS
    plate(cv, [T(0.0, -1.0 * ww), T(0.0, 1.08 * ww), T(0.11, 1.06 * ww), T(0.11, -0.98 * ww)], metal(mix(P["trim"][2], COOL, 0.35)), 45)
    buckle = [T(-0.01, 0.45 * ww), T(-0.01, 1.12 * ww), T(0.125, 1.12 * ww), T(0.125, 0.45 * ww)]
    plate(cv, buckle, P["trim"], 46)
    if F["glow"]:
        bc = T(0.055, 0.8 * ww)
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            cv.put(bc[0] + dx - 0.5, bc[1] + dy - 0.5, F["glow"], 46.5, glow=True)
    if F.get("flap"):
        cloth(cv, [T(0.0, 0.05 * ww), T(0.0, 1.0 * ww), T(-0.46, 1.18 * ww), T(-0.48, 0.12 * ww)], P["flap"], 46.6,
              fold=(1.0, 0.1), spacing=7.0)
    if F["cloth"] == "sash":
        ribbon(cv, T(0.03, 0.9 * ww), 100, 22 * R, 5.0 * R, 0.8, 2.5 * R, P["cloth"], 46.8)


def draw_cloth_back(cv, F, T, cw, ww):
    kind = F["cloth"]
    P = F["pal"]
    R = RS
    if kind == "cape":
        A, B = T(1.0, -0.2 * cw), T(0.92, 0.35 * cw)
        bb, bf = add(A, (-23 * R, 42 * R)), add(A, (2 * R, 49 * R))
        pts = [B, A, bb]
        for i in range(1, 10):
            p = lerp(bb, bf, i / 10)
            pts.append((p[0], p[1] + (2.6 * R if i % 2 else 0)))
        pts.append(bf)
        cloth(cv, pts, P["cloth"], 0, fold=(1.0, 0.22), spacing=5.5)
        line(cv, add(A, (-1, 2)), add(bb, (1.5, -1)), P["cloth_in"][2], 0.5)
        line(cv, add(A, (-2, 4)), add(bb, (0.5, -2.5)), P["cloth_in"][1], 0.5)
    elif kind == "coat":
        for i, sh in enumerate((0.0, 1.0)):
            W = T(0.12, (-0.9 + 0.5 * sh) * ww)
            pts = [T(0.32, (-0.95 + 0.4 * sh) * cw), W, add(W, ((-15 + 8 * sh) * R, 30 * R)),
                   add(W, ((-5 + 8 * sh) * R, 36 * R)), add(W, (4 * R, 24 * R))]
            cloth(cv, pts, dim(P["cloth"], 0.12 * (1 - sh)), 0.2 * i, fold=(1.0, 0.3), spacing=5.0)
            line(cv, add(W, ((-14 + 8 * sh) * R, 29 * R)), add(W, ((-5 + 8 * sh) * R, 35 * R)), P["cloth_in"][2], 0.3 + 0.2 * i)
    elif kind == "half_cape":
        A, B = T(1.0, -0.6 * cw), T(0.95, 0.1 * cw)
        base_y = A[1] + 40 * R
        xl, xr = A[0] - 19 * R, A[0] + 6 * R
        pts = [B, A, (xl, A[1] + 10 * R)]
        tips = []
        for i in range(8):
            t = i / 7
            x = xl + (xr - xl) * t
            y = base_y + (7 * R if i % 2 == 0 else 0) - t * 4 * R
            pts.append((x, y))
            if i % 2 == 0:
                tips.append((x, y))
        cloth(cv, pts, P["cloth"], 0, fold=(1.0, 0.15), spacing=6.0)
        for x, y in tips:
            line(cv, (x, y - 4 * R), (x, y - 1), P["cloth_in"][2], 0.5, glow=True)
    elif kind == "scarf":
        start = T(1.0, -0.3 * cw)
        ribbon(cv, start, 192, 28 * R, 6.5 * R, 1.3, 4 * R, P["cloth"], 0.2)
        ribbon(cv, add(start, (0, 2)), 172, 22 * R, 5 * R, 1.1, 3.5 * R, dim(P["cloth"], 0.15), 0.1, phase=1.7)
    if F.get("flap"):
        cloth(cv, [T(0.0, -0.2 * ww), T(0.0, -1.05 * ww), T(-0.4, -1.22 * ww), T(-0.42, -0.3 * ww)], dim(P["flap"], 0.22), 1.5,
              fold=(1.0, 0.1), spacing=7.0)


# ----------------------------------------------------------------- cabeza y pelo
# Mechones: (raíz x, raíz y, ángulo en grados, largo, ancho, curva), en radios de cabeza.
# Ángulos con y hacia abajo: 0 = delante, 90 = abajo, 180 = atrás, 270 = arriba.
HAIR = {
    "flame": {
        "back": [(-0.5, -0.4, 160, 2.6, 0.85, 0.3), (-0.7, 0.0, 145, 2.3, 0.75, 0.25), (-0.35, -0.7, 176, 2.5, 0.72, -0.2),
                 (-0.75, 0.35, 128, 1.8, 0.6, 0.15)],
        "front": [(-0.75, -0.5, 193, 1.7, 0.62, -0.2), (-0.45, -0.82, 205, 1.8, 0.62, -0.22), (-0.05, -0.98, 218, 1.85, 0.6, -0.2),
                  (0.35, -0.9, 233, 1.35, 0.55, -0.15), (0.62, -0.66, 250, 0.9, 0.45, -0.1), (0.5, -0.72, 40, 0.8, 0.42, 0.12),
                  (0.78, -0.42, 65, 0.55, 0.34, 0.0)],
    },
    "crown": {
        "back": [],
        "front": [(-0.7, -0.62, 250, 0.82, 0.5, 0.1), (-0.35, -0.8, 262, 1.08, 0.55, -0.1), (0.0, -0.9, 272, 1.25, 0.58, 0.07),
                  (0.35, -0.85, 282, 1.04, 0.55, -0.07), (0.68, -0.62, 294, 0.8, 0.5, 0.07)],
    },
    "short": {
        "back": [],
        "front": [(-0.85, -0.3, 185, 0.85, 0.45, 0.05), (-0.65, -0.65, 195, 1.0, 0.5, -0.12), (-0.3, -0.9, 208, 1.15, 0.52, -0.15),
                  (0.1, -0.98, 222, 1.05, 0.5, -0.12), (0.45, -0.85, 238, 0.85, 0.45, -0.1), (0.55, -0.72, 32, 0.7, 0.42, 0.08)],
    },
    "long": {
        "back": [(-0.45, -0.55, 118, 2.4, 0.85, 0.25), (-0.7, -0.15, 103, 2.2, 0.7, 0.15), (-0.25, -0.8, 132, 2.0, 0.6, 0.25)],
        "front": [(-0.6, -0.7, 200, 1.0, 0.5, -0.1), (-0.2, -0.95, 215, 0.9, 0.5, -0.1), (0.0, -0.98, 18, 1.25, 0.55, 0.22),
                  (0.35, -0.88, 40, 1.15, 0.5, 0.18)],
    },
    "rough": {
        "back": [],
        "front": [(-0.75, -0.55, 225, 0.62, 0.45, 0.08), (-0.45, -0.85, 245, 0.62, 0.45, -0.08), (-0.05, -0.97, 262, 0.6, 0.45, 0.08),
                  (0.35, -0.9, 280, 0.55, 0.42, -0.06), (0.65, -0.66, 300, 0.45, 0.38, 0.0),
                  (0.15, 0.42, 100, 0.75, 0.6, 0.05), (0.45, 0.42, 85, 0.72, 0.55, -0.05), (0.72, 0.28, 70, 0.5, 0.42, 0.0)],
    },
    "ponytail": {
        "back": [(-0.88, -0.42, 152, 2.4, 0.72, 0.3), (-0.92, -0.36, 163, 2.2, 0.62, 0.2), (-0.84, -0.5, 142, 2.0, 0.55, 0.35)],
        "front": [(0.35, -0.82, 58, 0.85, 0.45, 0.1), (0.05, -0.95, 72, 0.65, 0.42, 0.0), (-0.4, -0.9, 205, 0.7, 0.45, -0.05)],
    },
    "hood": {
        "back": [],
        "front": [(0.25, -0.62, 75, 0.65, 0.4, 0.05), (0.5, -0.58, 65, 0.55, 0.35, 0.0)],
    },
}


def draw_head(cv, F, head, hr):
    P = F["pal"]
    style = F["hair_style"]
    hx, hy = head

    def H(ox, oy):
        return (hx + ox * hr, hy + oy * hr)

    def strands(specs, layer, alternate=True, glow=False, root="hair", tip="hair2"):
        for i, (ox, oy, ang, ln, w, bend) in enumerate(specs):
            r = H(ox, oy)
            a = math.radians(ang)
            t = (r[0] + math.cos(a) * ln * hr, r[1] + math.sin(a) * ln * hr)
            strand(cv, r, t, w * hr, P[root], P[tip], layer + (i % 2 if alternate else 0), bend * hr, glow)

    # pelo / capucha por detrás
    if style == "hood":
        plate(cv, ellipse_pts(H(-0.25, -0.1), (1, 0), (0, 1), 1.25 * hr, 1.22 * hr), P["cloth"], 47, bevel=1.6, spec=False)
    strands(HAIR[style]["back"], 47, alternate=False)
    if style == "ponytail":
        knot = H(-0.88, -0.45)
        bow = dim(P["cloth"], 0.0) if "cloth" in P else P["trim"]
        plate(cv, [knot, add(knot, (-4.5, -4.0)), add(knot, (-5.0, 1.5))], bow, 48)
        plate(cv, [knot, add(knot, (2.5, -4.5)), add(knot, (-1.0, -5.0))], bow, 48.2)
    # cara, mandíbula y oreja
    skin = P["skin"]
    ellipse(cv, head, hr * 0.92, hr, skin, 51)
    capsule(cv, H(0.1, 0.3), H(0.5, 0.62), hr * 0.4, hr * 0.32, skin, 51)
    ellipse(cv, H(-0.25, 0.1), 1.8, 2.6, ramp(mix(hexc(F["skin"]), (120, 60, 50), 0.3)), 51.5, flat=True)
    # rasgos
    ex, ey = int(hx + hr * 0.42), int(hy - 0.5)
    iris = hexc(F["iris"])
    for dx, dy, col in ((0, 0, (255, 255, 255)), (1, 0, iris), (2, 0, OUTLINE[:3]), (0, 1, (230, 225, 235)),
                        (1, 1, mix(iris, (0, 0, 0), 0.4)), (2, 1, OUTLINE[:3]), (1, -1, OUTLINE[:3]), (2, -1, OUTLINE[:3])):
        cv.put(ex + dx, ey + dy, col, 52)
    cv.put(ex - 1, ey, skin[1], 52)          # cuenca del ojo
    cv.put(ex - 1, ey + 1, skin[1], 52)
    for k in range(5):                       # ceja gruesa en ángulo
        cv.put(ex - 1 + k, ey - 3 + (k // 2), P["hair"][0], 52)
        cv.put(ex - 1 + k, ey - 4 + (k // 2), P["hair"][0], 52)
    cv.put(ex + 1, ey + 3, skin[3], 52)      # pómulo
    cv.put(ex + 3, ey + 1, skin[3], 52)      # puente de la nariz
    cv.put(int(hx + hr * 0.3), int(hy + hr * 0.35), skin[1], 52)
    cv.put(int(hx + hr * 0.4), int(hy + hr * 0.4), skin[1], 52)
    mouth = mix(hexc(F["skin"]), (110, 50, 50), 0.5)
    cv.put(int(hx + hr * 0.62), int(hy + hr * 0.5), mouth, 52)
    cv.put(int(hx + hr * 0.52), int(hy + hr * 0.5), mouth, 52)
    cv.put(int(hx + hr * 0.86), int(hy + hr * 0.12), skin[0], 52)
    cv.put(int(hx + hr * 0.86), int(hy + hr * 0.2), skin[1], 52)
    face_details(cv, F, hx, hy, hr, ex, ey, skin, P["hair"], 52.2)
    # casquete de pelo y mechones delanteros
    if style == "hood":
        hood = [H(-1.15, 0.3), H(-1.05, -0.75), H(-0.4, -1.18), H(0.45, -1.12), H(1.0, -0.62), H(0.9, -0.42), H(0.3, -0.62),
                H(-0.35, -0.5), H(-0.55, 0.45)]
        plate(cv, hood, P["cloth"], 56, bevel=1.6, spec=False)
        for a, b in ((H(1.0, -0.62), H(0.3, -0.62)), (H(0.3, -0.62), H(-0.35, -0.5)), (H(-0.35, -0.5), H(-0.55, 0.45))):
            line(cv, a, b, P["cloth_in"][2], 56.3)
        cv.put(*H(0.55, -0.88), F["glow"], 56.5, glow=True)
        strands(HAIR[style]["front"], 55)
    elif style == "crown":
        ellipse(cv, H(-0.12, -0.66), hr * 0.96, hr * 0.5, P["hair_cap"], 53)
        strands(HAIR[style]["front"], 54, glow=True, root="hair2", tip="hair")
        plate(cv, [H(-0.95, -0.5), H(0.95, -0.66), H(0.97, -0.4), H(-0.95, -0.25)], P["trim"], 56)
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            cv.put(H(0.55, -0.55)[0] + dx, H(0.55, -0.55)[1] + dy, F["glow"], 56.5, glow=True)
    else:
        ellipse(cv, H(-0.12, -0.66), hr * 0.98, hr * 0.52, P["hair"], 53)
        strands(HAIR[style]["front"], 54)
        if style == "long":
            mask = [H(-0.25, -0.32), H(1.02, -0.4), H(1.0, 0.04), H(-0.25, 0.08)]
            plate(cv, mask, metal(F["armor"]), 56)
            line(cv, H(-0.2, -0.34), H(1.0, -0.42), F["glow"], 56.3, glow=True)
            cv.put(ex, ey, (255, 255, 255), 56.5)
            cv.put(ex + 1, ey, iris, 56.5)
        elif style == "ponytail":
            line(cv, H(-0.85, -0.72), H(0.6, -0.95), P["cloth"][2] if "cloth" in P else P["trim"][2], 56, width=2)
        elif style == "rough":
            line(cv, H(0.6, 0.36), H(0.98, 0.3), P["hair"][0], 56)   # bigote
    if style != "long":
        # Los ojos se repasan encima del pelo para que nunca queden tapados.
        for dx, dy, col in ((0, 0, (255, 255, 255)), (1, 0, iris), (2, 0, OUTLINE[:3]),
                            (1, 1, mix(iris, (0, 0, 0), 0.4)), (1, -1, OUTLINE[:3]), (2, -1, OUTLINE[:3])):
            cv.put(ex + dx, ey + dy, col, 57, glow=(F.get("face") == "glow" and dx < 2 and dy >= 0))


def face_details(cv, F, hx, hy, hr, ex, ey, skin, hair, layer):
    """Rasgos propios de cada cara: pestañas, labios, cicatriz, sonrisa, ojos que brillan."""
    face = F.get("face", "")
    lips = mix(hexc(F["skin"]), (200, 70, 80), 0.45)
    if face.endswith("_f"):
        cv.put(ex + 3, ey - 1, OUTLINE, layer)
        cv.put(ex + 3, ey - 2, OUTLINE, layer)
        cv.put(int(hx + hr * 0.52), int(hy + hr * 0.5), lips, layer)
        cv.put(int(hx + hr * 0.62), int(hy + hr * 0.5), lips, layer)
        cv.put(int(hx + hr * 0.57), int(hy + hr * 0.58), lips, layer)
        if face == "fierce_f":
            cv.put(ex - 1, ey - 4, hair[0], layer)
        if face == "soft_f":
            cv.put(int(hx + hr * 0.25), int(hy + hr * 0.25), mix(hexc(F["skin"]), (240, 120, 120), 0.4), layer)
    elif face == "scar":
        for k in range(4):
            cv.put(int(hx + hr * 0.15) + k, int(hy - hr * 0.2) + k, mix(hexc(F["skin"]), (150, 60, 60), 0.6), layer)
    elif face == "smirk":
        cv.put(int(hx + hr * 0.7), int(hy + hr * 0.42), mix(hexc(F["skin"]), (110, 50, 50), 0.6), layer)
    elif face == "glow":
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            cv.put(ex + dx, ey + dy, (255, 200, 90), layer, glow=True)
        cv.put(ex + 2, ey, (255, 140, 60), layer, glow=True)
    elif face == "stern":
        for k in range(4):
            cv.put(int(hx + hr * 0.3) + k, int(hy + hr * 0.75), skin[0], layer)


# ----------------------------------------------------------------- figura completa
def draw_fighter(cfg, pose, name="", streaks=None):
    cv = Canvas()
    F = dict(cfg)
    F["pal"] = P = palettes(cfg)
    F["glow"] = hexc(cfg["glow"]) if cfg.get("glow") else None
    drop = pose.get("drop", 0) * SY
    j = {k: add(tf(v, k), (0, drop)) for k, v in pose.items() if isinstance(v, tuple)}
    bulk = cfg["bulk"]
    female = cfg["female"]
    R = RS
    hip, neck = j["hip"], j["neck"]
    head = j.get("head") or (neck[0] + 2.5 * SX, neck[1] - 12.5 * SY)
    tu = unit(sub(neck, hip))
    tn = frontward(perp(tu))
    TL = length(sub(neck, hip))

    def T(a, b):
        return (hip[0] + tu[0] * a * TL + tn[0] * b, hip[1] + tu[1] * a * TL + tn[1] * b)

    cw = (10.4 if female else 12.6) * R * bulk
    ww = (7.2 if female else 8.4) * R * bulk
    sh_f = T(0.86, 5.8 * bulk)
    sh_b = T(0.87, -7.2 * bulk)
    hip_b = (hip[0] - 3, hip[1])
    hip_f = (hip[0] + 3, hip[1])
    back_front = pose.get("back_arm_front", False)

    draw_cloth_back(cv, F, T, cw, ww)
    if not back_front:
        draw_arm(cv, F, sh_b, j["el_b"], j["ha_b"], 10, back=True)
        draw_pauldron(cv, F, sh_b, j["el_b"], 16, back=True)
    draw_leg(cv, F, hip_b, j["kn_b"], j["ft_b"], 20, back=True)
    draw_torso(cv, F, T, cw, ww, hip_b, hip_f)
    draw_leg(cv, F, hip_f, j["kn_f"], j["ft_f"], 40, back=False)
    draw_belt(cv, F, T, ww)
    capsule(cv, neck, (head[0] - 1, head[1] + 4), 3.6 * R, 3.4 * R, P["skin"], 49)
    if F["hair_style"] != "hood":
        plate(cv, [T(0.95, -0.5 * cw), T(0.96, 0.45 * cw), T(1.1, 0.32 * cw), T(1.1, -0.36 * cw)], P["trim"], 50)
    draw_head(cv, F, head, 9.0 * R)
    if F["cloth"] == "scarf":
        ellipse(cv, add(neck, (1, 3)), 6.5 * R, 3.8 * R, P["cloth"], 58)
        line(cv, add(neck, (-4 * R, 3)), add(neck, (6 * R, 4)), P["cloth"][0], 58.2)
    if back_front:
        draw_arm(cv, F, sh_b, j["el_b"], j["ha_b"], 60, back=True)
        draw_pauldron(cv, F, sh_b, j["el_b"], 66, back=True)
    draw_arm(cv, F, sh_f, j["el_f"], j["ha_f"], 70, back=False)
    draw_pauldron(cv, F, sh_f, j["el_f"], 76, back=False)

    finish(cv, F["glow"])
    if streaks:
        draw_streaks(cv, streaks, mix(ELEMENT_GLOW[cfg["element"]], (255, 255, 255), 0.45), drop)
    apply_element(cv, cfg, j, name.split("_smear")[0])
    return cv, head


# ----------------------------------------------------------------- fases de los golpes
def lerp_pose(a, b, t):
    out = {}
    for k in set(a) | set(b):
        va, vb = a.get(k), b.get(k)
        if isinstance(va, tuple) and isinstance(vb, tuple):
            out[k] = (va[0] + (vb[0] - va[0]) * t, va[1] + (vb[1] - va[1]) * t)
        elif isinstance(vb, tuple):
            out[k] = vb
        elif isinstance(va, tuple):
            out[k] = va
        else:
            out[k] = vb if vb is not None else va
    if "head" not in a or "head" not in b:
        out.pop("head", None)
    return out


# golpe -> (pose de partida, miembros que dejan estela)
STRIKE_BASES = {
    "jab": ("stance", ("ha_f",)), "cross": ("stance", ("ha_b",)), "hook": ("stance", ("ha_f",)),
    "uppercut": ("stance", ("ha_f",)), "throw": ("stance", ("ha_f", "ha_b")), "air_punch": ("jump", ("ha_f",)),
    "kick_low": ("kick_chamber", ("ft_f",)), "kick_mid": ("kick_chamber", ("ft_f",)),
    "kick_high": ("kick_chamber", ("ft_f",)), "kick_spin": ("kick_chamber", ("ft_f",)),
    "sweep": ("charge", ("ft_f",)), "air_kick": ("jump", ("ft_f",)),
}
PUNCHES = ("jab", "cross", "hook", "uppercut", "throw", "air_punch")


def build_phases():
    """Fases intermedias de cada golpe: preparación, golpe en curso (con estela) y recuperación."""
    phases = {}
    for strike, (base, limbs) in STRIKE_BASES.items():
        a, b = POSES[base], POSES[strike]
        if strike in PUNCHES:
            phases[strike + "_anticipate"] = (lerp_pose(a, b, -0.25), None)
            phases[strike + "_punch"] = (lerp_pose(a, b, 0.35), None)
        phases[strike + "_smear"] = (lerp_pose(a, b, 0.62), [(a[l], b[l]) for l in limbs])
        phases[strike + "_recover"] = (lerp_pose(a, b, 0.45), None)
    return phases


def draw_streaks(cv, streaks, color, drop=0.0):
    """Estela de movimiento detrás del puño o del pie (solo sobre el fondo vacío)."""
    for a, b in streaks:
        a, b = add(tf(a), (0, drop)), add(tf(b), (0, drop))
        dx, dy = b[0] - a[0], b[1] - a[1]
        ln = math.hypot(dx, dy) or 1
        nx, ny = -dy / ln, dx / ln
        for lane, alpha in ((-8, 0.45), (-5, 0.6), (5, 0.6), (8, 0.45), (0, 0.5)):
            steps = int(ln)
            for i in range(steps):
                t = i / max(1, steps)
                if (i // 3) % 3 == 2 and lane != 0:
                    continue
                xi = int(a[0] + dx * t + nx * lane)
                yi = int(a[1] + dy * t + ny * lane)
                if 0 <= xi < SIZE and 0 <= yi < SIZE and cv.px[yi * SIZE + xi] is None:
                    blend(cv, xi, yi, color, alpha * (0.3 + 0.7 * t))


# ----------------------------------------------------------------- efectos elementales
# Se dibujan encima del sprite ya terminado (sin contorno), como los rayos de Volt.
ATTACK_POSES = ("jab", "cross", "hook", "uppercut", "throw", "air_punch", "kick_low", "kick_mid", "kick_high",
                "kick_spin", "sweep", "air_kick")
ELEMENT_GLOW = {
    "fire": (255, 150, 60), "ember": (255, 120, 50), "water": (110, 230, 225), "prism": (210, 170, 255),
    "mirror": (255, 190, 230), "rock": (220, 190, 140), "light": (200, 255, 170),
}


class Rand:
    def __init__(self, seed):
        self.v = (seed * 2654435761) & 0xFFFFFFFF or 1

    def f(self):
        self.v ^= (self.v << 13) & 0xFFFFFFFF
        self.v ^= self.v >> 17
        self.v ^= (self.v << 5) & 0xFFFFFFFF
        return (self.v & 0xFFFF) / 65535.0


def aura(cv, cx, cy, r, color, strength):
    """Tiñe los píxeles cercanos y añade un halo suave fuera de la silueta."""
    for y in range(int(cy - r), int(cy + r) + 1):
        for x in range(int(cx - r), int(cx + r) + 1):
            d = math.hypot(x - cx, y - cy)
            if d > r or not (0 <= x < SIZE and 0 <= y < SIZE):
                continue
            k = (1.0 - d / r) * strength
            if cv.px[y * SIZE + x] is None:
                if k > 0.18 and (x + y) % 2 == 0:
                    blend(cv, x, y, color, k * 0.55)
            else:
                blend(cv, x, y, color, k * 0.5)


def apply_element(cv, cfg, j, name):
    element = cfg.get("element")
    if not element:
        return
    rnd = Rand(sum(ord(ch) * (i + 1) for i, ch in enumerate(name + element)))
    count = 4
    if name in ATTACK_POSES:
        count = 10
    elif name in ("special", "charge", "victory"):
        count = 16
    kick = name.startswith("kick") or name in ("sweep", "air_kick")
    anchors = [j["ft_f"]] if kick else [j["ha_f"]]
    if name in ("charge", "victory", "special", "block", "throw"):
        anchors.append(j["ha_b"])
    if element == "rock":
        anchors.append(j["ft_b"])
    accent = hexc(cfg["glow"])
    glow = ELEMENT_GLOW[element]
    strong = name in ATTACK_POSES or name in ("special", "charge", "victory")
    for ax, ay in anchors:
        aura(cv, ax, ay, 11 if strong else 7, glow, 0.55 if strong else 0.3)
    if element == "water" and strong:
        ax, ay = anchors[0]
        for k in range(12):
            ang = k / 12.0 * math.tau * 0.75 + 0.6
            blend(cv, ax + math.cos(ang) * 10, ay + math.sin(ang) * 8, (150, 240, 235), 0.9)
            blend(cv, ax + math.cos(ang) * 11, ay + math.sin(ang) * 9, (60, 170, 190), 0.6)
    for m in range(count):
        ax, ay = anchors[m % len(anchors)]
        ang = rnd.f() * math.tau
        dist = 3 + rnd.f() * 12
        x = ax + math.cos(ang) * dist
        y = ay + math.sin(ang) * dist * 0.8
        if element in ("fire", "ember", "light"):
            y -= rnd.f() * 8  # suben
        motif(cv, element, x, y, rnd, accent)


def motif(cv, element, x, y, rnd, accent):
    white = (255, 255, 245)
    x = min(max(x, 3), SIZE - 6)
    y = min(max(y, 9), SIZE - 7)
    if element == "fire":
        h = 4 + int(rnd.f() * 5)
        for k in range(h):
            w = max(1, (h - k) // 2)
            col = (255, 240, 150) if k < h // 2 else ((255, 150, 50) if k < h - 1 else (230, 70, 40))
            for dx in range(-w // 2, w // 2 + 1):
                blend(cv, x + dx, y - k, col, 0.95)
        blend(cv, x, y + 1, (255, 120, 40), 0.45)
    elif element == "ember":
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            blend(cv, x + dx, y + dy, (255, 230, 140) if (dx, dy) == (0, 0) else (255, 150, 60), 1.0)
        for dx, dy in ((-1, 0), (0, -1), (2, 1), (1, 2), (-1, 1), (1, -1), (2, 0), (0, 2)):
            blend(cv, x + dx, y + dy, (255, 110, 40), 0.45)
        blend(cv, x + 1, y + 3, (255, 140, 60), 0.6)
    elif element == "water":
        col = (120, 230, 220)
        for dx, dy in ((0, 0), (0, 1), (-1, 2), (0, 2), (1, 2), (-1, 3), (0, 3), (1, 3), (0, 4)):
            blend(cv, x + dx, y + dy, col, 0.95)
        blend(cv, x, y + 5, (60, 150, 170), 0.9)
        blend(cv, x + 1, y + 4, (60, 150, 170), 0.9)
        blend(cv, x - 1, y + 2, white, 1.0)
    elif element == "prism":
        r = 2 + int(rnd.f() * 2)
        for dy in range(-r, r + 1):
            w = r - abs(dy)
            for dx in range(-w, w + 1):
                blend(cv, x + dx, y + dy, accent if abs(dx) + abs(dy) > 0 else white, 0.9)
        blend(cv, x - 1, y - 1, white, 1.0)
    elif element == "mirror":
        r = 2 + int(rnd.f() * 3)
        blend(cv, x, y, white, 1.0)
        for k in range(1, r + 1):
            a = 0.95 - k * 0.18
            for dx, dy in ((k, 0), (-k, 0), (0, k), (0, -k)):
                blend(cv, x + dx, y + dy, accent if k > 1 else white, a)
    elif element == "rock":
        col = (150, 120, 90)
        size = 2 + int(rnd.f() * 2)
        for dy in range(size + 1):
            for dx in range(size + 1):
                if dx + dy <= size + 1:
                    blend(cv, x + dx, y + dy, col, 1.0)
        blend(cv, x, y, (225, 200, 160), 1.0)
        blend(cv, x + 1, y, (225, 200, 160), 1.0)
        for k in range(size + 1):
            blend(cv, x + size, y + k, (80, 60, 45), 1.0)
        blend(cv, x - 2, y + size + 1, (190, 175, 150), 0.5)
    elif element == "light":
        blend(cv, x, y, white, 1.0)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            blend(cv, x + dx, y + dy, accent, 0.85)
        for dx, dy in ((2, 0), (-2, 0), (0, 2), (0, -2)):
            blend(cv, x + dx, y + dy, accent, 0.6)
        for dx, dy in ((3, 0), (-3, 0), (0, 3), (0, -3), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            blend(cv, x + dx, y + dy, accent, 0.25)


# ----------------------------------------------------------------- claves para FighterPainter
PHASES = {}

ALIASES = {
    "light_anticipate": "jab_anticipate", "light_recover": "jab_recover", "light_smear": "jab_smear",
    "heavy_anticipate": "cross_anticipate", "heavy_recover": "cross_recover", "heavy_smear": "cross_smear",
    "heavy_punch": "cross_punch",
    "weak_anticipate": "jab_anticipate", "weak_recover": "jab_recover",
    "strong_anticipate": "cross_anticipate", "strong_recover": "cross_recover", "strong_smear": "cross_smear",
    "strong_punch": "cross_punch",
    "finisher_smear": "kick_high_smear", "kick_smear": "kick_high_smear", "finisher_recover": "kick_high_recover",
    "light": "jab", "heavy": "cross", "weak": "jab", "strong": "cross",
    "finisher": "kick_chamber", "finisher_impact": "kick_high", "kick": "kick_high",
    "kick_low_kick": "kick_chamber", "kick_mid_kick": "kick_chamber", "kick_high_kick": "kick_chamber",
    "kick_spin_kick": "kick_chamber", "sweep_kick": "charge", "air_kick_kick": "jump",
    "fall": "hurt",
}

PHASES.update(build_phases())


def main(only=None):
    for fid, cfg in FIGHTERS.items():
        if only and fid not in only:
            continue
        folder = OUT / fid
        folder.mkdir(parents=True, exist_ok=True)
        for name, pose in POSES.items():
            cv, _ = draw_fighter(cfg, pose, name)
            save_png(cv, folder / ("%s_%s.png" % (fid, name)))
        print(fid, "listo")


if __name__ == "__main__":
    main(sys.argv[1:] or None)
