"""Build the mystical larder: a whole model for every ingredient in data/ingredients.

    blender --background --factory-startup --python tools/blender/larder.py [-- id ...]

There are too many ingredients to sculpt one by one, so each is built by one of a
few shape *families* (fish, eel, bird, crab, fillet, organ, leaf, kelp, root,
mushroom, grain, ...) from a row in SPECS that names the family and its shape
parameters. Size and colours are never written here: they are read from the
ingredient's own .tres (whole_size_mm, tint_color, flesh_color), so a model
always matches what the simulation cuts and cooks.

Each model is written to models/larder/<id>.blend and exported to the .glb path
from glb_path(), with a `skin` slot in the ingredient's tint and a `flesh` slot
for cut faces. Painted shading (a darker back on a fish, the fat cap on a loin,
veins on a leaf) is a vertex-colour multiplier on the slot colour, exported as
COLOR_0, so the cel shader in Godot still owns the light.

validate_models.py imports SPECS and checks every model built here.
"""

import math
import os
import re
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import bumpy, tube  # noqa: E402

TAU = 2.0 * math.pi
ROOT = kit.ROOT
INGREDIENTS = os.path.join(ROOT, "data", "ingredients")


# --------------------------------------------------------------------------
# Reading the ingredient data
# --------------------------------------------------------------------------

def tres_path(ingredient_id):
    for folder, _dirs, files in os.walk(INGREDIENTS):
        if ingredient_id + ".tres" in files:
            return os.path.join(folder, ingredient_id + ".tres")
    raise SystemExit(f"no ingredient {ingredient_id} under data/ingredients")


def read_ingredient(ingredient_id):
    text = open(tres_path(ingredient_id)).read()

    def field(key):
        m = re.search(r"^" + key + r" = (.*)$", text, re.M)
        return m.group(1) if m else None

    def numbers(value):
        inside = value[value.index("(") + 1:value.rindex(")")]
        return [float(n) for n in inside.split(",")]

    size = numbers(field("whole_size_mm"))
    tint = numbers(field("tint_color"))[:3]
    flesh_field = field("flesh_color")
    flesh = numbers(flesh_field)[:3] if flesh_field else tint
    # whole_size_mm is (length X, height Y, depth Z) in Godot; Blender is
    # length X, depth Y, height Z.
    return {
        "size": (size[0] / 1000.0, size[2] / 1000.0, size[1] / 1000.0),
        "tint": tint,
        "flesh": flesh,
    }


def glb_path(ingredient_id):
    rel = os.path.relpath(tres_path(ingredient_id), INGREDIENTS)
    parts = rel.split(os.sep)
    if parts[0] == "catch" and len(parts) == 3:
        return f"assets/models/catch/{parts[1]}/{ingredient_id}.glb"
    return f"assets/models/ingredients/{ingredient_id}.glb"


# --------------------------------------------------------------------------
# Small helpers
# --------------------------------------------------------------------------

def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a))) if b != a else float(x >= a)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def interp(values, t):
    """Piecewise-linear sample of a list spread evenly over 0..1."""
    t = max(0.0, min(1.0, t)) * (len(values) - 1)
    i = min(int(t), len(values) - 2)
    return lerp(values[i], values[i + 1], t - i)


def mat_rgb(name, rgb, roughness=0.8, alpha=1.0):
    """A slot material from a Godot (sRGB) colour."""
    return kit.material(name, "#%02x%02x%02x" % tuple(int(max(0, min(1, c)) * 255 + 0.5) for c in rgb),
                        roughness=roughness, alpha=alpha)


def tag(sub, mat_index):
    for f in sub.faces:
        f.material_index = mat_index
    return sub


def sphere(center, radii, mat_index, u=12, v=8, shape=None, bump=0.0, bump_scale=2.0, seed=0):
    """A deformed UV sphere. `shape(p)` reshapes the unit sphere first."""
    sub = bmesh.new()
    bmesh.ops.create_uvsphere(sub, u_segments=u, v_segments=v, radius=1.0)
    for vert in sub.verts:
        p = vert.co.copy()
        if shape:
            p = shape(p)
        if bump:
            p = p * bumpy(p, bump_scale, bump, seed)
        vert.co = Vector((center[0] + p.x * radii[0], center[1] + p.y * radii[1], center[2] + p.z * radii[2]))
    return tag(sub, mat_index)


def add(bm, sub):
    kit.merge(bm, sub)


def add_tube(bm, path, radii, sides, mat_index, **kwargs):
    sub = bmesh.new()
    _rings, faces = tube(sub, path, radii, sides, mat_index, **kwargs)
    return sub, faces


def put_tube(bm, path, radii, sides, mat_index, end_mat=None, **kwargs):
    sub, faces = add_tube(bm, path, radii, sides, mat_index, **kwargs)
    if end_mat is not None and kwargs.get("cap_end", True):
        faces[-1].material_index = end_mat
    add(bm, sub)


def sheet(outline, thickness, mat_index, rings=4, lift=None, edge_thin=0.5, center=None):
    """A closed thin plate: a fan of `rings` rings from a centre out to a
    star-shaped outline (a list of (x, y)), lifted by `lift(x, y)` in Z and
    thinning toward its edge."""
    sub = bmesh.new()
    n = len(outline)
    cx = sum(p[0] for p in outline) / n if center is None else center[0]
    cy = sum(p[1] for p in outline) / n if center is None else center[1]
    lift = lift or (lambda x, y: 0.0)

    def ring_points(k):
        t = k / rings
        pts = []
        for (x, y) in outline:
            px, py = cx + (x - cx) * t, cy + (y - cy) * t
            half = thickness * 0.5 * (1.0 - edge_thin * t * t)
            pts.append((px, py, lift(px, py), half))
        return pts

    top_rings, bottom_rings = [], []
    for k in range(1, rings + 1):
        pts = ring_points(k)
        top_rings.append([sub.verts.new((x, y, z + h)) for x, y, z, h in pts])
        bottom_rings.append([sub.verts.new((x, y, z - h)) for x, y, z, h in pts])
    z0 = lift(cx, cy)
    top_c = sub.verts.new((cx, cy, z0 + thickness * 0.5))
    bot_c = sub.verts.new((cx, cy, z0 - thickness * 0.5))
    for i in range(n):
        j = (i + 1) % n
        sub.faces.new((top_c, top_rings[0][i], top_rings[0][j]))
        sub.faces.new((bot_c, bottom_rings[0][j], bottom_rings[0][i]))
        for k in range(rings - 1):
            sub.faces.new((top_rings[k][i], top_rings[k + 1][i], top_rings[k + 1][j], top_rings[k][j]))
            sub.faces.new((bottom_rings[k][j], bottom_rings[k + 1][j], bottom_rings[k + 1][i], bottom_rings[k][i]))
        sub.faces.new((top_rings[-1][i], bottom_rings[-1][i], bottom_rings[-1][j], top_rings[-1][j]))
    return tag(sub, mat_index)


def ellipse_outline(rx, ry, count, wobble=0.0, seed=0, tip=0.0, waves=0, wave_amp=0.0, notch=0.0):
    """Points round an ellipse, optionally pointed at both X ends (`tip`),
    waved (`waves` bumps of `wave_amp`) and notched at -X (`notch`, a heart)."""
    pts = []
    for s in range(count):
        a = TAU * s / count
        r = 1.0 + wobble * noise.noise(Vector((math.cos(a) * 1.7 + seed, math.sin(a) * 1.7, seed * 0.37)))
        if waves:
            r += wave_amp * math.sin(a * waves + seed)
        x, y = math.cos(a), math.sin(a)
        if tip:
            y *= (1.0 - tip * abs(x) ** 3)
        if notch:
            r *= 1.0 - notch * max(0.0, -x) ** 8
        pts.append((x * rx * r, y * ry * r))
    return pts


def fan_outline(spread, length, count, base=0.1, ragged=0.0, fork=0.0, seed=0):
    """A fin: a fan opening `spread` radians from a narrow base at the origin
    along +X; `fork` cuts a V into its trailing edge."""
    pts = [(0.0, -base * 0.5)]
    for s in range(count + 1):
        t = s / count
        a = (t - 0.5) * spread
        r = length * (1.0 - fork * (1.0 - abs(t - 0.5) * 2.0))
        r *= 1.0 + ragged * (noise.noise(Vector((t * 7.0, seed, 0.3))) )
        pts.append((math.cos(a) * r, math.sin(a) * r))
    pts.append((0.0, base * 0.5))
    return pts


def place(sub, matrix):
    bmesh.ops.transform(sub, matrix=matrix, verts=sub.verts)
    return sub


def paint(bm, fn):
    """Vertex-colour multiplier: fn(u, co, mat_index) -> (r, g, b) as an
    sRGB multiplier, with u the vertex position normalised to the model's
    bounds. Stored linear, as glTF expects COLOR_0."""
    layer = bm.verts.layers.float_color.new("Color")
    lo = Vector((min(v.co[i] for v in bm.verts) for i in range(3)))
    hi = Vector((max(v.co[i] for v in bm.verts) for i in range(3)))
    span = Vector((max(hi[i] - lo[i], 1e-9) for i in range(3)))
    for v in bm.verts:
        u = Vector(((v.co[i] - lo[i]) / span[i] for i in range(3)))
        mat_index = v.link_faces[0].material_index if v.link_faces else 0
        rgb = [kit._linear(max(0.0, min(1.0, c))) for c in fn(u, v.co, mat_index)]
        v[layer] = (rgb[0], rgb[1], rgb[2], 1.0)


def grey(k):
    return (k, k, k)


def hue_shift(rgb_from, rgb_to, t):
    """A multiplier that moves rgb_from toward rgb_to by t (both sRGB)."""
    return tuple(lerp(1.0, (b / a if a > 0.02 else 1.0), t) for a, b in zip(rgb_from, rgb_to))


# --------------------------------------------------------------------------
# Families. Each builds into `bm` at a convenient scale (the model is fitted
# to the ingredient's exact size afterwards), returns its slot list as
# (name, colour, roughness), and paints itself.
# --------------------------------------------------------------------------

def _fish_body(bm, P, upto=1.0):
    """The body tube of a fish lying on its side: X nose to tail, Y the
    body depth (back +Y), Z its thickness. Returns depth(x) for fin placing."""
    depth, thick = P.get("depth", 0.36), P.get("thick", 0.16)
    prof = P.get("profile", [0.0, 0.5, 0.78, 0.95, 1.0, 0.95, 0.8, 0.58, 0.36, 0.22, 0.17])
    tprof = P.get("thick_profile", [0.0, 0.55, 0.82, 0.96, 1.0, 0.95, 0.8, 0.6, 0.4, 0.25, 0.2])
    body = 0.8
    stations = 14
    count = stations if upto >= 1.0 else max(3, int(stations * upto) + 1)
    path, radii = [], []
    for i in range(count):
        t = i / (count - 1) * upto
        path.append((body * t, 0.0, 0.0))
        d, th = interp(prof, t) * depth * 0.5, interp(tprof, t) * thick * 0.5
        radii.append(0.0 if i == 0 else (d, th))
    put_tube(bm, path, radii, 12, 0, up=(0, 1, 0), end_mat=3 if upto < 1.0 else None,
             shape=lambda a, i: 1.0 + 0.04 * math.cos(2 * a))
    return lambda x: interp(prof, x / body) * depth * 0.5, lambda x: interp(tprof, x / body) * thick * 0.5


def _fish_face(bm, P, half_depth, half_thick):
    ex = P.get("eye_at", 0.085)
    er = P.get("eye_size", 0.026)
    for side in (1, -1):
        z = half_thick(ex) * 0.86 * side
        add(bm, sphere((ex, half_depth(ex) * 0.25, z), (er, er, er * 0.55), 2, u=8, v=6))
    for (bx, by) in P.get("barbels", []):
        put_tube(bm, [(0.01, by, 0.0), (bx * 0.5, by - 0.02, 0.0), (bx, by - 0.05, 0.004)],
                 [0.004, 0.003, 0.0], 4, 1)


def fish(bm, P):
    hd, ht = _fish_body(bm, P)
    depth = P.get("depth", 0.36)
    thick = P.get("thick", 0.16)
    _fish_face(bm, P, hd, ht)
    fin_t = thick * 0.08
    # Tail: a forked (or wispy) fan off the peduncle.
    tail = fan_outline(P.get("tail_spread", 1.5), P.get("tail_len", 0.24), 10, base=hd(0.8) * 1.2,
                       fork=P.get("fork", 0.45), ragged=P.get("tail_ragged", 0.0), seed=3)
    add(bm, place(sheet(tail, fin_t, 1, rings=3, edge_thin=0.3), Matrix.Translation((0.77, 0, 0))))
    # Dorsal and anal fins ride the back and belly edges.
    for side, (a, b, h) in ((1, P.get("dorsal", (0.26, 0.66, 0.22))), (-1, P.get("anal", (0.5, 0.7, 0.12)))):
        pts = [(a, side * (hd(a) - 0.01)), (a + (b - a) * 0.18, side * (hd(a) + depth * h)),
               (b, side * (hd(b) + depth * h * 0.35)), (b + 0.02, side * (hd(b) - 0.01))]
        mid = ((a + b) * 0.5, side * (hd((a + b) * 0.5) * 0.8))
        outline = [pts[0], pts[1], pts[2], pts[3]]
        if side < 0:
            outline.reverse()
        add(bm, sheet(outline, fin_t, 1, rings=2, center=mid, edge_thin=0.4))
    # Pectoral fins lie along each flank behind the gill.
    for side in (1, -1):
        pec = fan_outline(0.7, 0.09, 4, base=0.02, seed=7)
        sub = sheet(pec, fin_t, 1, rings=2, edge_thin=0.4)
        place(sub, Matrix.Translation((0.17, -hd(0.17) * 0.25, ht(0.17) * 0.75 * side))
              @ Matrix.Rotation(-0.5, 4, "Z") @ Matrix.Rotation(side * 0.25, 4, "Y"))
        add(bm, sub)

    back = P.get("back", 0.55)
    stripes = P.get("stripes", 0)
    spots = P.get("spots", 0.0)
    gill = P.get("gill_at", 0.17)

    def shade(u, co, m):
        if m == 2:
            return grey(1.0)
        if m == 1:
            return grey(lerp(1.0, 0.75, u.y))
        k = 1.0 - back * smooth(0.45, 0.95, u.y)
        if stripes:
            k *= 1.0 - 0.12 * smooth(0.6, 0.9, math.sin(co.x * stripes * TAU) * 0.5 + 0.5)
        if spots:
            n = noise.noise(co * 60.0)
            k *= 1.0 - spots * smooth(0.25, 0.4, n)
        # The gill cover's edge reads as a darker crescent.
        k *= 1.0 - 0.25 * smooth(0.012, 0.0, abs(co.x - gill - 0.03 * (u.y - 0.5) ** 2))
        # Scales: a soft diamond lattice.
        lattice = abs(math.sin(co.x * 160 + co.y * 120)) * abs(math.sin(co.x * 160 - co.y * 120))
        k *= 1.0 - 0.06 * lattice
        return grey(k)

    paint(bm, shade)
    return [("skin", None, 0.35), ("fin", P.get("fin_color", (0.8, 0.82, 0.85)), 0.5),
            ("eye", (0.08, 0.08, 0.1), 0.15), ("flesh", "flesh", 0.6)]


def fish_head(bm, P):
    hd, ht = _fish_body(bm, P, upto=P.get("upto", 0.36))
    _fish_face(bm, P, hd, ht)
    back = P.get("back", 0.55)
    paint(bm, lambda u, co, m: grey(1.0) if m in (2, 3) else grey(1.0 - back * smooth(0.45, 0.95, u.y)))
    return [("skin", None, 0.35), ("fin", (0.8, 0.82, 0.85), 0.5), ("eye", (0.08, 0.08, 0.1), 0.15),
            ("flesh", "flesh", 0.6)]


def _eel_path(P, length=1.0, upto=1.0):
    amp = P.get("curve", 0.08)
    n = 22
    pts = []
    for i in range(n):
        t = i / (n - 1) * upto
        pts.append((t * length, amp * math.sin(t * TAU * 0.85 + 0.4), 0.0))
    return pts


def eel(bm, P, upto=1.0):
    r = P.get("radius", 0.035)
    path = _eel_path(P, upto=upto)
    radii = []
    for i in range(len(path)):
        t = i / (len(path) - 1) * upto
        k = 1.0 if t < 0.55 else (1.0 - (t - 0.55) / 0.45) ** 0.7
        head = 0.8 + 0.2 * smooth(0.0, 0.08, t)
        radii.append((r * k * 0.85 * head, r * k * head) if i else 0.0)
    if upto >= 1.0:
        radii[-1] = 0.0
    # A low fin fringe runs along the top of the back half.
    put_tube(bm, path, radii, 10, 0, up=(0, 0, 1), end_mat=3 if upto < 1.0 else None,
             shape=lambda a, i: 1.0 + (0.35 * max(0.0, math.cos(a)) ** 8 if i > len(path) * 0.4 else 0.0))
    for side in (1, -1):
        add(bm, sphere((0.03, path[1][1] + side * r * 0.62, r * 0.45), (0.009, 0.009, 0.007), 2, u=8, v=6))
    glow = P.get("spots", 0.0)

    def shade(u, co, m):
        if m in (2, 3):
            return grey(1.0)
        k = lerp(0.75, 1.0, smooth(0.3, 0.9, u.z))
        if glow:
            # Lantern spots down each flank: lighter dots the glow shines through.
            lane = abs(math.sin(co.x * 90.0))
            k = lerp(k, 1.0, glow * smooth(0.85, 0.97, lane) * smooth(0.35, 0.6, u.z))
        return hue_shift((1, 1, 1), (k, k, k * 1.05), 1.0)

    paint(bm, shade)
    return [("skin", None, 0.25), ("fin", P.get("fin_color", (0.2, 0.25, 0.3)), 0.4),
            ("eye", P.get("eye_color", (0.55, 0.85, 1.0)), 0.1), ("flesh", "flesh", 0.6)]


def eel_head(bm, P):
    return eel(bm, P, upto=P.get("upto", 0.14))


def bird(bm, P):
    """A plucked bird on its back, breast up, neck toward -X."""
    def body_shape(p):
        q = p.copy()
        if q.z > 0:  # the breast swells over the keel
            q.z *= 1.0 + 0.18 * (1.0 - abs(q.y))
        if q.z < -0.45:
            q.z = -0.45 + (q.z + 0.45) * 0.3
        q.x *= 1.0 - 0.12 * max(0.0, q.x)  # tapering toward the tail
        return q
    add(bm, sphere((0, 0, 0.34), (0.5, 0.34, 0.34), 0, u=18, v=12, shape=body_shape, bump=0.03, seed=2))
    for side in (1, -1):
        # Drumsticks folded forward along the flanks.
        put_tube(bm, [(0.22, side * 0.26, 0.22), (0.06, side * 0.33, 0.42), (-0.12, side * 0.28, 0.56),
                      (-0.2, side * 0.25, 0.6)],
                 [0.11, 0.12, 0.07, (0.045, 0.045)], 10, 0, cap_end=True)
        add(bm, sphere((-0.21, side * 0.25, 0.61), (0.05, 0.05, 0.05), 1, u=8, v=6))
        # Wings tucked under.
        put_tube(bm, [(-0.25, side * 0.3, 0.28), (-0.05, side * 0.38, 0.2), (0.12, side * 0.34, 0.16)],
                 [0.07, 0.06, 0.03], 8, 0)
    put_tube(bm, [(-0.45, 0, 0.32), (-0.58, 0, 0.3), (-0.64, 0, 0.29)], [0.1, 0.08, 0.075], 10, 0, end_mat=2)
    add(bm, sphere((0.52, 0, 0.36), (0.07, 0.07, 0.06), 0, u=8, v=6))
    paint(bm, lambda u, co, m: grey(1.0) if m else
          grey(lerp(0.82, 1.0, smooth(0.2, 0.8, u.z)) * (1.0 - 0.05 * noise.noise(co * 40.0))))
    return [("skin", None, 0.45), ("knuckle", (0.85, 0.72, 0.55), 0.6), ("flesh", "flesh", 0.6)]


def crab(bm, P):
    """A crab, claws forward (+X), legs splayed to the sides."""
    def shell_shape(p):
        q = p.copy()
        if q.z < 0:
            q.z *= 0.35
        if q.x > 0.4 and q.z > -0.1:  # a notched brow between the eyes
            q.z *= 1.0 - 0.15 * math.cos(q.y * 9.0)
        return q
    add(bm, sphere((0, 0, 0.2), (0.32, 0.42, 0.16), 0, u=20, v=10, shape=shell_shape, bump=0.04, bump_scale=5.0))
    for side in (1, -1):
        for k in range(4):
            a = side * (1.3 + k * 0.32)
            base = Vector((0.24 * math.cos(a) - 0.06, 0.36 * math.sin(a), 0.14))
            out = Vector((math.cos(a), math.sin(a), 0.0))
            knee = base + out * 0.22 + Vector((0, 0, 0.12))
            foot = base + out * 0.44 + Vector((0, 0, -0.14))
            put_tube(bm, [base, knee, foot], [0.04, 0.032, 0.0], 6, 0)
        # Claw: an arm forward to a heavy pincer.
        shoulder = Vector((0.24, side * 0.26, 0.15))
        wrist = Vector((0.48, side * 0.36, 0.16))
        put_tube(bm, [shoulder, (0.36, side * 0.38, 0.2), wrist], [0.05, 0.05, 0.06], 8, 0)
        add(bm, sphere((0.6, side * 0.33, 0.16), (0.13, 0.08, 0.075), 0, u=10, v=8))
        put_tube(bm, [(0.7, side * 0.36, 0.16), (0.8, side * 0.33, 0.17), (0.86, side * 0.28, 0.16)],
                 [0.04, 0.025, 0.0], 6, 1)
        put_tube(bm, [(0.7, side * 0.29, 0.14), (0.79, side * 0.27, 0.13), (0.84, side * 0.24, 0.13)],
                 [0.03, 0.02, 0.0], 6, 1)
        add(bm, sphere((0.3, side * 0.08, 0.3), (0.025, 0.025, 0.025), 2, u=6, v=4))
    paint(bm, lambda u, co, m: grey(1.0) if m == 2 else
          (grey(0.4) if m == 1 else grey(lerp(0.78, 1.0, smooth(0.3, 0.9, u.z)) * (1.0 - 0.15 * smooth(0.2, 0.45, noise.noise(co * 18.0))))))
    return [("skin", None, 0.4), ("claw_tip", (0.25, 0.12, 0.08), 0.3), ("eye", (0.05, 0.05, 0.05), 0.15),
            ("flesh", "flesh", 0.6)]


def _blob_shape(P):
    """Reshapes the unit sphere for the organ and meat families."""
    kind = P.get("kind", "round")
    flat = P.get("flat_base", 0.4)

    def shape(p):
        q = p.copy()
        if kind == "teardrop":  # fillets: wide at the head end, tapering to the tail
            q.y *= 1.0 - 0.55 * smooth(-0.6, 1.0, q.x)
            q.z *= 1.0 - 0.45 * smooth(-0.3, 1.0, q.x)
        elif kind == "bean":
            q.x -= 0.25 * math.exp(-(q.y + 1.0) ** 2 * 3.0) * (1.0 - abs(q.x))
        elif kind == "heart":
            q.x *= 1.0 - 0.45 * smooth(-0.2, 1.0, q.z)
            q.y *= 1.0 - 0.45 * smooth(-0.2, 1.0, q.z)
        elif kind == "lobes":
            q.y *= 1.0 + 0.18 * math.cos(q.x * 4.0)
            q.z *= 1.0 - 0.3 * abs(math.sin(q.x * 2.2))
        elif kind == "block":  # a rounded slab of fat or a roast
            k = max(abs(q.x), abs(q.y), abs(q.z), 1e-6)
            sq = q / k
            q = q.lerp(sq * q.length, P.get("squareness", 0.55))
        elif kind == "tongue":
            q.y *= 1.0 - 0.3 * smooth(0.0, 1.0, q.x)
            q.z *= 0.8 - 0.2 * smooth(0.2, 1.0, q.x)
        elif kind == "sac":  # a roe sac, slightly kinked
            q.y += 0.12 * math.sin(q.x * 2.5)
        if q.z < -flat:
            q.z = -flat + (q.z + flat) * 0.2
        return q
    return shape


def blob(bm, P):
    """Organs and meat cuts: one deformed sphere, with optional vessels,
    fat cap, marbling, flakes, beads or gloss."""
    shape = _blob_shape(P)
    add(bm, sphere((0, 0, 0), (1.0, P.get("width", 0.6), P.get("height", 0.4)), 0,
                   u=P.get("u", 18), v=P.get("v", 10), shape=shape,
                   bump=P.get("bump", 0.04), bump_scale=P.get("bump_scale", 2.5), seed=P.get("seed", 1)))
    for (start, end, r) in P.get("vessels", []):
        put_tube(bm, [start, ((start[0] + end[0]) / 2, (start[1] + end[1]) / 2, (start[2] + end[2]) / 2 + 0.03), end],
                 [r, r * 0.9, r * 0.8], 8, 1)
    for (cx, cy, cz, r) in P.get("bone_ends", []):
        add(bm, sphere((cx, cy, cz), (r * 0.6, r, r), 1, u=10, v=6))
    fat_cap = P.get("fat_cap", 0.0)
    marble = P.get("marble", 0.0)
    flakes = P.get("flakes", 0.0)
    beads = P.get("beads", 0.0)
    mottle = P.get("mottle", 0.0)
    fat_tint = P.get("fat_tint", (1.0, 0.96, 0.9))

    def shade(u, co, m):
        if m:
            return grey(1.0)
        k = Vector((1.0, 1.0, 1.0))
        if fat_cap:
            t = smooth(1.0 - fat_cap, 1.0 - fat_cap * 0.6, u.z)
            k = k.lerp(Vector(fat_tint), t)
        if marble:
            n = abs(noise.noise(co * Vector((6.0, 12.0, 12.0))))
            k = k.lerp(Vector(fat_tint), marble * smooth(0.05, 0.0, n))
        if flakes:
            k *= 1.0 - flakes * smooth(0.6, 0.95, abs(math.sin(co.x * 18.0 + abs(co.y) * 10.0)))
        if beads:
            k *= 1.0 - beads * smooth(0.3, 0.7, noise.noise(co * 40.0) * 0.5 + 0.5)
        if mottle:
            k *= 1.0 - mottle * smooth(0.1, 0.5, noise.noise(co * 6.0))
        k *= lerp(0.85, 1.0, smooth(0.0, 0.7, u.z))
        return tuple(k)

    paint(bm, shade)
    return [("skin", None, P.get("roughness", 0.45)), ("vessel", P.get("vessel_color", (0.85, 0.75, 0.7)), 0.5),
            ("flesh", "flesh", 0.6)]


def twin_blob(bm, P):
    """Two joined chambers: a swim bladder, a two-lobed liver."""
    gap = P.get("gap", 1.1)
    for i, (scale, dz) in enumerate(((1.0, 0.0), (P.get("second", 0.75), 0.0))):
        x = (i - 0.5) * gap
        add(bm, sphere((x, 0, dz), (0.6 * scale, P.get("width", 0.45) * scale, P.get("height", 0.4) * scale), 0,
                       u=14, v=8, bump=P.get("bump", 0.03), seed=i + 3,
                       shape=_blob_shape({"flat_base": P.get("flat_base", 0.5)})))
    put_tube(bm, [(-0.15, 0, 0.0), (0.15, 0, 0.0)], [0.12, 0.12], 8, 0)
    paint(bm, lambda u, co, m: grey(lerp(0.85, 1.0, smooth(0.0, 0.8, u.z)) * (1.0 - P.get("mottle", 0.0) * smooth(0.1, 0.5, noise.noise(co * 6.0)))))
    return [("skin", None, P.get("roughness", 0.3)), ("flesh", "flesh", 0.6)]


def eye(bm, P):
    """An eye: a sphere of sclera with a domed iris and a dark pupil facing +Z."""
    add(bm, sphere((0, 0, 0), (1, 1, 1), 1, u=12, v=8))
    add(bm, sphere((0, 0, 0.55), (0.72, 0.72, 0.5), 0, u=12, v=6))
    paint(bm, lambda u, co, m: grey(0.35) if m == 0 and co.z > 0.98 else grey(1.0))
    return [("skin", None, 0.1), ("sclera", "flesh", 0.3)]


def fish_skin(bm, P):
    outline = ellipse_outline(1.0, P.get("width", 0.4), 28, wobble=0.06, seed=4, tip=0.6)
    add(bm, sheet(outline, 0.02, 0, rings=4, lift=lambda x, y: 0.012 * math.sin(x * 6.0 + y * 4.0)))
    back = P.get("back", 0.4)
    paint(bm, lambda u, co, m: grey((1.0 - back * smooth(0.4, 1.0, u.y))
                                    * (1.0 - 0.08 * abs(math.sin(co.x * 50 + co.y * 40)) * abs(math.sin(co.x * 50 - co.y * 40)))))
    return [("skin", None, 0.3), ("flesh", "flesh", 0.6)]


def hide(bm, P):
    """A flayed hide: a ragged square sheet, fleece up."""
    pts = []
    for s in range(32):
        a = TAU * s / 32
        c, d = math.cos(a), math.sin(a)
        k = max(abs(c), abs(d))
        r = (1.0 / k) ** 0.7 * (1.0 + 0.1 * noise.noise(Vector((c * 2.3, d * 2.3, 0.7))))
        pts.append((c * r, d * r))
    add(bm, sheet(pts, 0.03, 0, rings=5, lift=lambda x, y: 0.01 * noise.noise(Vector((x * 2, y * 2, 0.2))),
                  edge_thin=0.3))
    paint(bm, lambda u, co, m: grey(lerp(0.78, 1.0, smooth(0.3, 1.0, u.z)) * (1.0 - 0.12 * (noise.noise(co * 25.0) * 0.5 + 0.5))))
    return [("skin", None, 0.95), ("flesh", "flesh", 0.7)]


def draped_hide(bm, P):
    """The same hide laid over a pot of rim radius `rim` (m): a taut top that
    slumps over the rim into folds."""
    rim = P.get("rim", 0.093)
    half = P.get("half", 0.11)
    n = 28
    pts = []
    for s in range(n):
        a = TAU * s / n
        c, d = math.cos(a), math.sin(a)
        k = max(abs(c), abs(d))
        pts.append((c / k * half, d / k * half))

    def lift(x, y):
        r = math.hypot(x, y)
        over = max(0.0, r - rim)
        fold = 0.004 * math.sin(math.atan2(y, x) * 9.0) * smooth(0.0, 0.01, over)
        return -over * 1.6 - 0.006 * smooth(0.0, rim, r) ** 2 + fold
    add(bm, sheet(pts, 0.003, 0, rings=7, lift=lift, edge_thin=0.2))
    paint(bm, lambda u, co, m: grey(lerp(0.75, 1.0, u.z) * (1.0 - 0.12 * (noise.noise(co * 400.0) * 0.5 + 0.5))))
    return [("skin", None, 0.95), ("flesh", "flesh", 0.7)]


def bird_skin(bm, P):
    outline = ellipse_outline(1.0, 0.75, 26, wobble=0.18, seed=9)
    add(bm, sheet(outline, 0.02, 0, rings=4, lift=lambda x, y: 0.02 * noise.noise(Vector((x * 3, y * 3, 0.5)))))
    paint(bm, lambda u, co, m: grey(1.0 - 0.1 * smooth(0.55, 0.8, noise.noise(co * 60.0) * 0.5 + 0.5)))
    return [("skin", None, 0.5), ("flesh", "flesh", 0.6)]


def fins(bm, P):
    for i, (x, y, a, l) in enumerate(((0.0, 0.0, 0.2, 1.0), (0.55, 0.45, -0.4, 0.75), (-0.3, 0.6, 0.9, 0.6))):
        pts = fan_outline(1.1, l, 8, base=0.12, ragged=0.08, seed=i)
        add(bm, place(sheet(pts, 0.03, 0, rings=2, edge_thin=0.5),
                      Matrix.Translation((x, y, i * 0.012)) @ Matrix.Rotation(a, 4, "Z")))
    paint(bm, lambda u, co, m: grey(1.0 - 0.18 * smooth(0.6, 0.95, abs(math.sin(math.atan2(co.y, co.x) * 14.0)))))
    return [("skin", None, 0.4), ("flesh", "flesh", 0.6)]


def scales(bm, P):
    """A little drift of shed scales."""
    import random
    rng = random.Random(5)
    for i in range(14):
        x, y = rng.uniform(-1, 1), rng.uniform(-1, 1)
        if x * x + y * y > 1.0:
            x, y = x * 0.7, y * 0.7
        pts = ellipse_outline(0.28, 0.24, 8, wobble=0.1, seed=i)
        add(bm, place(sheet(pts, 0.03, 0, rings=1, edge_thin=0.2),
                      Matrix.Translation((x, y, i * 0.01)) @ Matrix.Rotation(rng.uniform(0, TAU), 4, "Z")))
    paint(bm, lambda u, co, m: grey(lerp(0.85, 1.0, u.z)))
    return [("skin", None, 0.2), ("flesh", "flesh", 0.6)]


def carapace(bm, P):
    """A crab's empty back shell."""
    outline = ellipse_outline(1.0, 0.78, 30, wobble=0.05, seed=2, waves=9, wave_amp=0.03)
    add(bm, sheet(outline, 0.07, 0, rings=5, lift=lambda x, y: 0.35 * (1.0 - min(1.0, x * x + (y / 0.78) ** 2)) ** 0.7,
                  edge_thin=0.4))
    paint(bm, lambda u, co, m: grey(lerp(0.75, 1.0, u.z) * (1.0 - 0.15 * smooth(0.2, 0.45, noise.noise(co * 6.0)))))
    return [("skin", None, 0.4), ("flesh", "flesh", 0.6)]


def frame(bm, P):
    """A fish skeleton: spine, ribs and the tail fan, with flesh scraps."""
    length = 1.0
    rib_len = P.get("rib_len", 0.14)
    ribs = P.get("ribs", 16)
    put_tube(bm, [(0, 0, 0), (length * 0.5, 0, 0), (length * 0.9, 0, 0)], [0.022, 0.02, 0.012], 6, 0)
    for i in range(ribs):
        t = 0.05 + 0.8 * i / (ribs - 1)
        rl = rib_len * (1.0 - 0.6 * t) * (1.0 if t < 0.55 else 0.6)
        for side in (1, -1):
            put_tube(bm, [(t, 0, 0), (t + 0.03, side * rl * 0.6, 0.004), (t + 0.06, side * rl, 0.0)],
                     [0.006, 0.005, 0.0], 3, 0)
    if P.get("tail", True):
        add(bm, place(sheet(fan_outline(1.3, 0.12, 6, base=0.03, fork=0.4), 0.01, 1, rings=2),
                      Matrix.Translation((length * 0.89, 0, 0))))
    paint(bm, lambda u, co, m: grey(1.0 - 0.15 * smooth(0.6, 1.0, noise.noise(co * 30.0) * 0.5 + 0.5)))
    return [("skin", None, 0.4), ("fin", (0.82, 0.82, 0.8), 0.5), ("flesh", "flesh", 0.6)]


def bird_frame(bm, P):
    """A bird's carcass after the cuts: keel, ribs and spine."""
    put_tube(bm, [(-0.5, 0, 0.1), (0.0, 0, 0.08), (0.5, 0, 0.12)], [0.05, 0.06, 0.04], 8, 0)
    put_tube(bm, [(-0.35, 0, 0.12), (0.0, 0, 0.36), (0.35, 0, 0.14)], [0.025, 0.03, 0.02], 4, 0)
    for i in range(7):
        x = -0.36 + i * 0.12
        for side in (1, -1):
            put_tube(bm, [(x, 0, 0.08), (x, side * 0.26, 0.18), (x + 0.03, side * 0.12, 0.32)],
                     [0.018, 0.016, 0.012], 4, 0)
    paint(bm, lambda u, co, m: grey(1.0 - 0.2 * smooth(0.5, 1.0, noise.noise(co * 12.0) * 0.5 + 0.5)))
    return [("skin", None, 0.6), ("flesh", "flesh", 0.6)]


def bone(bm, P):
    """Marrow bones: a pair of sawn shafts showing marrow at each end."""
    for i, y in enumerate((-0.18, 0.2)):
        length = 1.0 if i == 0 else 0.8
        x0 = -0.5 + (0.0 if i == 0 else 0.1)
        def knob(a, k, i=i):
            return 1.0 + 0.08 * math.cos(3 * a + i)
        put_tube(bm, [(x0, y, 0.17), (x0 + length * 0.5, y, 0.16), (x0 + length, y, 0.17)],
                 [0.17, 0.14, 0.17], 12, 0, shape=knob)
        for x in (x0 - 0.002, x0 + length + 0.002):
            add(bm, place(sheet(ellipse_outline(0.1, 0.1, 10), 0.01, 1, rings=1),
                          Matrix.Translation((x, y, 0.17)) @ Matrix.Rotation(math.pi / 2, 4, "Y")))
    paint(bm, lambda u, co, m: grey(1.0) if m else grey(1.0 - 0.12 * smooth(0.3, 0.8, noise.noise(co * 10.0) * 0.5 + 0.5)))
    return [("skin", None, 0.6), ("marrow", "flesh", 0.4), ("flesh", "flesh", 0.6)]


def spine(bm, P):
    """An eel's backbone: a long chain of vertebrae with short spines."""
    n = 30
    pts = [(i / (n - 1), 0.05 * math.sin(i / (n - 1) * TAU * 0.85 + 0.4), 0.0) for i in range(n)]
    put_tube(bm, pts, [0.012] * (n - 1) + [0.0], 6, 0,
             shape=lambda a, i: 1.0 + 0.25 * (i % 2))
    for i in range(2, n - 2, 2):
        x, y, _ = pts[i]
        for side in (1, -1):
            put_tube(bm, [(x, y, 0), (x + 0.01, y + side * 0.03, 0.002), (x + 0.02, y + side * 0.05, 0.0)],
                     [0.004, 0.003, 0.0], 3, 0)
    paint(bm, lambda u, co, m: grey(lerp(0.85, 1.0, u.z)))
    return [("skin", None, 0.45), ("flesh", "flesh", 0.6)]


def horn(bm, P):
    """A ridged ram's horn curling along X, broad at its root."""
    n = 26
    path, radii = [], []
    for i in range(n):
        t = i / (n - 1)
        a = t * TAU * 0.9
        path.append((t, 0.22 * math.sin(a) * (1 - 0.4 * t), 0.22 * (1 - math.cos(a)) * (1 - 0.4 * t)))
        radii.append(0.2 * (1.0 - t) ** 0.8 + 0.01 if i < n - 1 else 0.0)
    put_tube(bm, path, radii, 10, 0, end_mat=None, shape=lambda a, i: 1.0 + 0.06 * (i % 2) + 0.05 * math.cos(3 * a))
    paint(bm, lambda u, co, m: grey(lerp(0.75, 1.0, u.x) * (1.0 - 0.1 * abs(math.sin(u.x * 70.0)))))
    return [("skin", None, 0.55), ("flesh", "flesh", 0.6)]


def hoof(bm, P):
    """A cloven hoof with the pastern above it."""
    for side in (1, -1):
        add(bm, sphere((0.1, side * 0.22, 0.2), (0.45, 0.2, 0.25), 0, u=12, v=8,
                       shape=lambda p: Vector((p.x, p.y, max(p.z, -0.6) * (1.0 - 0.3 * max(0.0, p.x))))))
    put_tube(bm, [(-0.25, 0, 0.3), (-0.4, 0, 0.6), (-0.45, 0, 0.8)], [0.32, 0.26, 0.24], 10, 1, end_mat=2)
    paint(bm, lambda u, co, m: grey(1.0) if m else grey(lerp(0.7, 1.0, u.z)))
    return [("skin", None, 0.35), ("hair", (0.8, 0.72, 0.58), 0.9), ("flesh", "flesh", 0.6)]


def teeth(bm, P):
    """A row of teeth set in a sliver of jaw: needles or molars."""
    count = P.get("count", 5)
    needle = P.get("needle", False)
    box = kit.box_bm(Vector((0, 0, 0.1)), (1.0, 0.35, 0.2), 1, bevel=0.03, segments=1)
    add(bm, box)
    for i in range(count):
        x = -0.4 + 0.8 * i / max(1, count - 1)
        if needle:
            put_tube(bm, [(x, 0, 0.18), (x + 0.02, 0, 0.5), (x + 0.06, 0, 0.9)], [0.05, 0.03, 0.0], 5, 0)
        else:
            add(bm, place(kit.box_bm(Vector((0, 0, 0)), (0.7 / count, 0.3, 0.6), 0, bevel=0.03, segments=1),
                          Matrix.Translation((x, 0, 0.5))))
    paint(bm, lambda u, co, m: grey(lerp(0.85, 1.0, u.z)))
    return [("skin", None, 0.2), ("gum", P.get("gum", (0.75, 0.55, 0.5)), 0.5), ("flesh", "flesh", 0.6)]


def bird_foot(bm, P):
    put_tube(bm, [(-0.5, 0, 0.25), (-0.2, 0, 0.25), (0.0, 0, 0.22)], [0.12, 0.1, 0.1], 6, 0)
    for a in (-0.5, 0.0, 0.5):
        put_tube(bm, [(0.0, 0, 0.2), (0.25 * math.cos(a), 0.25 * math.sin(a), 0.12),
                      (0.5 * math.cos(a), 0.5 * math.sin(a), 0.08)], [0.07, 0.05, 0.0], 5, 0)
    put_tube(bm, [(-0.02, 0, 0.2), (-0.2, 0.05, 0.1), (-0.3, 0.06, 0.06)], [0.05, 0.04, 0.0], 5, 0)
    paint(bm, lambda u, co, m: grey(1.0 - 0.15 * abs(math.sin(co.x * 60.0))))
    return [("skin", None, 0.5), ("flesh", "flesh", 0.6)]


def drumstick(bm, P):
    add(bm, sphere((0.1, 0, 0), (0.6, 0.45, 0.38), 0, u=14, v=8, bump=0.04,
                   shape=lambda p: Vector((p.x, p.y * (1.0 - 0.35 * smooth(-0.2, 1.0, -p.x)), max(p.z, -0.5)))))
    put_tube(bm, [(-0.45, 0, -0.05), (-0.75, 0, 0.0), (-0.85, 0, 0.0)], [0.1, 0.08, 0.1], 8, 1)
    add(bm, sphere((-0.87, 0, 0.0), (0.06, 0.12, 0.12), 1, u=8, v=6))
    paint(bm, lambda u, co, m: grey(1.0) if m else grey(lerp(0.85, 1.0, u.z)))
    return [("skin", None, 0.45), ("bone", (0.92, 0.88, 0.8), 0.5), ("flesh", "flesh", 0.6)]


def meat_chunk(bm, P):
    """Picked crab meat: a loose cluster of flaky lumps."""
    import random
    rng = random.Random(P.get("seed", 3))
    for i in range(P.get("lumps", 6)):
        add(bm, sphere((rng.uniform(-0.5, 0.5), rng.uniform(-0.35, 0.35), rng.uniform(0.05, 0.25)),
                       (rng.uniform(0.25, 0.4), rng.uniform(0.18, 0.28), rng.uniform(0.12, 0.22)), 0,
                       u=8, v=6, bump=0.12, bump_scale=3.0, seed=i))
    streak = P.get("streak", (1.0, 1.0, 1.0))
    paint(bm, lambda u, co, m: tuple(Vector((1.0, 1.0, 1.0)).lerp(Vector(streak), smooth(0.55, 0.9, u.z))
                                     * (1.0 - 0.1 * abs(math.sin(co.x * 40.0)))))
    return [("skin", None, 0.55), ("flesh", "flesh", 0.6)]


# --- the garden ---

def leaf(bm, P):
    """A broad leaf with a midrib, side veins and a crinkled or waved edge."""
    outline = ellipse_outline(1.0, P.get("width", 0.6), 32, wobble=P.get("wobble", 0.05), seed=P.get("seed", 1),
                              tip=P.get("tip", 0.3), waves=P.get("waves", 0), wave_amp=P.get("wave_amp", 0.0),
                              notch=P.get("notch", 0.0))
    crinkle = P.get("crinkle", 0.02)
    cup = P.get("cup", 0.05)
    add(bm, sheet(outline, 0.012, 0, rings=5,
                  lift=lambda x, y: cup * (x * x + y * y) + crinkle * noise.noise(Vector((x * 5, y * 5, 0.3))),
                  edge_thin=0.3))
    if P.get("stem", True):
        put_tube(bm, [(-1.0, 0, 0.0), (-1.18, 0, -0.004), (-1.28, 0, -0.006)], [0.025, 0.022, 0.02], 5, 1)
    vein = P.get("veins", 0.18)

    def shade(u, co, m):
        if m:
            return grey(1.0)
        y = co.y / max(P.get("width", 0.6), 1e-6)
        mid = smooth(0.06, 0.0, abs(y)) * 0.5
        side = smooth(0.9, 1.0, abs(math.sin((co.x - abs(y) * 0.6) * 9.0)))
        k = 1.0 - vein * side * (1.0 - abs(y))
        return tuple(Vector(grey(k)).lerp(Vector(P.get("rib_tint", (1.0, 1.0, 0.85))), mid))

    paint(bm, shade)
    return [("skin", None, 0.55), ("stem", P.get("stem_color", (0.55, 0.7, 0.4)), 0.6), ("flesh", "flesh", 0.6)]


def kelp(bm, P):
    """A long kelp blade with ruffled edges, and round gas bladders along its
    midrib if it has them."""
    width = P.get("width", 0.32)
    outline = ellipse_outline(1.0, width, 40, wobble=0.04, seed=6, tip=0.7, waves=14, wave_amp=P.get("ruffle", 0.04))
    add(bm, sheet(outline, 0.012, 0, rings=4,
                  lift=lambda x, y: 0.03 * math.sin(x * 9.0) * (abs(y) / width) ** 2, edge_thin=0.3))
    put_tube(bm, [(-1.0, 0, 0.0), (-1.15, 0, 0.0)], [0.03, 0.025], 5, 1)
    for i in range(P.get("bladders", 0)):
        x = -0.7 + i * 1.4 / max(1, P.get("bladders", 1) - 1)
        r = P.get("bladder_size", 0.07) * (1.0 - 0.3 * abs(x))
        add(bm, sphere((x, 0.0, r * 0.4), (r, r, r * 0.9), 1, u=8, v=6))
    paint(bm, lambda u, co, m: grey(1.0) if m else grey(lerp(1.0, 0.8, smooth(0.0, 1.0, abs(u.y - 0.5) * 2.0))))
    return [("skin", None, 0.25), ("bladder", P.get("bladder_color", (0.6, 0.65, 0.3)), 0.2), ("flesh", "flesh", 0.6)]


def frond(bm, P):
    """A branching strap of wrack."""
    branches = [((-1.0, 0.0), (0.1, 0.0), 0.12), ((0.0, 0.0), (1.0, 0.45), 0.09), ((0.0, 0.0), (1.0, -0.35), 0.09),
                ((0.4, 0.17), (0.8, 0.75), 0.06)]
    for i, ((x0, y0), (x1, y1), w) in enumerate(branches):
        dx, dy = x1 - x0, y1 - y0
        length = math.hypot(dx, dy)
        pts = ellipse_outline(length * 0.55, w, 14, wobble=0.08, seed=i, tip=0.4)
        add(bm, place(sheet(pts, 0.02, 0, rings=2, edge_thin=0.3),
                      Matrix.Translation(((x0 + x1) / 2, (y0 + y1) / 2, i * 0.004)) @ Matrix.Rotation(math.atan2(dy, dx), 4, "Z")))
    paint(bm, lambda u, co, m: grey(1.0 - 0.25 * smooth(0.6, 0.95, noise.noise(co * 9.0) * 0.5 + 0.5)))
    return [("skin", None, 0.3), ("flesh", "flesh", 0.6)]


def sprig(bm, P):
    """A herb sprig: a stem with paired leaves."""
    put_tube(bm, [(-1.0, 0, 0.0), (0.0, 0.03, 0.0), (0.9, 0.0, 0.0)], [0.025, 0.02, 0.012], 5, 1)
    for i in range(6):
        x = -0.6 + i * 0.28
        size = 0.35 * (1.0 - 0.1 * i)
        for side in (1, -1):
            pts = ellipse_outline(size, size * 0.45, 10, tip=0.5, seed=i)
            add(bm, place(sheet(pts, 0.02, 0, rings=2, edge_thin=0.3),
                          Matrix.Translation((x + size * 0.4, side * size * 0.7, 0.01))
                          @ Matrix.Rotation(side * 0.9, 4, "Z")))
    paint(bm, lambda u, co, m: grey(1.0) if m else grey(lerp(0.85, 1.0, abs(math.sin(co.x * 9.0)))))
    return [("skin", None, 0.6), ("stem", (0.5, 0.62, 0.35), 0.6), ("flesh", "flesh", 0.6)]


def taproot(bm, P):
    """A carrot-like taproot with ring grooves and a green crown."""
    n = 14
    path = [(i / (n - 1), 0.02 * math.sin(i * 0.7), 0.0) for i in range(n)]
    radii = [0.13 * (1.0 - (i / (n - 1)) ** 1.3) ** 0.7 + (0.0 if i == n - 1 else 0.004) for i in range(n)]
    radii[-1] = 0.0
    put_tube(bm, path, radii, 10, 0, shape=lambda a, i: 1.0 + 0.03 * (i % 2))
    for a in (-0.4, 0.0, 0.4):
        put_tube(bm, [(0.0, 0, 0.0), (-0.12, 0.06 * math.sin(a * 3), 0.03), (-0.22, 0.12 * a, 0.05)],
                 [0.03, 0.022, 0.0], 5, 1)
    paint(bm, lambda u, co, m: grey(1.0) if m else grey(1.0 - 0.15 * smooth(0.8, 1.0, abs(math.sin(co.x * 60.0)))))
    return [("skin", None, 0.6), ("stem", (0.4, 0.6, 0.3), 0.6), ("flesh", "flesh", 0.6)]


def root(bm, P):
    """A gnarled root, knuckled and barked, with a couple of rootlets."""
    n = 14
    path = [(i / (n - 1), 0.05 * math.sin(i * 1.3), 0.02 * math.sin(i * 0.9)) for i in range(n)]
    radii = [0.11 * (1.0 - 0.6 * i / (n - 1)) for i in range(n)]
    radii[-1] = 0.0
    put_tube(bm, path, radii, 9, 0, shape=lambda a, i: 1.0 + 0.12 * noise.noise(Vector((a, i * 0.7, 0.4))))
    put_tube(bm, [(0.3, 0.05, 0.0), (0.42, 0.15, -0.01), (0.55, 0.2, -0.02)], [0.04, 0.03, 0.0], 5, 0)
    put_tube(bm, [(0.6, -0.03, 0.0), (0.7, -0.13, 0.0), (0.82, -0.17, -0.01)], [0.035, 0.025, 0.0], 5, 0)
    paint(bm, lambda u, co, m: grey(1.0 - 0.25 * smooth(0.55, 0.9, abs(math.sin(co.x * 70.0 + noise.noise(co * 8.0) * 3.0)))))
    return [("skin", None, 0.85), ("flesh", "flesh", 0.6)]


def rhizome(bm, P):
    """A lotus-like rhizome: swollen links joined at narrow nodes."""
    links = P.get("links", 3)
    n = links * 6 + 1
    path = [(i / (n - 1), 0.0, 0.0) for i in range(n)]
    radii = []
    for i in range(n):
        phase = (i % 6) / 6.0
        radii.append(0.13 * (0.55 + 0.45 * math.sin(phase * math.pi)) if 0 < i < n - 1 else 0.07)
    put_tube(bm, path, radii, 12, 0, shape=lambda a, i: 1.0 + 0.03 * math.cos(5 * a + i))
    paint(bm, lambda u, co, m: grey(lerp(0.85, 1.0, u.z) * (1.0 - 0.15 * smooth(0.05, 0.0, abs(math.sin(co.x * math.pi * 3.0))))))
    return [("skin", None, 0.6), ("flesh", "flesh", 0.6)]


def leek(bm, P):
    """A leek: white shank to green leaves, with a root tuft."""
    put_tube(bm, [(0.0, 0, 0.0), (0.4, 0, 0.0), (0.62, 0, 0.0)], [0.06, 0.058, 0.055], 10, 0)
    for i, a in enumerate((-0.25, 0.0, 0.3)):
        pts = ellipse_outline(0.22, 0.05, 10, tip=0.6, seed=i)
        add(bm, place(sheet(pts, 0.015, 1, rings=2),
                      Matrix.Translation((0.82, a * 0.18, 0.02 + i * 0.005)) @ Matrix.Rotation(a, 4, "Z")))
    for a in range(5):
        ang = (a - 2) * 0.35
        put_tube(bm, [(0.0, 0, 0), (-0.05, 0.04 * math.sin(ang), 0.0), (-0.09, 0.07 * math.sin(ang), -0.01)],
                 [0.012, 0.008, 0.0], 4, 2)
    paint(bm, lambda u, co, m: grey(1.0) if m else
          tuple(Vector((1.0, 1.0, 1.0)).lerp(Vector((0.55, 0.85, 0.5)), smooth(0.25, 0.7, u.x))))
    return [("skin", None, 0.4), ("leaf", (0.35, 0.55, 0.3), 0.5), ("root", (0.9, 0.86, 0.75), 0.8),
            ("flesh", "flesh", 0.6)]


def mushroom(bm, P):
    """An upright mushroom: a cap on a stout stem."""
    cap_r = 0.5
    rise = P.get("rise", 0.32)
    rim = 0.12
    profile = [(0.0, rim + rise + 0.05), (cap_r * 0.5, rim + rise * 0.85), (cap_r * 0.88, rim + rise * 0.45),
               (cap_r, rim + 0.05), (cap_r * 0.95, rim), (cap_r * 0.5, rim + 0.06), (0.0, rim + 0.08)]
    profile = [(r, z + P.get("stem", 0.35)) for r, z in profile]
    sub = bmesh.new()
    kit.lathe(sub, list(reversed(profile)), 20, 0, shape=lambda p, a, i: p * bumpy(p, 4.0, P.get("lumpy", 0.03), 4))
    for f in sub.faces:
        c = f.calc_center_median()
        if c.z < P.get("stem", 0.35) + rim + 0.075 and math.hypot(c.x, c.y) < cap_r * 0.9:
            f.material_index = 1
    add(bm, sub)
    put_tube(bm, [(0, 0, 0.0), (0, 0, P.get("stem", 0.35) * 0.6), (0, 0, P.get("stem", 0.35) + rim + 0.05)],
             [P.get("stem_r", 0.13), P.get("stem_r", 0.13) * 0.9, P.get("stem_r", 0.13) * 0.8], 10, 2)
    spots = P.get("spots", 0.0)
    crack = P.get("cracks", 0.0)

    def shade(u, co, m):
        if m:
            return grey(1.0)
        k = lerp(0.85, 1.0, smooth(0.5, 1.0, u.z))
        if spots:
            k = lerp(k, 1.0, spots * smooth(0.3, 0.5, noise.noise(co * 14.0)))
            k *= 1.0 - spots * 0.3 * smooth(0.5, 0.3, noise.noise(co * 14.0))
        if crack:
            k *= 1.0 - crack * smooth(0.05, 0.0, abs(noise.noise(co * 9.0)))
        return grey(k)

    paint(bm, shade)
    return [("skin", None, 0.6), ("gills", P.get("gill_color", (0.85, 0.8, 0.72)), 0.7),
            ("stem", P.get("stem_color", (0.9, 0.88, 0.82)), 0.7), ("flesh", "flesh", 0.6)]


def berry(bm, P):
    add(bm, sphere((0, 0, 0.5), (0.5, 0.5, 0.48), 0, u=10, v=7))
    for k in range(5):
        a = TAU * k / 5
        put_tube(bm, [(0.04 * math.cos(a), 0.04 * math.sin(a), 0.95), (0.12 * math.cos(a), 0.12 * math.sin(a), 1.02)],
                 [0.03, 0.0], 3, 1)
    paint(bm, lambda u, co, m: grey(1.0) if m else grey(lerp(0.7, 1.0, u.z)))
    return [("skin", None, 0.35), ("crown", (0.3, 0.2, 0.2), 0.7), ("flesh", "flesh", 0.6)]


def clam(bm, P):
    """A closed clam: two ribbed valves meeting at a lip, the hinge at -X."""
    def valves(p):
        q = p.copy()
        a = math.atan2(q.y, q.x)
        q *= 1.0 + 0.035 * math.cos(a * 18.0) * (1.0 - abs(q.z))
        q.x *= 1.0 - 0.15 * max(0.0, -q.x) * abs(q.z)
        return q
    add(bm, sphere((0, 0, 0.3), (0.5, 0.4, 0.3), 0, u=24, v=10, shape=valves))
    add(bm, sphere((-0.44, 0, 0.4), (0.08, 0.1, 0.08), 0, u=8, v=6))

    def shade(u, co, m):
        d = math.hypot(co.x + 0.45, co.y)
        k = 1.0 - 0.18 * smooth(0.5, 1.0, math.sin(d * 40.0) * 0.5 + 0.5)
        k *= 1.0 - 0.45 * smooth(0.04, 0.0, abs(co.z - 0.3))  # the dark lip where the valves meet
        return grey(k)

    paint(bm, shade)
    return [("skin", None, 0.35), ("flesh", "flesh", 0.6)]


# --- grains and spices: tiny, instanced hundreds of times ---

def grain_flake(bm, P):
    pts = ellipse_outline(1.0, 0.7, 7, wobble=0.12, seed=P.get("seed", 1))
    add(bm, sheet(pts, 0.2, 0, rings=1, lift=lambda x, y: 0.12 * (x * x), edge_thin=0.4))
    paint(bm, lambda u, co, m: grey(lerp(0.85, 1.0, u.z)))
    return [("skin", None, 0.8)]


def grain_round(bm, P):
    add(bm, sphere((0, 0, 0.5), (0.5, 0.5, 0.5), 0, u=6, v=4, bump=P.get("wrinkle", 0.0), bump_scale=6.0))
    paint(bm, lambda u, co, m: grey(lerp(0.8, 1.0, u.z)))
    return [("skin", None, 0.6)]


def grain_kernel(bm, P):
    tube(bm, [(0, 0, 0), (0.25, 0, 0), (0.6, 0, 0), (0.88, 0, 0), (1.0, 0, 0)],
         [0.0, (0.3, 0.32), (0.4, 0.4), (0.3, 0.28), 0.0], 5, 0, up=(0, 0, 1))
    paint(bm, lambda u, co, m: grey(lerp(0.82, 1.0, u.z)))
    return [("skin", None, 0.6)]


def grain_bean(bm, P):
    add(bm, sphere((0, 0, 0.5), (0.5, 0.35, 0.32), 0, u=6, v=4,
                   shape=lambda p: Vector((p.x, p.y - 0.18 * (1 - abs(p.x)) * (p.y < 0), p.z))))
    paint(bm, lambda u, co, m: grey(0.55) if co.y < -0.12 and abs(co.x) < 0.08 else grey(lerp(0.85, 1.0, u.z)))
    return [("skin", None, 0.5)]


def crystal(bm, P):
    add(bm, place(kit.box_bm(Vector((0, 0, 0)), (1.0, 0.9, 0.8), 0),
                  Matrix.Translation((0, 0, 0.4)) @ Matrix.Rotation(0.3, 4, "Z") @ Matrix.Rotation(0.2, 4, "X")))
    paint(bm, lambda u, co, m: grey(lerp(0.85, 1.0, u.z)))
    return [("skin", None, 0.15)]


def fleck(bm, P):
    add(bm, sphere((0, 0, 0.5), (0.5, 0.45, 0.4), 0, u=5, v=3, bump=0.35, bump_scale=3.0, seed=P.get("seed", 2)))
    paint(bm, lambda u, co, m: grey(lerp(0.8, 1.0, u.z)))
    return [("skin", None, 0.8)]


def spice_flake(bm, P):
    pts = [(0.0, 0.0), (1.0, 0.25), (0.7, 0.9), (0.15, 0.7)]
    add(bm, sheet(pts, 0.15, 0, rings=1, lift=lambda x, y: 0.15 * x * y, edge_thin=0.0))
    paint(bm, lambda u, co, m: grey(lerp(0.75, 1.0, u.x)))
    return [("skin", None, 0.5)]


def bark_curl(bm, P):
    path = [(t / 4.0, 0.25 * math.sin(t * 0.9), 0.25 * (1 - math.cos(t * 0.9))) for t in range(5)]
    tube(bm, path, [(0.12, 0.05)] * 5, 3, 0, up=(0, 0, 1))
    paint(bm, lambda u, co, m: grey(lerp(0.7, 1.0, u.z)))
    return [("skin", None, 0.85)]


FAMILIES = {f.__name__: f for f in (
    fish, fish_head, eel, eel_head, bird, crab, blob, twin_blob, eye, fish_skin, hide, draped_hide, bird_skin, fins,
    scales, carapace, frame, bird_frame, bone, spine, horn, hoof, teeth, bird_foot, drumstick, meat_chunk,
    leaf, kelp, frond, sprig, taproot, root, rhizome, leek, mushroom, berry, clam,
    grain_flake, grain_round, grain_kernel, grain_bean, crystal, fleck, spice_flake, bark_curl)}

# Families small enough to be drawn hundreds of times in a heap.
KERNELS = {"grain_flake", "grain_round", "grain_kernel", "grain_bean", "crystal", "fleck", "spice_flake", "bark_curl"}


# --------------------------------------------------------------------------
# The larder: ingredient id -> (family, shape parameters)
# --------------------------------------------------------------------------

BREAM = {"depth": 0.42, "thick": 0.2, "back": 0.5, "fork": 0.5, "fin_color": (0.78, 0.82, 0.86)}
CARP = {"depth": 0.34, "thick": 0.2, "back": 0.45, "fork": 0.15, "tail_len": 0.32, "tail_spread": 1.9,
        "tail_ragged": 0.18, "stripes": 0, "barbels": [(0.07, -0.02)], "fin_color": (0.9, 0.85, 0.7),
        "profile": [0.0, 0.55, 0.8, 0.94, 1.0, 0.97, 0.86, 0.66, 0.42, 0.26, 0.2]}
EEL = {"radius": 0.035, "curve": 0.07, "spots": 0.7}

SPECS = {
    # The garden.
    "cliff_garden_herb": ("sprig", {}),
    "driftwood_ember_root": ("root", {}),
    "bog_lotus_root": ("rhizome", {"links": 3}),
    "cliff_carrot": ("taproot", {}),
    "frostcap": ("mushroom", {"rise": 0.4, "spots": 0.6, "stem": 0.32, "gill_color": (0.9, 0.95, 0.98),
                              "stem_color": (0.93, 0.95, 0.97)}),
    "stonecap": ("mushroom", {"rise": 0.22, "cracks": 0.5, "stem": 0.25, "stem_r": 0.16, "lumpy": 0.06,
                              "gill_color": (0.75, 0.7, 0.62), "stem_color": (0.8, 0.76, 0.68)}),
    "heathberry": ("berry", {}),
    "lanternwrack": ("frond", {}),
    "mirewort": ("leaf", {"width": 0.7, "notch": 0.6, "tip": 0.1, "crinkle": 0.02, "cup": 0.04,
                          "stem_color": (0.35, 0.5, 0.3)}),
    "sea_cabbage_leaf": ("leaf", {"width": 0.92, "tip": 0.0, "crinkle": 0.035, "waves": 11, "wave_amp": 0.05,
                                  "cup": 0.03, "veins": 0.22, "stem_color": (0.6, 0.75, 0.55)}),
    "skybladder_kelp": ("kelp", {"width": 0.3, "bladders": 4, "bladder_size": 0.085, "ruffle": 0.03}),
    "sea_kelp": ("kelp", {"width": 0.32, "ruffle": 0.05}),
    "tide_leek": ("leek", {}),
    "tide_pool_clam": ("clam", {}),
    # Grains.
    "cliff_oats": ("grain_flake", {}),
    "ember_millet": ("grain_round", {}),
    "mirebean": ("grain_bean", {}),
    "moonbarley": ("grain_kernel", {}),
    # Spices.
    "ashsalt": ("crystal", {}),
    "tidewater_salt": ("crystal", {}),
    "cliff_pepper": ("grain_round", {"wrinkle": 0.15}),
    "ember_flakes": ("spice_flake", {}),
    "frost_mint": ("spice_flake", {}),
    "bog_myrtle": ("spice_flake", {}),
    "heath_thyme": ("spice_flake", {}),
    "galeseed": ("grain_kernel", {}),
    "kelp_dust": ("fleck", {"seed": 4}),
    "lantern_spore": ("grain_round", {}),
    "moonbark": ("bark_curl", {}),
    # Driftback bream.
    "driftback_bream_whole": ("fish", BREAM),
    "driftback_bream_head": ("fish_head", BREAM),
    "driftback_bream_fillet": ("blob", {"kind": "teardrop", "width": 0.42, "height": 0.16, "flakes": 0.08,
                                        "flat_base": 0.2, "bump": 0.02}),
    "driftback_bream_belly": ("blob", {"kind": "teardrop", "width": 0.42, "height": 0.12, "fat_cap": 0.0,
                                       "marble": 0.3, "flat_base": 0.2, "bump": 0.02}),
    "driftback_bream_eye": ("eye", {}),
    "driftback_bream_fins": ("fins", {}),
    "driftback_bream_frame": ("frame", {}),
    "driftback_bream_liver": ("twin_blob", {"second": 0.7, "flat_base": 0.3, "mottle": 0.1}),
    "driftback_bream_roe": ("blob", {"kind": "sac", "width": 0.45, "height": 0.35, "beads": 0.25, "roughness": 0.25}),
    "driftback_bream_skin": ("fish_skin", {"width": 0.38, "back": 0.45}),
    # Fogtail carp.
    "fogtail_carp_whole": ("fish", CARP),
    "fogtail_carp_head": ("fish_head", CARP),
    "fogtail_carp_fillet": ("blob", {"kind": "teardrop", "width": 0.4, "height": 0.18, "flakes": 0.08,
                                     "flat_base": 0.2, "bump": 0.02}),
    "fogtail_carp_eye": ("eye", {}),
    "fogtail_carp_frame": ("frame", {}),
    "fogtail_carp_liver": ("twin_blob", {"second": 0.8, "flat_base": 0.3, "mottle": 0.12}),
    "fogtail_carp_roe": ("blob", {"kind": "sac", "width": 0.45, "height": 0.35, "beads": 0.3, "roughness": 0.25}),
    "fogtail_carp_scales": ("scales", {}),
    "fogtail_carp_skin": ("fish_skin", {"width": 0.38, "back": 0.35}),
    "fogtail_carp_swim_bladder": ("twin_blob", {"second": 0.65, "gap": 1.2, "width": 0.42, "height": 0.42,
                                                "roughness": 0.15}),
    # Lantern eel.
    "lantern_eel_whole": ("eel", EEL),
    "lantern_eel_head": ("eel_head", dict(EEL, upto=0.16)),
    "lantern_eel_fillet": ("blob", {"kind": "teardrop", "width": 0.18, "height": 0.09, "flakes": 0.06,
                                    "flat_base": 0.2, "bump": 0.015}),
    "lantern_eel_bones": ("spine", {}),
    "lantern_eel_eye": ("eye", {}),
    "lantern_eel_liver": ("blob", {"kind": "lobes", "width": 0.4, "height": 0.2, "mottle": 0.1, "roughness": 0.25}),
    "lantern_eel_skin": ("fish_skin", {"width": 0.12, "back": 0.2}),
    "lantern_eel_teeth": ("teeth", {"needle": True, "count": 7, "gum": (0.6, 0.65, 0.7)}),
    # Heath grouse.
    "heath_grouse_whole": ("bird", {}),
    "heath_grouse_breast": ("blob", {"kind": "teardrop", "width": 0.55, "height": 0.3, "flat_base": 0.3}),
    "heath_grouse_thigh": ("drumstick", {}),
    "heath_grouse_carcass": ("bird_frame", {}),
    "heath_grouse_eye": ("eye", {}),
    "heath_grouse_foot": ("bird_foot", {}),
    "heath_grouse_gizzard": ("blob", {"kind": "round", "width": 0.85, "height": 0.6, "fat_cap": 0.25,
                                      "fat_tint": (1.0, 1.0, 1.0), "roughness": 0.3}),
    "heath_grouse_heart": ("blob", {"kind": "heart", "width": 0.8, "height": 0.8, "flat_base": 0.6,
                                    "vessels": [((0.1, 0.0, 0.7), (0.25, 0.1, 0.95), 0.1)]}),
    "heath_grouse_liver": ("twin_blob", {"second": 0.8, "flat_base": 0.3, "roughness": 0.25}),
    "heath_grouse_skin": ("bird_skin", {}),
    # Cinder crab.
    "cinder_crab_whole": ("crab", {}),
    "cinder_crab_shell": ("carapace", {}),
    "cinder_crab_body_meat": ("meat_chunk", {"lumps": 7}),
    "cinder_crab_claw_meat": ("meat_chunk", {"lumps": 4, "seed": 8, "streak": (1.0, 0.6, 0.5)}),
    "cinder_crab_coral": ("blob", {"kind": "lobes", "width": 0.7, "height": 0.35, "beads": 0.2, "bump": 0.08}),
    "cinder_crab_tomalley": ("blob", {"kind": "round", "width": 0.7, "height": 0.35, "mottle": 0.15, "bump": 0.07}),
    # Gale ram, dressed in the field.
    "gale_ram_loin": ("blob", {"kind": "block", "width": 0.4, "height": 0.26, "fat_cap": 0.3, "marble": 0.5,
                               "flat_base": 0.8, "squareness": 0.6}),
    "gale_ram_shoulder": ("blob", {"kind": "block", "width": 0.68, "height": 0.34, "fat_cap": 0.22, "marble": 0.6,
                                   "flat_base": 0.7, "squareness": 0.35, "bump": 0.07,
                                   "bone_ends": [(-0.98, 0.15, 0.05, 0.12)], "vessel_color": (0.95, 0.9, 0.82)}),
    "gale_ram_tallow": ("blob", {"kind": "block", "width": 0.8, "height": 0.4, "squareness": 0.4, "bump": 0.09,
                                 "bump_scale": 3.5, "flat_base": 0.7, "mottle": 0.08, "roughness": 0.6}),
    "gale_ram_liver": ("blob", {"kind": "lobes", "width": 0.6, "height": 0.2, "flat_base": 0.3, "roughness": 0.2}),
    "gale_ram_kidney": ("blob", {"kind": "bean", "width": 0.65, "height": 0.5, "roughness": 0.25}),
    "gale_ram_heart": ("blob", {"kind": "heart", "width": 0.66, "height": 0.66, "flat_base": 0.6, "fat_cap": 0.2,
                                "vessels": [((0.1, 0.0, 0.6), (0.2, 0.1, 0.85), 0.12),
                                            ((-0.15, 0.1, 0.58), (-0.3, 0.15, 0.8), 0.09)]}),
    "gale_ram_tongue": ("blob", {"kind": "tongue", "width": 0.42, "height": 0.26, "mottle": 0.08, "bump": 0.02}),
    "gale_ram_eye": ("eye", {}),
    "gale_ram_hide": ("hide", {}),
    "gale_ram_hide_draped": ("draped_hide", {}),
    "gale_ram_hoof": ("hoof", {}),
    "gale_ram_horn": ("horn", {}),
    "gale_ram_marrow_bones": ("bone", {}),
    "gale_ram_teeth": ("teeth", {"count": 3}),
}

# Models that are a second look of an ingredient, not an ingredient themselves:
# id -> (ingredient whose data they take, Blender size override in metres or None).
VARIANTS = {
    # The hide as it lies taut over the pot: as wide as the pot's rim plus the
    # overhang, slumping 0.05 m down its sides.
    "gale_ram_hide_draped": ("gale_ram_hide", (0.22, 0.22, 0.05)),
}


def budget(family):
    if family in KERNELS:
        return (4, 40)
    if family in ("fish", "eel", "bird", "crab"):
        return (400, 3000)
    return (20, 2000)


def source_of(model_id):
    return VARIANTS[model_id][0] if model_id in VARIANTS else model_id


def model_size(model_id):
    if model_id in VARIANTS and VARIANTS[model_id][1]:
        return VARIANTS[model_id][1]
    return read_ingredient(source_of(model_id))["size"]


def model_glb(model_id):
    if model_id in VARIANTS:
        base = glb_path(source_of(model_id))
        return base.replace(source_of(model_id) + ".glb", model_id + ".glb")
    return glb_path(model_id)


def build(model_id):
    family, params = SPECS[model_id]
    data = read_ingredient(source_of(model_id))
    kit.reset()
    bm = bmesh.new()
    slots = FAMILIES[family](bm, params)
    # Paint lives in a vertex layer; fitting keeps it.
    size = model_size(model_id)
    kit.fit_to_box(bm, size)
    mats = []
    for name, colour, roughness in slots:
        rgb = data["tint"] if colour is None else data["flesh"] if colour == "flesh" else colour
        mats.append(mat_rgb(name, rgb, roughness=roughness))
    small = family in KERNELS
    obj = kit.mesh_object(model_id, bm, mats, smooth_angle=180 if small else 50, uv=None if small else "smart")
    obj.data.color_attributes.active_color = obj.data.color_attributes["Color"]
    os.makedirs(os.path.join(kit.BLEND_DIR, "larder"), exist_ok=True)
    kit.save(os.path.join("larder", model_id), model_glb(model_id), vertex_colors=True)


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or list(SPECS)
    unknown = [n for n in names if n not in SPECS]
    if unknown:
        raise SystemExit(f"unknown model(s): {', '.join(unknown)}")
    for name in names:
        build(name)


if __name__ == "__main__":
    main()
