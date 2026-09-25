"""Build the outdoor setting around the kitchen: the cliff top, the lighthouse and
the sea stacks. Kept apart from build_models.py so rebuilding the setting can
never overwrite the kitchen kit.

    blender --background --factory-startup --python tools/blender/build_environment.py [-- name ...]

Blender axes: X across the coast, Y out to sea (Godot -Z), Z up. The kitchen
counter stands at the origin; the ground there is Z = 0 and the sea surface is
Z = -14. Each model is written to models/<name>.blend and exported to its .glb
under assets/models/environment/.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector, noise

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kit  # noqa: E402
from kit import box, cylinder, lathe, material, mesh_object, tube  # noqa: E402

TAU = 2.0 * math.pi
SEA_LEVEL = -14.0


# --------------------------------------------------------------------------
# Cliff top
# --------------------------------------------------------------------------

# The land is a straight-ish coast a few metres beyond the counter, with a
# long headland running out to sea on the left for the lighthouse.
COAST_Y = 3.6
HEADLAND_X = -30.0
HEADLAND_ROOT_Y = 2.0
HEADLAND_TIP_Y = 64.0
HEADLAND_RADIUS = 9.0
LIGHTHOUSE_SPOT = (HEADLAND_X, 62.0)
# The drop from the grass edge to the sea happens over this many metres.
CLIFF_DROP = 2.6
GRID_STEP = 1.25
EXTENT_X = (-72.0, 48.0)
EXTENT_Y = (-40.0, 82.0)
STRATUM = 2.4


def _coast_distance(x, y):
    """Signed distance to the coastline: negative on land, positive out at sea."""
    along = noise.noise(Vector((x * 0.06, 0.0, 0.3)))
    main = y - (COAST_Y + 1.8 * along)
    t = min(max((y - HEADLAND_ROOT_Y) / (HEADLAND_TIP_Y - HEADLAND_ROOT_Y), 0.0), 1.0)
    cy = HEADLAND_ROOT_Y + t * (HEADLAND_TIP_Y - HEADLAND_ROOT_Y)
    radius = HEADLAND_RADIUS * (1.0 - 0.35 * t)
    headland = math.hypot(x - HEADLAND_X, y - cy) - radius
    wobble = 1.3 * noise.noise(Vector((x * 0.11, y * 0.11, 1.7)))
    return min(main, headland) + wobble


def _ground_height(x, y):
    sd = _coast_distance(x, y)
    if sd <= 0.0:
        rolling = 0.35 * noise.noise(Vector((x * 0.045, y * 0.045, 4.2)))
        rise_inland = max(0.0, -y - 8.0) * 0.045
        # A level terrace for the kitchen, blending into the rolling ground.
        terrace = min(math.hypot(x, y) / 3.5, 1.0)
        top = (rolling + rise_inland) * terrace
        # Rounded lip along the cliff edge.
        lip = min(-sd / 1.2, 1.0)
        return top - 0.35 * (1.0 - lip)
    drop = min(sd / CLIFF_DROP, 1.0)
    below = max(0.0, sd - CLIFF_DROP) / 8.0
    ragged = 0.6 * noise.noise(Vector((x * 0.3, y * 0.3, 7.1)))
    return -0.35 + (SEA_LEVEL - 1.5 + 0.35) * drop - 4.0 * min(below, 1.0) + ragged * drop


def cliff_top():
    kit.reset()
    grass = material("grass", "#7fae57", roughness=0.9)
    grass_dry = material("grass_dry", "#a9b465", roughness=0.9)
    rock_light = material("rock_light", "#c8b79a", roughness=0.9)
    rock_dark = material("rock_dark", "#9c8b76", roughness=0.9)
    rock_wet = material("rock_wet", "#5e5a57", roughness=0.6)
    bm = bmesh.new()
    nx = int((EXTENT_X[1] - EXTENT_X[0]) / GRID_STEP) + 1
    ny = int((EXTENT_Y[1] - EXTENT_Y[0]) / GRID_STEP) + 1
    grid = []
    for j in range(ny):
        row = []
        for i in range(nx):
            x = EXTENT_X[0] + i * GRID_STEP
            y = EXTENT_Y[0] + j * GRID_STEP
            row.append(bm.verts.new((x, y, _ground_height(x, y))))
        grid.append(row)
    for j in range(ny - 1):
        for i in range(nx - 1):
            face = bm.faces.new((grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i]))
            centre = face.calc_center_median()
            face.normal_update()
            if centre.z < SEA_LEVEL + 0.8:
                face.material_index = 4
            elif face.normal.z > 0.82 and centre.z > -1.2:
                patch = noise.noise(Vector((centre.x * 0.09, centre.y * 0.09, 2.0)))
                face.material_index = 1 if patch > 0.35 else 0
            else:
                face.material_index = 2 if int(math.floor(centre.z / STRATUM)) % 2 == 0 else 3
    # Faces are wound counter-clockwise seen from above, so they already face
    # up. Recalculating normals on an open heightfield can flip it upside
    # down, which leaves the collision one-sided from below.
    mesh_object("cliff_top", bm, [grass, grass_dry, rock_light, rock_dark, rock_wet], smooth_angle=25,
                recalc=False, uv="none")
    kit.save("cliff_top", "assets/models/environment/cliff_top.glb")


# --------------------------------------------------------------------------
# Lighthouse
# --------------------------------------------------------------------------

def lighthouse():
    kit.reset()
    stone = material("stone", "#b7ab96", roughness=0.9)
    white = material("white", "#f2ede2", roughness=0.8)
    red = material("red", "#b8483b", roughness=0.7)
    iron = material("iron", "#3b3f44", metallic=0.3, roughness=0.6)
    glass = material("glass", "#ffe2a8", roughness=0.2)
    roof = material("roof", "#4d6f78", roughness=0.7)
    door = material("door", "#3f6a63", roughness=0.7)
    lamp_mat = material("lamp", "#fff1c8", roughness=0.3)
    mats = [stone, white, red, iron, glass, roof, door]
    STONE, WHITE, RED, IRON, GLASS, ROOF, DOOR = range(7)

    bm = bmesh.new()
    # Tower: a stone plinth, then a tapering white shaft with a red band.
    profile = [(0.0, 0.0), (2.5, 0.0), (2.5, 0.9), (2.1, 0.9), (1.95, 4.6), (1.85, 6.6),
               (1.7, 10.8), (1.7, 11.0), (0.0, 11.0)]
    band = [STONE, STONE, STONE, WHITE, RED, WHITE, WHITE, WHITE]
    lathe(bm, profile, 24, WHITE, mats=band)
    # Gallery deck and railing.
    lathe(bm, [(0.0, 11.0), (2.4, 11.0), (2.4, 11.22), (0.0, 11.22)], 24, IRON)
    posts = 18
    for k in range(posts):
        a = TAU * k / posts
        p = Vector((2.3 * math.cos(a), 2.3 * math.sin(a), 0.0))
        cylinder(bm, p + Vector((0, 0, 11.22)), p + Vector((0, 0, 12.05)), 0.035, 5, IRON)
    tube(bm, [(2.3 * math.cos(TAU * k / 36), 2.3 * math.sin(TAU * k / 36), 12.05) for k in range(36)],
         0.045, 5, IRON, closed=True)
    # Lantern room: glazing between iron mullions, under a domed cap.
    lathe(bm, [(0.0, 11.22), (1.15, 11.22), (1.15, 13.05), (0.0, 13.05)], 16, GLASS)
    for k in range(8):
        a = TAU * k / 8
        p = Vector((1.17 * math.cos(a), 1.17 * math.sin(a), 0.0))
        cylinder(bm, p + Vector((0, 0, 11.22)), p + Vector((0, 0, 13.05)), 0.05, 5, IRON)
    lathe(bm, [(0.0, 13.05), (1.35, 13.05), (1.3, 13.2), (1.0, 13.65), (0.55, 13.95), (0.0, 14.05)], 16, RED)
    cylinder(bm, (0, 0, 14.0), (0, 0, 14.5), 0.06, 6, IRON)
    lathe(bm, [(0.0, 14.45), (0.14, 14.55), (0.0, 14.68)], 8, IRON)
    # Door facing the land and small windows climbing the tower.
    box(bm, Vector((0.0, -2.08, 1.95)), (0.95, 0.3, 2.1), DOOR)
    for z, a in ((5.2, 0.4), (8.0, -0.5), (9.9, 0.9)):
        r = 1.95 - (z - 0.9) * 0.03
        box(bm, Vector((r * math.sin(a), -r * math.cos(a), z)), (0.42, 0.25, 0.7), DOOR, rot_z=a)

    # Keeper's cottage beside the tower, on the landward side.
    cx, cy = 3.9, -3.2
    box(bm, Vector((cx, cy, 0.35)), (5.6, 4.3, 0.7), STONE)
    box(bm, Vector((cx, cy, 1.95)), (5.2, 3.9, 2.5), WHITE)
    ridge = 4.6
    for side in (-1, 1):
        # Two roof slopes meeting at the ridge, overhanging the walls.
        slope = [(cx - 2.9, cy + side * 2.25, 3.1), (cx + 2.9, cy + side * 2.25, 3.1),
                 (cx + 2.9, cy, ridge), (cx - 2.9, cy, ridge)]
        pts = [Vector(p) for p in slope]
        thickness = Vector((0.0, 0.0, 0.14))
        base = [bm.verts.new(p) for p in pts]
        top = [bm.verts.new(p + thickness) for p in pts]
        faces = [bm.faces.new(base if side > 0 else list(reversed(base))),
                 bm.faces.new(list(reversed(top)) if side > 0 else top)]
        for i in range(4):
            j = (i + 1) % 4
            quad = (base[i], base[j], top[j], top[i]) if side < 0 else (base[j], base[i], top[i], top[j])
            faces.append(bm.faces.new(quad))
        for f in faces:
            f.material_index = ROOF
    # Gable ends.
    for gx in (cx - 2.6, cx + 2.6):
        box(bm, Vector((gx, cy, 3.75)), (0.18, 3.0, 1.0), WHITE, taper_top=(1.0, 0.1))
    box(bm, Vector((cx + 1.6, cy + 0.9, 4.6)), (0.55, 0.55, 1.6), STONE)
    box(bm, Vector((cx - 0.9, cy - 1.98, 1.55)), (0.9, 0.12, 1.9), DOOR)
    for wx in (cx + 0.9, cx + 2.0):
        box(bm, Vector((wx, cy - 1.98, 2.1)), (0.7, 0.12, 0.8), DOOR)
    tower = mesh_object("lighthouse", bm, mats, smooth_angle=30, uv="none")

    lamp_bm = bmesh.new()
    lathe(lamp_bm, [(0.0, 11.7), (0.35, 11.85), (0.45, 12.15), (0.35, 12.45), (0.0, 12.6)], 12, 0)
    mesh_object("lamp", lamp_bm, [lamp_mat], parent=tower, uv="none")
    kit.save("lighthouse", "assets/models/environment/lighthouse.glb")


# --------------------------------------------------------------------------
# Sea stack
# --------------------------------------------------------------------------

def sea_stack():
    kit.reset()
    rock_light = material("rock_light", "#c8b79a", roughness=0.9)
    rock_dark = material("rock_dark", "#9c8b76", roughness=0.9)
    grass = material("grass", "#8fb56a", roughness=0.9)
    bm = bmesh.new()
    rings = 9
    profile = []
    for k in range(rings + 1):
        z = -6.0 + k * (22.0 / rings)
        taper = 1.0 - 0.45 * (k / rings)
        profile.append((5.5 * taper, z))
    profile = [(0.0, -6.0)] + profile + [(0.0, profile[-1][1] + 0.6)]

    def ragged(p, angle, index):
        k = 1.0 + 0.28 * noise.noise(Vector((math.cos(angle) * 1.3, math.sin(angle) * 1.3, index * 0.7)))
        return Vector((p.x * k, p.y * k, p.z))

    bands = [1] + [0 if k % 2 else 1 for k in range(rings)] + [2]
    lathe(bm, profile, 14, 0, shape=ragged, mats=bands)
    mesh_object("sea_stack", bm, [rock_light, rock_dark, grass], smooth_angle=25, uv="none")
    kit.save("sea_stack", "assets/models/environment/sea_stack.glb")


# --------------------------------------------------------------------------
# Grass
# --------------------------------------------------------------------------

GRASS_TUFTS = 2600
GRASS_REGION_X = (-48.0, 34.0)
GRASS_REGION_Y = (-14.0, 66.0)
GRASS_SEED = 7


def _tuft(bm, base, rng, colour_layer):
    """A clump of five tapering blades leaning outward. Each blade vertex
    records how far up the blade it is (0 at the root, 1 at the tip) in the
    colour alpha, which the wind shader uses to sway only the tips."""
    blades = 5
    for b in range(blades):
        a = rng.uniform(0.0, TAU)
        lean = Vector((math.cos(a), math.sin(a), 0.0)) * rng.uniform(0.05, 0.16)
        height = rng.uniform(0.22, 0.45)
        width = rng.uniform(0.035, 0.055)
        side = Vector((-math.sin(a), math.cos(a), 0.0)) * width
        root = base + Vector((math.cos(a), math.sin(a), 0.0)) * rng.uniform(0.0, 0.06)
        mid = root + lean * 0.5 + Vector((0, 0, height * 0.55))
        tip = root + lean + Vector((0, 0, height))
        verts = [bm.verts.new(root - side), bm.verts.new(root + side),
                 bm.verts.new(mid + side * 0.6), bm.verts.new(mid - side * 0.6), bm.verts.new(tip)]
        faces = [bm.faces.new((verts[0], verts[1], verts[2], verts[3])), bm.faces.new((verts[3], verts[2], verts[4]))]
        for f in faces:
            f.material_index = 0
        for v, t in zip(verts, (0.0, 0.0, 0.55, 0.55, 1.0)):
            v[colour_layer] = (1.0, 1.0, 1.0, t)


def grass_field():
    import random
    kit.reset()
    blade = material("grass_blade", "#7fae57", roughness=0.9)
    bm = bmesh.new()
    colour_layer = bm.verts.layers.float_color.new("Color")
    rng = random.Random(GRASS_SEED)
    placed = 0
    attempts = 0
    while placed < GRASS_TUFTS and attempts < GRASS_TUFTS * 20:
        attempts += 1
        x = rng.uniform(*GRASS_REGION_X)
        y = rng.uniform(*GRASS_REGION_Y)
        if _coast_distance(x, y) > -0.8:
            continue
        if math.hypot(x, y) < 3.4:
            continue  # the cook's standing room and the view over the counter
        if math.hypot(x - LIGHTHOUSE_SPOT[0], y - LIGHTHOUSE_SPOT[1]) < 7.5:
            continue
        # Thicker grass away from the cook, in drifts.
        drift = noise.noise(Vector((x * 0.08, y * 0.08, 9.0)))
        if rng.random() > 0.55 + 0.45 * drift:
            continue
        _tuft(bm, Vector((x, y, _ground_height(x, y) - 0.02)), rng, colour_layer)
        placed += 1
    obj = mesh_object("grass_field", bm, [blade], smooth_angle=80, recalc=False, uv="none")
    obj.data.color_attributes.active_color = obj.data.color_attributes["Color"]
    kit.save("grass_field", "assets/models/environment/grass_field.glb", vertex_colors=True)
    print(f"grass tufts placed: {placed}")


MODELS = {f.__name__: f for f in (cliff_top, lighthouse, sea_stack, grass_field)}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    names = argv or list(MODELS)
    unknown = [n for n in names if n not in MODELS]
    if unknown:
        raise SystemExit(f"unknown model(s): {', '.join(unknown)}; known: {', '.join(MODELS)}")
    for name in names:
        MODELS[name]()


main()
