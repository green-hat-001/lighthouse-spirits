"""Build the Lighthouse Spirits model kit described in docs/models_needed.md.

    blender --background --factory-startup --python tools/blender/build_models.py [-- name ...]

Each model is written to models/<name>.blend (the editable source) and exported
to its .glb path under assets/models/. With no names, every model is rebuilt.
"""

import math
import os
import sys

import bmesh
import bpy
import numpy
from mathutils import Matrix, Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import bumpy, box, cylinder, disc, empty, lathe, material, mesh_object, tube  # noqa: E402

TAU = 2.0 * math.pi


# --------------------------------------------------------------------------
# Section 1: food state model
# --------------------------------------------------------------------------

def potato():
    kit.reset()
    skin = material("skin", "#a4805a", roughness=0.9)
    flesh = material("flesh", "#efe4c2", roughness=0.7)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
    eyes = [Vector(d).normalized() for d in ((0.8, 0.4, 0.3), (-0.6, -0.5, 0.4), (0.1, 0.7, 0.6),
                                             (-0.9, 0.3, -0.1), (0.4, -0.8, 0.2), (0.95, -0.2, -0.2))]
    for v in bm.verts:
        p = v.co.copy()
        p *= bumpy(p, 1.4, 0.09, 1) * bumpy(p, 3.2, 0.035, 2)
        if p.z < -0.5:  # rests on its flattest side
            p.z = -0.5 + (p.z + 0.5) * 0.35
        v.co = p
    for eye in eyes:
        nearest = max(bm.verts, key=lambda v: v.co.normalized().dot(eye))
        nearest.co *= 0.93
    kit.fit_to_box(bm, (0.090, 0.055, 0.045))
    for f in bm.faces:
        f.material_index = 0
    mesh_object("potato", bm, [skin, flesh], smooth_angle=180)
    kit.save("potato", "assets/models/ingredients/potato.glb")


def chilli():
    kit.reset()
    skin = material("skin", "#c0281e", roughness=0.3)
    stem = material("stem", "#4f7a2c", roughness=0.7)
    flesh = material("flesh", "#e0584a", roughness=0.6)
    bm = bmesh.new()
    stations = 13
    path, radii = [Vector((-0.001, 0, 0))], [0.0]
    for i in range(stations):
        t = i / (stations - 1)
        x = 0.002 + t * 0.060
        path.append(Vector((x, 0.0035 * t * t, -0.0015 * t * t)))
        shoulder = min(1.0, 0.8 + t * 3.0)
        radii.append(0.0078 * shoulder * (1.0 - t ** 1.7) ** 0.55 if t < 1 else 0.0)
    radii[-1] = 0.0
    tube(bm, path, radii, 8, 0, shape=lambda a, i: 1.0 + 0.07 * math.cos(3 * a))
    # calyx: a short flared cup gripping the shoulder
    tube(bm, [(-0.0015, 0, 0), (0.0015, 0, 0), (0.0045, 0, 0)], [0.0055, 0.0082, 0.0074], 8, 1,
         shape=lambda a, i: 1.0 + (0.12 * math.cos(5 * a) if i == 2 else 0.0))
    tube(bm, [(-0.001, 0, 0), (-0.006, 0, 0.0006), (-0.0095, 0, 0.0020), (-0.0115, 0, 0.0040)],
         [0.0017, 0.0015, 0.0014, 0.0013], 6, 1)
    kit.fit_to_box(bm, (0.070, 0.018, 0.018))
    mesh_object("chilli", bm, [skin, stem, flesh], smooth_angle=60)
    kit.save("chilli", "assets/models/ingredients/chilli.glb")


def _seed_disc_image():
    """Dark disc with lighter florets laid on Vogel's golden-angle spiral."""
    size = 256
    yy, xx = numpy.mgrid[0:size, 0:size].astype(numpy.float32)
    u = (xx + 0.5) / size * 2 - 1
    v = (yy + 0.5) / size * 2 - 1
    base = numpy.array(kit.srgb("#3a2413"), numpy.float32)
    light = numpy.array(kit.srgb("#8a6438"), numpy.float32)
    mask = numpy.zeros((size, size), numpy.float32)
    golden = math.pi * (3 - math.sqrt(5))
    count = 520
    for n in range(1, count):
        r = math.sqrt(n / count) * 0.98
        a = n * golden
        cx, cy = r * math.cos(a), r * math.sin(a)
        rad = 0.022 + 0.018 * r
        d2 = (u - cx) ** 2 + (v - cy) ** 2
        mask = numpy.maximum(mask, numpy.clip(1.0 - d2 / (rad * rad), 0, 1) * (0.35 + 0.65 * r))
    rgb = base[None, None, :] * (1 - mask[..., None]) + light[None, None, :] * mask[..., None]
    rgba = numpy.concatenate([rgb, numpy.ones((size, size, 1), numpy.float32)], axis=2)
    img = bpy.data.images.new("sunflower_seed_disc", size, size, alpha=False)
    img.colorspace_settings.name = "sRGB"
    # pixels are stored in scene-linear order but an sRGB image expects encoded values
    encoded = numpy.where(rgba <= 0.0031308, rgba * 12.92, 1.055 * numpy.power(rgba, 1 / 2.4) - 0.055)
    encoded[..., 3] = 1.0
    img.pixels.foreach_set(encoded.ravel())
    img.pack()
    return img


def sunflower_head():
    kit.reset()
    petals = material("petals", "#f2b71f", roughness=0.8)
    seed_disc = material("seed_disc", "#3a2413", roughness=0.95, image=_seed_disc_image())
    stem = material("stem", "#5b7f34", roughness=0.8)
    bm = bmesh.new()
    # Built with the face towards +Z and the back of the disc at the origin,
    # then turned to face -Y (the front view) and drooped 20 degrees.
    disc_r = 0.074
    profile = [(0, 0.0), (0.040, 0.002), (0.064, 0.010), (0.074, 0.022), (0.071, 0.031),
               (0.052, 0.037), (0.026, 0.041), (0, 0.042)]
    lathe(bm, profile, 24, 0, mats=[2, 2, 2, 1, 1, 1, 1])

    def petal(angle, base_r, z0, length, width, lift, droop, mat_index, seed):
        radial = Vector((math.cos(angle), math.sin(angle), 0))
        twist = 0.12 * kit.bumpy(radial, 3.0, 1.0, seed) - 0.12
        pts, rads = [], []
        for s, w in ((0.0, 0.0), (0.3, 0.85), (0.72, 1.0), (1.0, 0.0)):
            pts.append(radial * (base_r + s * length) + Vector((0, 0, z0 + lift * s - droop * s * s)))
            rads.append((0.0012, width * 0.5 * w) if w else 0.0)
        side = radial.cross(Vector((0, 0, 1)))
        tube(bm, pts, rads, 4, mat_index, up=Vector((0, 0, 1)) + side * twist)

    for k in range(16):
        a = TAU * k / 16
        petal(a, 0.066, 0.026, 0.060, 0.022, 0.010, 0.020, 0, k)
        petal(a + TAU / 32, 0.064, 0.020, 0.056, 0.020, 0.004, 0.024, 0, k + 40)
        petal(a + TAU / 64, 0.062, 0.010, 0.030, 0.014, -0.004, 0.008, 2, k + 80)  # green bracts

    uv = bm.loops.layers.uv.new("UVMap")
    for f in bm.faces:
        for loop in f.loops:
            loop[uv].uv = (0.5 + loop.vert.co.x / (2 * disc_r), 0.5 + loop.vert.co.y / (2 * disc_r))
    bmesh.ops.rotate(bm, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(110), 3, "X"), verts=bm.verts)
    # stem stub leaves the back (now +Y and slightly up) and bends down under the head
    tube(bm, [(0, -0.004, -0.001), (0, 0.028, 0.010), (0, 0.050, 0.006), (0, 0.064, -0.014),
              (0, 0.071, -0.038), (0, 0.073, -0.058)],
         [0.0105, 0.0095, 0.009, 0.009, 0.0088, 0.0085], 8, 2)
    mesh_object("sunflower_head", bm, [petals, seed_disc, stem], smooth_angle=50, uv=None)
    kit.save("sunflower_head", "assets/models/ingredients/sunflower_head.glb")


def sunflower_seed():
    kit.reset()
    kernel = material("kernel", "#cfc6b0", roughness=0.8)
    bm = bmesh.new()
    tube(bm, [(0, 0, 0), (0.0025, 0, 0), (0.006, 0, 0), (0.0088, 0, 0), (0.010, 0, 0)],
         [0.0, (0.55, 0.62), (1.0, 1.0), (0.85, 0.8), 0.0], 6, 0, up=(0, 0, 1))
    kit.fit_to_box(bm, (0.010, 0.005, 0.003))
    mesh_object("sunflower_seed", bm, [kernel], smooth_angle=180)
    kit.save("sunflower_seed", "assets/models/ingredients/sunflower_seed.glb")


# --------------------------------------------------------------------------
# Section 2: heat and cooking
# --------------------------------------------------------------------------

def gas_stove():
    kit.reset()
    enamel = material("enamel", "#8fb3a2", roughness=0.35)
    iron = material("iron", "#3a3b3d", roughness=0.75)
    brass = material("brass", "#b8903f", metallic=1.0, roughness=0.35)
    burner = material("burner", "#1c1c1c", roughness=0.6)

    # body: enamelled casing with a shallow drip tray pressed into the top
    body_bm = kit.box_bm(Vector((0, 0, 0.038)), (0.30, 0.30, 0.060), 0, bevel=0.010, segments=2,
                         bevel_filter=lambda e: not (e.verts[0].co.z < 0 and e.verts[1].co.z < 0))
    top = max((f for f in body_bm.faces if f.normal.z > 0.99), key=lambda f: f.calc_area())
    bmesh.ops.inset_region(body_bm, faces=[top], thickness=0.020, depth=-0.004)
    body = bmesh.new()
    kit.merge(body, body_bm)
    for x in (-0.12, 0.12):
        for y in (-0.12, 0.12):
            cylinder(body, (x, y, 0.0), (x, y, 0.0085), 0.013, 8, 1)
    cylinder(body, (0, 0.150, 0.030), (0, 0.172, 0.030), 0.006, 8, 2)  # gas inlet
    mesh_object("body", body, [enamel, burner, brass])

    # burner: spreader ring and cap sitting in the drip tray
    cap = bmesh.new()
    lathe(cap, [(0, 0.064), (0.046, 0.064), (0.046, 0.071), (0.040, 0.073), (0.038, 0.078),
                (0.030, 0.082), (0, 0.083)], 20, 0)
    mesh_object("burner_cap", cap, [burner], smooth_angle=40)
    empty("flame_anchor", (0, 0, 0.083))

    # grate: ring on four legs, with four pan supports; tops at 0.10 m
    grate = bmesh.new()
    ring_r, ring_z = 0.105, 0.091
    tube(grate, [(ring_r * math.cos(TAU * i / 20), ring_r * math.sin(TAU * i / 20), ring_z) for i in range(20)],
         (0.0045, 0.004), 4, 0, closed=True)
    for k in range(4):
        a = TAU * k / 4 + TAU / 8
        box(grate, Vector((0.078 * math.cos(a), 0.078 * math.sin(a), 0.0955)), (0.060, 0.008, 0.009), 0, rot_z=a)
        box(grate, Vector((ring_r * math.cos(a + TAU / 8), ring_r * math.sin(a + TAU / 8), 0.080)),
            (0.009, 0.009, 0.026), 0, rot_z=a)
    mesh_object("grate", grate, [iron])

    # knob: pivot on the rotation axis at the front face; indicator points up (off)
    knob = bmesh.new()
    cylinder(knob, (0, 0, 0), (0, -0.004, 0), 0.022, 16, 0, up=(0, 0, 1))
    tube(knob, [(0, -0.004, 0), (0, -0.016, 0), (0, -0.019, 0)], [0.017, 0.016, 0.0145], 16, 0)
    kit.prism(knob, [(0.0032, -0.019, -0.010), (0.0032, -0.019, 0.011), (0, -0.019, 0.017),
                     (-0.0032, -0.019, 0.011), (-0.0032, -0.019, -0.010)], (0, -0.010, 0), 0)
    mesh_object("knob", knob, [brass], location=(0, -0.150, 0.038))
    kit.save("gas_stove", "assets/models/equipment/gas_stove.glb")


POT_INNER_R, POT_FLOOR, POT_RIM = 0.090, 0.003, 0.123


def pot():
    kit.reset()
    metal = material("metal", "#b9bec2", metallic=1.0, roughness=0.45)
    handles = material("handles", "#55595e", metallic=1.0, roughness=0.5)
    liquid = material("liquid", "#9fbcc0", roughness=0.1)
    bm = bmesh.new()
    wall = 0.003
    outer = POT_INNER_R + wall
    lathe(bm, [(0, 0.0), (outer - 0.008, 0.0), (outer - 0.001, 0.003), (outer, 0.010),
               (outer, POT_RIM - 0.006), (outer + 0.0018, POT_RIM - 0.002), (outer, POT_RIM),
               (POT_INNER_R, POT_RIM), (POT_INNER_R, POT_FLOOR + 0.004), (POT_INNER_R - 0.002, POT_FLOOR),
               (0, POT_FLOOR)], 32, 0)
    for side in (1, -1):
        loop = [(0.0905, -0.028), (0.110, -0.026), (0.121, -0.015), (0.124, 0.0), (0.121, 0.015),
                (0.110, 0.026), (0.0905, 0.028)]
        tube(bm, [(side * x, y, 0.104) for x, y in loop], (0.0055, 0.0035), 6, 1, up=(0, 0, 1))
    body = mesh_object("body", bm, [metal, handles], smooth_angle=50)
    volume = kit.cavity_volume_ml([(0, POT_FLOOR), (POT_INNER_R, POT_FLOOR), (POT_INNER_R, POT_RIM),
                                   (0, POT_RIM)], 32)
    body["interior_volume_ml"] = round(volume, 1)
    surface = bmesh.new()
    disc(surface, (0, 0, 0), POT_INNER_R - 0.0006, 32, 0)
    mesh_object("liquid_surface", surface, [liquid], location=(0, 0, POT_FLOOR + 0.0005), recalc=False)
    print(f"POT interior volume {volume:.0f} ml")
    kit.save("pot", "assets/models/equipment/pot.glb")


def slotted_spoon():
    kit.reset()
    metal = material("metal", "#aab0b5", metallic=1.0, roughness=0.35)
    wood = material("wood", "#8a5a34", roughness=0.75)
    bm = bmesh.new()
    xs = [0.0, 0.003, 0.012, 0.070, 0.125, 0.148]
    tube(bm, [(x, 0, 0) for x in xs], [0.0, 0.0075, 0.0100, 0.0102, 0.0094, 0.0090], 8, 1)
    tube(bm, [(0.144, 0, 0), (0.152, 0, 0), (0.160, 0, 0)], [0.0098, 0.0100, 0.0070], 8, 0)
    cx, bowl_r, rim_z = 0.282, 0.0378, -0.004
    tube(bm, [(0.158, 0, 0), (0.215, 0, -0.001), (cx - bowl_r, 0, rim_z)], (0.0028, 0.0022), 6, 0)
    tube(bm, [(cx + bowl_r * math.cos(TAU * i / 16), bowl_r * math.sin(TAU * i / 16), rim_z) for i in range(16)],
         0.0022, 4, 0, closed=True)
    for r, z in ((0.028, -0.011), (0.015, -0.016)):
        tube(bm, [(cx + r * math.cos(TAU * i / 12), r * math.sin(TAU * i / 12), z) for i in range(12)],
             0.0015, 3, 0, closed=True)
    for k in range(6):
        a = TAU * k / 6
        d = Vector((math.cos(a), math.sin(a), 0))
        pts = [Vector((cx, 0, -0.018)) + d * 0.002, Vector((cx, 0, -0.016)) + d * 0.015,
               Vector((cx, 0, -0.011)) + d * 0.028, Vector((cx, 0, rim_z)) + d * bowl_r]
        tube(bm, pts, 0.0014, 3, 0)
    mesh_object("slotted_spoon", bm, [metal, wood], smooth_angle=50)
    kit.save("slotted_spoon", "assets/models/equipment/slotted_spoon.glb")


def water_jug():
    kit.reset()
    ceramic = material("ceramic", "#e9e0cc", roughness=0.35)
    bm = bmesh.new()
    lip = {7, 8, 9}

    def spout(p, a, i):
        pull = max(0.0, math.cos(a)) ** 8
        if i in lip:
            p = p + Vector((math.cos(a), math.sin(a), 0)) * 0.010 * pull + Vector((0, 0, 0.004 * pull))
        elif i in (6, 10):
            p = p + Vector((math.cos(a), math.sin(a), 0)) * 0.005 * pull
        return p

    profile = [(0, 0.0), (0.040, 0.0), (0.045, 0.005), (0.049, 0.050), (0.047, 0.110), (0.040, 0.155),
               (0.041, 0.180), (0.045, 0.196), (0.046, 0.200), (0.042, 0.200), (0.036, 0.180),
               (0.035, 0.155), (0.043, 0.110), (0.045, 0.050), (0.038, 0.009), (0, 0.008)]
    lathe(bm, profile, 18, 0, shape=spout)
    tube(bm, [(-0.040, 0, 0.176), (-0.058, 0, 0.172), (-0.066, 0, 0.150), (-0.066, 0, 0.105),
              (-0.058, 0, 0.076), (-0.044, 0, 0.066)], (0.009, 0.0042), 6, 0, up=(0, 1, 0))
    mesh_object("body", bm, [ceramic], smooth_angle=50)
    tip = max(bpy.data.objects["body"].data.vertices, key=lambda v: v.co.x)
    empty("pour_point", tuple(tip.co))
    kit.save("water_jug", "assets/models/equipment/water_jug.glb")


def oil_bottle():
    kit.reset()
    glass = material("glass", "#cfe6e2", roughness=0.05, alpha=0.3)
    oil = material("oil", "#d6a52a", roughness=0.1, alpha=0.85)
    cork = material("cork", "#b08858", roughness=0.9)
    bm = bmesh.new()
    lathe(bm, [(0, 0.0), (0.031, 0.0), (0.035, 0.004), (0.035, 0.150), (0.028, 0.184), (0.0125, 0.204),
               (0.0125, 0.236), (0.0145, 0.238), (0.0145, 0.243), (0.0100, 0.243), (0.0100, 0.205),
               (0.0260, 0.185), (0.0325, 0.150), (0.0325, 0.006), (0, 0.006)], 14, 0)
    lathe(bm, [(0, 0.0065), (0.0320, 0.0065), (0.0320, 0.120), (0, 0.120)], 14, 1)
    mesh_object("body", bm, [glass, oil], smooth_angle=50)
    stopper = bmesh.new()
    lathe(stopper, [(0, 0.228), (0.0092, 0.228), (0.0100, 0.243), (0.0118, 0.244), (0.0118, 0.250),
                    (0, 0.250)], 12, 0)
    mesh_object("cork", stopper, [cork], smooth_angle=50)
    empty("pour_point", (0, 0, 0.243))
    kit.save("oil_bottle", "assets/models/equipment/oil_bottle.glb")


# --------------------------------------------------------------------------
# Section 3: equipment and transformations
# --------------------------------------------------------------------------

PRESS_AXIS_Z = 0.130
HOPPER_X = 0.045


def oil_press():
    kit.reset()
    iron = material("iron", "#3b3a38", roughness=0.75)
    wood = material("wood", "#7a4a28", roughness=0.75)
    brass = material("brass", "#b38a3e", metallic=1.0, roughness=0.35)
    z = PRESS_AXIS_Z

    frame = bmesh.new()
    for px in (-0.0825, 0.0825):
        box(frame, Vector((px, 0, 0.006)), (0.060, 0.130, 0.012), 0, bevel=0.003)
        box(frame, Vector((px, 0, 0.012 + (z - 0.012) / 2)), (0.020, 0.070, z - 0.012), 0,
            taper_top=(1.0, 0.65))
        tube(frame, [(px - 0.012, 0, z), (px + 0.012, 0, z)], 0.037, 16, 0)
        for dy in (-0.048, 0.048):
            for dx in (-0.020, 0.020):
                cylinder(frame, (px + dx, dy, 0.012), (px + dx, dy, 0.018), 0.0055, 6, 2)
    mesh_object("frame", frame, [iron, wood, brass])

    barrel = bmesh.new()
    xs = [-0.172, -0.160, -0.148, -0.140, -0.120, -0.050, -0.046, -0.030, -0.026, -0.010, -0.006,
          0.010, 0.014, 0.105]
    rs = [0.009, 0.013, 0.021, 0.030, 0.030, 0.030, 0.027, 0.027, 0.030, 0.030, 0.027, 0.027, 0.030, 0.030]
    tube(barrel, [(x, 0, z) for x in xs], rs, 20, 0)
    tube(barrel, [(-0.150, 0, z), (-0.138, 0, z)], 0.0325, 20, 2)   # outlet collar
    tube(barrel, [(0.100, 0, z), (0.116, 0, z)], 0.034, 20, 2)      # crank bearing
    tube(barrel, [(0.002, 0, z - 0.026), (0.002, 0, z - 0.040), (0.002, 0, z - 0.046)],
         [0.0075, 0.0055, 0.004], 8, 2)                              # oil drip nozzle
    mesh_object("barrel", barrel, [iron, wood, brass], smooth_angle=40)

    hopper = bmesh.new()
    inner = [(0.0155, 0.150), (0.0155, 0.185), (0.0525, 0.295), (0.0525, 0.300)]
    outer = [(r + 0.0025, h) for r, h in inner]
    lathe(hopper, [outer[0], outer[1], outer[2], (outer[3][0] + 0.002, 0.298), (outer[3][0], 0.300)]
          + list(reversed(inner)), 24, 0, center=(HOPPER_X, 0, 0), closed=True)
    mesh_object("hopper", hopper, [iron, wood, brass], smooth_angle=40)
    hopper_ml = kit.cavity_volume_ml([(0, 0.185), (0.0155, 0.185), (0.0525, 0.295), (0.0525, 0.300),
                                      (0, 0.300)], 24)
    print(f"PRESS hopper volume {hopper_ml:.0f} ml, about {hopper_ml * 0.6:.0f} g of seeds")

    # crank: pivot on the screw axis at the barrel end; arm points up at rest
    crank = bmesh.new()
    tube(crank, [(0.0, 0, 0), (0.014, 0, 0)], 0.015, 12, 0)
    tube(crank, [(0.014, 0, 0), (0.020, 0, 0)], 0.009, 6, 2)
    tube(crank, [(0.009, 0, 0.004), (0.009, 0, 0.040), (0.009, 0, 0.072)], [(0.0045, 0.009), (0.0042, 0.008),
         (0.004, 0.0075)], 6, 0, up=(1, 0, 0))
    tube(crank, [(0.004, 0, 0.078), (0.016, 0, 0.078)], 0.0085, 8, 0)
    tube(crank, [(0.016, 0, 0.078), (0.019, 0, 0.078), (0.030, 0, 0.078), (0.043, 0, 0.078), (0.050, 0, 0.078),
                 (0.053, 0, 0.078)], [0.0065, 0.0080, 0.0095, 0.0090, 0.0070, 0.0], 8, 1)
    mesh_object("crank", crank, [iron, wood, brass], location=(0.116, 0, z), smooth_angle=45)

    empty("oil_spout", (0.002, 0, z - 0.046))  # clear of both feet for the oil cup
    empty("cake_outlet", (-0.172, 0, z))
    kit.save("oil_press", "assets/models/equipment/oil_press.glb")


def oil_cup():
    kit.reset()
    ceramic = material("ceramic", "#7fa3b0", roughness=0.35)
    oil = material("oil", "#d6a52a", roughness=0.1, alpha=0.85)
    bm = bmesh.new()
    inner_r, floor, rim = 0.0355, 0.005, 0.070

    def spout(p, a, i):
        pull = max(0.0, math.cos(a)) ** 10
        weight = {3: 0.4, 4: 1.0, 5: 1.0, 6: 1.0, 7: 0.4}.get(i, 0.0) * pull
        return p + Vector((math.cos(a), math.sin(a), 0)) * 0.009 * weight + Vector((0, 0, 0.003 * weight))

    lathe(bm, [(0, 0.0), (0.034, 0.0), (0.0385, 0.004), (0.0385, rim - 0.012), (0.0385, rim - 0.002),
               (0.0375, rim), (inner_r, rim), (inner_r, rim - 0.012), (inner_r, floor + 0.003),
               (inner_r - 0.003, floor), (0, floor)], 20, 0, shape=spout)
    body = mesh_object("body", bm, [ceramic], smooth_angle=50)
    volume = kit.cavity_volume_ml([(0, floor), (inner_r, floor), (inner_r, rim), (0, rim)], 20)
    body["interior_volume_ml"] = round(volume, 1)
    print(f"CUP interior volume {volume:.0f} ml")
    surface = bmesh.new()
    disc(surface, (0, 0, 0), inner_r - 0.0035, 20, 0)
    mesh_object("oil_surface", surface, [oil], location=(0, 0, floor + 0.0005), recalc=False)
    tip = max(body.data.vertices, key=lambda v: v.co.x)
    empty("pour_point", tuple(tip.co))
    kit.save("oil_cup", "assets/models/equipment/oil_cup.glb")


def sunflower_seed_cake():
    kit.reset()
    cake = material("cake", "#7a5f45", roughness=0.95)
    bm = bmesh.new()
    xs = [-0.0015, 0.0, 0.008, 0.017, 0.026, 0.034, 0.040, 0.0415]
    tube(bm, [(x, 0, 0) for x in xs], [0.0, 0.0052, 0.0060, 0.0058, 0.0061, 0.0057, 0.0050, 0.0],
         8, 0, shape=lambda a, i: 1.0 + 0.16 * math.sin(a * 3 + i * 1.7) * math.cos(a * 2 - i))
    for v in bm.verts:  # crumbly: jitter each vertex off the pellet's axis
        v.co += (v.co - Vector((v.co.x, 0, 0))) * 0.12 * (kit.bumpy(v.co * 300, 1.0, 1.0, 5) - 1.0)
    kit.fit_to_box(bm, (0.040, 0.012, 0.012))
    mesh_object("sunflower_seed_cake", bm, [cake], smooth_angle=30)
    kit.save("sunflower_seed_cake", "assets/models/ingredients/sunflower_seed_cake.glb")


# --------------------------------------------------------------------------
# Section 6, checkpoint 1: the cutting board
# --------------------------------------------------------------------------

def mezzaluna():
    kit.reset()
    steel = material("steel", "#c9d3dc", metallic=1.0, roughness=0.25)
    wood = material("wood", "#6b4226", roughness=0.75)
    half, thick, bevel_h = 0.085, 0.0025, 0.006
    edge_r = (half ** 2 + 0.055 ** 2) / (2 * 0.055)   # edge rises 55 mm to the tips
    spine_r = (half ** 2 + 0.025 ** 2) / (2 * 0.025)  # spine: 50 mm at centre, 75 mm at tips

    def edge_z(x):
        return edge_r - math.sqrt(edge_r ** 2 - x * x)

    def spine_z(x):
        return 0.050 + spine_r - math.sqrt(spine_r ** 2 - x * x)

    blade = bmesh.new()
    stations = []
    n = 20
    for i in range(n + 1):
        x = -half + 2 * half * i / n
        e, s = edge_z(x), spine_z(x)
        b = e + min(bevel_h, (s - e) * 0.45)
        stations.append([blade.verts.new(c) for c in ((x, thick / 2, s), (x, thick / 2, b), (x, 0, e),
                                                       (x, -thick / 2, b), (x, -thick / 2, s))])
    for a_ring, b_ring in zip(stations, stations[1:]):
        for k in range(5):
            k1 = (k + 1) % 5
            blade.faces.new((a_ring[k], b_ring[k], b_ring[k1], a_ring[k1]))
    blade.faces.new(stations[0])
    blade.faces.new(list(reversed(stations[-1])))
    for side in (-1, 1):  # tang rising into each handle
        box(blade, Vector((side * (half - 0.003), 0, spine_z(half) + 0.006)), (0.006, thick, 0.014), 0)
    for f in blade.faces:
        f.material_index = 0
    pivot = empty("BladePivot", (0, 0, 0), size=0.03, display="ARROWS")
    mesh_object("Blade", blade, [steel], parent=pivot, smooth_angle=30)

    for name, side in (("HandleLeft", -1), ("HandleRight", 1)):
        bm = bmesh.new()
        x, base = side * half, spine_z(half) + 0.004
        tube(bm, [(x, 0, base), (x, 0, base + 0.008)], [0.0085, 0.0085], 10, 1)
        zs = [base + 0.008, base + 0.012, base + 0.030, base + 0.052, base + 0.064, base + 0.070]
        tube(bm, [(x, 0, h) for h in zs], [0.0080, 0.0095, 0.0108, 0.0098, 0.0075, 0.0], 10, 0)
        mesh_object(name, bm, [wood, steel], parent=pivot, smooth_angle=45)
    kit.save("mezzaluna", "assets/models/tools/mezzaluna.glb")


def cutting_board():
    kit.reset()
    wood = material("wood", "#b98a58", roughness=0.8)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=6, y_segments=4, size=1.0)
    extent = max(abs(v.co.x) for v in bm.verts)
    for v in bm.verts:
        v.co.x *= 0.20 / extent
        v.co.y *= 0.14 / extent
    ext = bmesh.ops.extrude_face_region(bm, geom=list(bm.faces))
    bmesh.ops.translate(bm, vec=(0, 0, -0.020), verts=[g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    rim = [e for e in bm.edges if len(e.link_faces) == 2 and e.calc_face_angle(0) > math.radians(60)]
    bmesh.ops.bevel(bm, geom=rim, offset=0.004, segments=2, profile=0.5, affect="EDGES", clamp_overlap=True)
    for v in bm.verts:  # a faint dip worn into the middle of the top from use
        if v.co.z > -0.001 and abs(v.co.x) < 0.17 and abs(v.co.y) < 0.11:
            wear = (1 - (v.co.x / 0.19) ** 2) * (1 - (v.co.y / 0.13) ** 2)
            v.co.z -= 0.0008 * wear * kit.bumpy(v.co * 20, 1.0, 0.5, 3)
    top = max(v.co.z for v in bm.verts)
    for v in bm.verts:
        v.co.z -= top
    for f in bm.faces:
        f.material_index = 0
    mesh_object("cutting_board", bm, [wood], smooth_angle=35)
    kit.save("cutting_board", "assets/models/tools/cutting_board.glb")


def basket():
    kit.reset()
    wicker = material("wicker", "#b58d57", roughness=0.9)
    bm = bmesh.new()
    outer = [(0.052, 0.004), (0.058, 0.013), (0.062, 0.022), (0.065, 0.031), (0.067, 0.040),
             (0.068, 0.049)]
    inner = [(r - 0.0045, h + 0.002) for r, h in reversed(outer)]
    profile = ([(0, 0.0), (0.044, 0.0)] + outer + [(0.0705, 0.055), (0.0685, 0.060), (0.0645, 0.058)]
               + inner + [(0.040, 0.006), (0, 0.006)])

    def weave(p, a, i):
        """Coiled wicker: alternate rows of the outer wall stand proud of the next."""
        if not 2 <= i < 2 + len(outer):
            return p
        return p + Vector((math.cos(a), math.sin(a), 0)) * (0.0016 if i % 2 else -0.0010)

    lathe(bm, profile, 22, 0, shape=weave)
    mesh_object("basket", bm, [wicker], smooth_angle=25)  # crisp creases between coils
    kit.save("basket", "assets/models/pantry/basket.glb")


def counter():
    kit.reset()
    top_mat = material("top", "#cdb08a", roughness=0.85)
    base_mat = material("base", "#6f8f86", roughness=0.7)
    bm = bmesh.new()
    box(bm, Vector((0, 0, -0.020)), (1.600, 0.600, 0.040), 0, bevel=0.005, segments=2)
    box(bm, Vector((0, 0.015, -0.440)), (1.540, 0.570, 0.800), 1)
    box(bm, Vector((0, 0.030, -0.870)), (1.500, 0.520, 0.060), 1)
    for dx in (-0.385, 0.385):
        # drawer above a door on each side, each a raised panel with a sunken centre
        for cz, h in ((-0.130, 0.150), (-0.530, 0.600)):
            panel = kit.box_bm(Vector((dx, -0.274, cz)), (0.730, 0.012, h), 1)
            front = min(panel.faces, key=lambda f: f.calc_center_median().y)
            bmesh.ops.inset_region(panel, faces=[front], thickness=0.035, depth=-0.005)
            kit.merge(bm, panel)
            drawer = h < 0.3
            knob_x = dx if drawer else dx * 0.22  # door knobs sit by the meeting stiles
            knob_z = cz if drawer else cz + h / 2 - 0.080
            tube(bm, [(knob_x, -0.279, knob_z), (knob_x, -0.286, knob_z), (knob_x, -0.295, knob_z),
                      (knob_x, -0.298, knob_z)], [0.007, 0.006, 0.012, 0.0], 10, 0)
    mesh_object("counter", bm, [top_mat, base_mat], smooth_angle=35)
    kit.save("counter", "assets/models/kitchen/counter.glb")


# --------------------------------------------------------------------------
# The pantry and the pass
# --------------------------------------------------------------------------

# Shelf tops (m above the counter) and depths, front to back, for the
# dresser: garden at counter height, then catch, grains and spices. The
# Godot PantryDresser lays its items out on these, so keep them in step.
DRESSER_WIDTH, DRESSER_DEPTH = 1.30, 0.30
DRESSER_SHELVES = [(0.0, 0.30), (0.15, 0.28), (0.29, 0.25), (0.42, 0.22)]
DRESSER_TOP = 0.58


def pantry_dresser():
    """An open dresser standing behind the counter: a cupboard base below the
    counter's height, and four open shelves above, stepping back as they
    rise. Origin: centre of the front-to-back middle of the bottom shelf's
    top, level with the counter top; front faces -Y."""
    kit.reset()
    paint = material("paint", "#7d9e93", roughness=0.75)
    wood = material("wood", "#cdb08a", roughness=0.85)
    zinc = material("zinc", "#a3abae", metallic=0.3, roughness=0.45)
    ice = material("ice", "#e2f0f3", roughness=0.2)
    straw = material("straw", "#d6bf7c", roughness=0.95)
    brass = material("brass", "#b8903f", metallic=1.0, roughness=0.35)
    bm = bmesh.new()
    w, d = DRESSER_WIDTH, DRESSER_DEPTH
    back_y = d / 2
    # Cupboard base, to the ground, with two doors.
    box(bm, Vector((0, 0, -0.47)), (w, d, 0.90), 0)
    box(bm, Vector((0, -0.005, -0.905)), (w - 0.02, d - 0.02, 0.03), 0)
    for dx in (-w / 4, w / 4):
        panel = kit.box_bm(Vector((dx, -d / 2 - 0.006, -0.48)), (w / 2 - 0.05, 0.012, 0.78), 0)
        front = min(panel.faces, key=lambda f: f.calc_center_median().y)
        bmesh.ops.inset_region(panel, faces=[front], thickness=0.035, depth=-0.005)
        kit.merge(bm, panel)
        tube(bm, [(dx * 0.2, -d / 2 - 0.012, -0.18), (dx * 0.2, -d / 2 - 0.02, -0.18), (dx * 0.2, -d / 2 - 0.028, -0.18),
                  (dx * 0.2, -d / 2 - 0.031, -0.18)], [0.007, 0.006, 0.011, 0.0], 10, 5)
    # Side panels, stepping back with the shelves, and a scalloped top.
    for side in (1, -1):
        x = side * (w / 2 - 0.0125)
        outline = [(back_y, -0.02), (-d / 2, -0.02)]
        for (z, depth), (z_next, _d) in zip(DRESSER_SHELVES, DRESSER_SHELVES[1:] + [(DRESSER_TOP, 0)]):
            front = back_y - depth
            outline += [(front, z + 0.02), (front, z_next - 0.03)]
        outline += [(back_y - 0.20, DRESSER_TOP + 0.04), (back_y, DRESSER_TOP + 0.06)]
        pts = [(x - 0.0125, y, z) for y, z in outline]
        kit.prism(bm, pts, (0.025, 0, 0), 0)
    # The back, in planks.
    for i in range(10):
        px = -w / 2 + 0.025 + (w - 0.05) * (i + 0.5) / 10
        box(bm, Vector((px, back_y - 0.006, DRESSER_TOP / 2)), ((w - 0.05) / 10 - 0.002, 0.012, DRESSER_TOP), 0)
    # Shelves, each with a rail to keep jars from walking off.
    for i, (z, depth) in enumerate(DRESSER_SHELVES):
        y = back_y - depth / 2
        box(bm, Vector((0, y, z - 0.0125)), (w - 0.05, depth, 0.025), 1, bevel=0.003, segments=1)
        if i >= 2:
            tube(bm, [(-w / 2 + 0.025, back_y - depth + 0.008, z + 0.035), (w / 2 - 0.025, back_y - depth + 0.008, z + 0.035)],
                 0.004, 6, 5)
    # The cornice.
    box(bm, Vector((0, back_y - 0.13, DRESSER_TOP + 0.015)), (w + 0.04, 0.26, 0.03), 1, bevel=0.006, segments=2)
    # Straw on the garden shelf.
    straw_bm = bmesh.new()
    bmesh.ops.create_grid(straw_bm, x_segments=24, y_segments=6, size=0.5)
    for v in straw_bm.verts:
        v.co.x *= (w - 0.07)
        v.co.y = v.co.y * (DRESSER_SHELVES[0][1] - 0.03) + back_y - DRESSER_SHELVES[0][1] / 2
        v.co.z = 0.002 + 0.0015 * kit.bumpy(v.co * 40, 1.0, 1.0, 5) - 0.0015
    ext = bmesh.ops.extrude_face_region(straw_bm, geom=list(straw_bm.faces))
    bmesh.ops.translate(straw_bm, vec=(0, 0, -0.002), verts=[g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)])
    for f in straw_bm.faces:
        f.material_index = 4
    kit.merge(bm, straw_bm)
    # A zinc tray of crushed ice on the catch shelf.
    z, depth = DRESSER_SHELVES[1]
    y = back_y - depth / 2
    tray_w, tray_d = w - 0.08, depth - 0.03
    box(bm, Vector((0, y, z + 0.002)), (tray_w, tray_d, 0.004), 2)
    for sx, sy, lx, ly in ((0, tray_d / 2, tray_w, 0.004), (0, -tray_d / 2, tray_w, 0.004),
                           (tray_w / 2, 0, 0.004, tray_d), (-tray_w / 2, 0, 0.004, tray_d)):
        box(bm, Vector((sx, y + sy, z + 0.012)), (lx, ly, 0.024), 2)
    ice_bm = bmesh.new()
    bmesh.ops.create_grid(ice_bm, x_segments=40, y_segments=8, size=0.5)
    for v in ice_bm.verts:
        v.co.x *= tray_w - 0.012
        v.co.y = v.co.y * (tray_d - 0.012) + y
        v.co.z = z + 0.014 + 0.004 * (kit.bumpy(v.co * 60, 1.0, 1.0, 9) - 1.0)
    ext = bmesh.ops.extrude_face_region(ice_bm, geom=list(ice_bm.faces))
    bmesh.ops.translate(ice_bm, vec=(0, 0, -0.01), verts=[g for g in ext["geom"] if isinstance(g, bmesh.types.BMVert)])
    for f in ice_bm.faces:
        f.material_index = 3
    kit.merge(bm, ice_bm)
    mesh_object("pantry_dresser", bm, [paint, wood, zinc, ice, straw, brass], smooth_angle=30)
    kit.save("pantry_dresser", "assets/models/pantry/pantry_dresser.glb")


# Where a crock's or sack's contents heap, above its base.
CROCK_MOUTH_Z = 0.074
SACK_MOUTH_Z = 0.082


def _contents_mound(radius, base_z, rise):
    """What a container holds, heaped in its mouth: a separate object,
    `contents`, which Godot tints the colour of what is in it."""
    bm = bmesh.new()
    profile = [(0, base_z), (radius, base_z), (radius * 0.98, base_z + rise * 0.35), (radius * 0.7, base_z + rise * 0.8),
               (radius * 0.35, base_z + rise * 0.97), (0, base_z + rise)]
    lathe(bm, profile, 16, 0, shape=lambda p, a, i: p * kit.bumpy(p * 30.0, 1.0, 0.04, 6) if 1 < i < 5 else p)
    contents = material("contents", "#c8b89a", roughness=0.95)
    mesh_object("contents", bm, [contents], smooth_angle=60, uv=None)


def spice_crock():
    """A small glazed crock, open, its spice heaped at the mouth, with a
    paper label tied round its belly."""
    kit.reset()
    glaze = material("glaze", "#5e7f8e", roughness=0.25)
    clay = material("clay", "#c99a6e", roughness=0.9)
    label = material("label", "#efe6cf", roughness=0.9)
    bm = bmesh.new()
    profile = [(0, 0.0), (0.026, 0.0), (0.031, 0.006), (0.035, 0.03), (0.034, 0.055), (0.029, 0.072),
               (0.030, 0.080), (0.027, 0.082), (0.024, 0.076), (0.026, 0.06), (0.024, CROCK_MOUTH_Z - 0.006),
               (0, CROCK_MOUTH_Z - 0.006)]
    lathe(bm, profile, 18, 0, mats=[1, 0, 0, 0, 0, 1, 1, 1, 0, 0, 0])
    band = bmesh.new()
    lathe(band, [(0.0352, 0.026), (0.0362, 0.028), (0.0362, 0.05), (0.0352, 0.052), (0.034, 0.05),
                 (0.034, 0.028)], 18, 2, closed=True)
    kit.merge(bm, band)
    mesh_object("spice_crock", bm, [glaze, clay, label], smooth_angle=40)
    _contents_mound(0.0255, CROCK_MOUTH_Z - 0.008, 0.012)
    kit.save("spice_crock", "assets/models/pantry/spice_crock.glb")


def grain_sack():
    """A small burlap sack, its neck rolled down, its grain showing."""
    kit.reset()
    burlap = material("burlap", "#b89a6a", roughness=0.95)
    twine = material("twine", "#8a6a44", roughness=0.9)
    bm = bmesh.new()
    profile = [(0, 0.0), (0.058, 0.0), (0.072, 0.012), (0.078, 0.04), (0.074, 0.068), (0.068, 0.08),
               (0.074, 0.088), (0.078, 0.096), (0.072, 0.1), (0.064, 0.094), (0.062, SACK_MOUTH_Z),
               (0, SACK_MOUTH_Z)]

    def slump(p, a, i):
        return p * kit.bumpy(Vector((math.cos(a), math.sin(a), p.z * 8.0)), 1.6, 0.06, 3)

    lathe(bm, profile, 20, 0, shape=slump)
    # The slump is uneven; set the sack's foot back on the origin.
    foot = [v.co for v in bm.verts if v.co.z < 0.002]
    shift = Vector(((min(p.x for p in foot) + max(p.x for p in foot)) / 2, (min(p.y for p in foot) + max(p.y for p in foot)) / 2, 0))
    for v in bm.verts:
        v.co -= shift
    tube(bm, [(0.071 * math.cos(TAU * k / 20), 0.071 * math.sin(TAU * k / 20), 0.078) for k in range(20)],
         0.003, 4, 1, closed=True)
    mesh_object("grain_sack", bm, [burlap, twine], smooth_angle=45)
    _contents_mound(0.062, SACK_MOUTH_Z - 0.01, 0.022)
    kit.save("grain_sack", "assets/models/pantry/grain_sack.glb")


def serving_plate():
    """The pass's serving platter: a glazed oval, its well level with the
    origin like the board's top, rim raised and banded in blue."""
    kit.reset()
    glaze = material("glaze", "#f1ece0", roughness=0.2)
    band = material("band", "#5876a0", roughness=0.25)
    bm = bmesh.new()
    sx, sy = 0.32 / 2, 0.224 / 2
    profile = [(0, -0.014), (0.70, -0.014), (0.78, -0.008), (0.86, -0.002), (0.93, 0.004), (0.985, 0.0075),
               (1.0, 0.006), (0.975, 0.0045), (0.88, 0.0005), (0.84, 0.0), (0, 0.0)]
    lathe(bm, profile, 40, 0, mats=[0, 0, 0, 0, 1, 1, 0, 0, 0, 0])
    for v in bm.verts:
        v.co.x *= sx
        v.co.y *= sy
    mesh_object("serving_plate", bm, [glaze, band], smooth_angle=40)
    kit.save("serving_plate", "assets/models/tools/serving_plate.glb")


# --------------------------------------------------------------------------
# The caretaker's hand
# --------------------------------------------------------------------------

# Knuckle positions across the back of the hand (X; the thumb is at -X on a
# right hand held palm down), finger lengths, and how each length is shared
# between its three bones.
_FINGERS = [(-0.027, 0.071), (-0.009, 0.079), (0.009, 0.073), (0.026, 0.059)]
_BONES = (0.46, 0.30, 0.24)

# Each pose: (curl of each finger's three joints in degrees, spread of each
# finger in degrees, thumb (sweep in, curl) in degrees, what the origin is).
HAND_POSES = {
    "open": ([(14, 16, 10)] * 4, (-7, -2, 3, 8), (10, 10), "index_tip"),
    "grip": ([(58, 66, 44), (60, 70, 46), (62, 72, 46), (64, 74, 48)], (-3, -1, 1, 3), (45, 35), "grasp"),
    "pinch": ([(36, 44, 26), (66, 80, 54), (74, 86, 60), (80, 88, 62)], (-2, 0, 2, 4), (58, 26), "pinch"),
    "press": ([(4, 3, 2)] * 4, (-11, -4, 4, 12), (-8, 4), "palm"),
}


def _finger(bm, base, length, curls, spread, radius):
    """A finger from its knuckle: three bones bending down (toward -Z) by
    `curls`, splayed by `spread` about Z. Returns its tip."""
    pts, radii = [Vector(base)], [radius]
    angle = 0.0
    p = Vector(base)
    for share, curl in zip(_BONES, curls):
        angle += math.radians(curl)
        d = Matrix.Rotation(math.radians(spread), 3, "Z") @ Vector((0.0, math.cos(angle), -math.sin(angle)))
        p = p + d * length * share
        pts.append(p.copy())
        radii.append(radius * (0.92 if len(radii) < 3 else 0.82))
    tip = p + d * radius * 0.6
    pts.append(tip)
    radii.append(0.0)
    tube(bm, pts, radii, 7, 0, up=(0, 0, 1))
    return tip


def _hand(curls, spreads, thumb, origin):
    bm = bmesh.new()
    # The palm, knuckles at Y = 0.088, wrist at Y = 0: a flattened egg,
    # narrowing to the wrist, the back rounded, the knuckles a low ridge.
    palm = bmesh.new()
    bmesh.ops.create_uvsphere(palm, u_segments=16, v_segments=10, radius=1.0)
    for v in palm.verts:
        x, y, z = v.co
        t = (y + 1.0) * 0.5
        x *= 0.82 + 0.18 * t
        z *= 0.55 if z < 0 else 1.0
        z += 0.12 * max(0.0, y - 0.55) * (1.0 - abs(x))
        v.co = Vector((x * 0.041, 0.045 + y * 0.047, z * 0.0145))
    for f in palm.faces:
        f.material_index = 0
    kit.merge(bm, palm)
    tips = []
    for (x, length), curl, spread in zip(_FINGERS, curls, spreads):
        tips.append(_finger(bm, (x, 0.086, 0.002), length, curl, spread, 0.0088 if x < 0.02 else 0.0078))
    # The thumb sweeps in across the palm and curls toward the fingers.
    sweep, curl = math.radians(thumb[0]), math.radians(thumb[1])
    base = Vector((-0.034, 0.026, -0.004))
    d0 = Vector((-math.cos(sweep) * 0.75, 0.62, -0.25 - 0.5 * math.sin(sweep))).normalized()
    p1 = base + d0 * 0.034
    d1 = (Matrix.Rotation(-curl, 3, "Y") @ (Matrix.Rotation(-curl * 0.8, 3, "Z") @ d0)).normalized()
    p2 = p1 + d1 * 0.028
    thumb_tip = p2 + d1 * 0.006
    tube(bm, [base, p1, p2, thumb_tip], [0.0125, 0.0105, 0.0095, 0.0], 7, 0, up=(0, 0, 1))
    # Wrist, the knitted cuff, and the coat sleeve going back toward the eye.
    tube(bm, [(0.0, 0.014, -0.002), (0.0, -0.02, 0.002), (0.0, -0.05, 0.008)], [(0.012, 0.027), (0.014, 0.026), (0.017, 0.028)], 10, 0,
         up=(0, 0, 1))
    tube(bm, [(0.0, -0.045, 0.01), (0.0, -0.072, 0.016)], [0.034, 0.035], 12, 2)
    # Long enough that its end is always behind the eye.
    tube(bm, [(0.0, -0.066, 0.016), (0.0, -0.17, 0.05), (0.0, -0.36, 0.12), (0.0, -0.7, 0.26)],
         [0.041, 0.046, 0.052, 0.06], 12, 1)
    if origin == "index_tip":
        point = tips[0]
    elif origin == "pinch":
        point = (tips[0] + thumb_tip) / 2
    elif origin == "grasp":
        point = (sum(tips, Vector()) / 4 + Vector((0.0, 0.05, -0.013))) / 2
    else:
        point = Vector((0.0, 0.05, -0.013))
    for v in bm.verts:
        v.co -= point
    return bm


def hand():
    """The caretaker's right hand in each of its poses, one object per pose,
    each with its origin at the point it touches with: the index fingertip
    (open, reaching), the middle of the grasp (grip), where finger and thumb
    meet (pinch) and the middle of the palm (press). Fingers point +Y (away
    from the cook), palm down. Godot mirrors it for the left hand."""
    kit.reset()
    skin = material("skin", "#e2b18b", roughness=0.7)
    sleeve = material("sleeve", "#3f5867", roughness=0.9)
    cuff = material("cuff", "#d6c7a2", roughness=0.95)
    for name, (curls, spreads, thumb, origin) in HAND_POSES.items():
        mesh_object("hand_" + name, _hand(curls, spreads, thumb, origin), [skin, sleeve, cuff], smooth_angle=60)
    kit.save("hand", "assets/models/player/hand.glb")


MODELS = {f.__name__: f for f in (
    potato, chilli, sunflower_head, sunflower_seed, gas_stove, pot, slotted_spoon, water_jug,
    oil_bottle, oil_press, oil_cup, sunflower_seed_cake, mezzaluna, cutting_board, basket, counter,
    pantry_dresser, spice_crock, grain_sack, serving_plate, hand)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or list(MODELS)
    unknown = [n for n in names if n not in MODELS]
    if unknown:
        raise SystemExit(f"unknown model(s): {', '.join(unknown)}; known: {', '.join(MODELS)}")
    for name in names:
        MODELS[name]()


main()
