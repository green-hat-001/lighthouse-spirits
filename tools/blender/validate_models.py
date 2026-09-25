"""Check every built model against docs/models_needed.md.

    blender --background --factory-startup --python tools/blender/validate_models.py

Opens each models/<name>.blend and re-imports its .glb, then checks triangle
budget, bounds, origin, object and material names, identity transforms, pivots
and closed (manifold) meshes. Exits 1 on any failure.
"""

import math
import os
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

# name: glb path, triangle budget, expected overall size (m, None = unchecked),
# size tolerance, origin rule, objects (name -> type), material slots.
SPEC = {
    "potato": ("assets/models/ingredients/potato.glb", (300, 600), (0.090, 0.055, 0.045), 0.01, "bbox_base",
               {"potato": "MESH"}, {"skin", "flesh"}),
    "chilli": ("assets/models/ingredients/chilli.glb", (200, 400), (0.070, 0.018, 0.018), 0.01, "bbox_base",
               {"chilli": "MESH"}, {"skin", "stem", "flesh"}),
    "sunflower_head": ("assets/models/ingredients/sunflower_head.glb", (800, 1500), (0.25, None, None), 0.10,
                       "disc_back", {"sunflower_head": "MESH"}, {"petals", "seed_disc", "stem"}),
    "sunflower_seed": ("assets/models/ingredients/sunflower_seed.glb", (1, 39), (0.010, 0.005, 0.003), 0.01,
                       "bbox_base", {"sunflower_seed": "MESH"}, {"kernel"}),
    "gas_stove": ("assets/models/equipment/gas_stove.glb", (800, 1500), (0.30, None, 0.10), 0.12, "base",
                  {"body": "MESH", "grate": "MESH", "burner_cap": "MESH", "knob": "MESH", "flame_anchor": "EMPTY"},
                  {"enamel", "iron", "brass", "burner"}),
    "pot": ("assets/models/equipment/pot.glb", (600, 1200), (None, 0.186, 0.123), 0.02, "base",
            {"body": "MESH", "liquid_surface": "MESH"}, {"metal", "handles", "liquid"}),
    "slotted_spoon": ("assets/models/equipment/slotted_spoon.glb", (300, 600), (0.32, 0.08, None), 0.03,
                      "handle_end", {"slotted_spoon": "MESH"}, {"metal", "wood"}),
    "water_jug": ("assets/models/equipment/water_jug.glb", (300, 600), (0.12, None, 0.20), 0.12, "base",
                  {"body": "MESH", "pour_point": "EMPTY"}, {"ceramic"}),
    "oil_bottle": ("assets/models/equipment/oil_bottle.glb", (300, 600), (0.07, 0.07, 0.25), 0.03, "base",
                   {"body": "MESH", "cork": "MESH", "pour_point": "EMPTY"}, {"glass", "oil", "cork"}),
    "oil_press": ("assets/models/equipment/oil_press.glb", (1500, 3000), (0.35, 0.15, 0.30), 0.15, "base",
                  {"frame": "MESH", "hopper": "MESH", "barrel": "MESH", "crank": "MESH",
                   "oil_spout": "EMPTY", "cake_outlet": "EMPTY"}, {"iron", "wood", "brass"}),
    "oil_cup": ("assets/models/equipment/oil_cup.glb", (200, 400), (0.08, 0.08, 0.07), 0.12, "base",
                {"body": "MESH", "oil_surface": "MESH", "pour_point": "EMPTY"}, {"ceramic", "oil"}),
    "sunflower_seed_cake": ("assets/models/ingredients/sunflower_seed_cake.glb", (1, 149), (0.040, 0.012, 0.012),
                            0.01, "bbox_base", {"sunflower_seed_cake": "MESH"}, {"cake"}),
    "mezzaluna": ("assets/models/tools/mezzaluna.glb", (400, 800), (None, 0.02, None), 0.10, "edge_centre",
                  {"BladePivot": "EMPTY", "Blade": "MESH", "HandleLeft": "MESH", "HandleRight": "MESH"},
                  {"steel", "wood"}),
    "cutting_board": ("assets/models/tools/cutting_board.glb", (200, 400), (0.40, 0.28, 0.02), 0.01, "top",
                      {"cutting_board": "MESH"}, {"wood"}),
    "basket": ("assets/models/pantry/basket.glb", (400, 800), (0.14, 0.14, 0.06), 0.03, "base",
               {"basket": "MESH"}, {"wicker"}),
    "counter": ("assets/models/kitchen/counter.glb", (300, 800), (1.6, 0.6, 0.9), 0.01, "top",
                {"counter": "MESH"}, {"top", "base"}),
    # The outdoor setting (tools/blender/build_environment.py). The terrain and
    # grass are positioned around the kitchen origin, so their origin is not
    # checked.
    "cliff_top": ("assets/models/environment/cliff_top.glb", (15000, 20000), (120.0, 122.0, None), 0.02, "none",
                  {"cliff_top": "MESH"}, {"grass", "grass_dry", "rock_light", "rock_dark", "rock_wet"}),
    "lighthouse": ("assets/models/environment/lighthouse.glb", (1200, 2500), (None, None, 14.68), 0.02, "none",
                   {"lighthouse": "MESH", "lamp": "MESH"},
                   {"stone", "white", "red", "iron", "glass", "roof", "door", "lamp"}),
    "sea_stack": ("assets/models/environment/sea_stack.glb", (200, 600), (None, None, 22.6), 0.05, "none",
                  {"sea_stack": "MESH"}, {"rock_light", "rock_dark", "grass"}),
    "grass_field": ("assets/models/environment/grass_field.glb", (35000, 40000), (None, None, None), 0.0, "none",
                    {"grass_field": "MESH"}, {"grass_blade"}),
}

# Parts whose origin is a pivot: name -> expected world location.
PIVOTS = {
    "gas_stove": {"knob": (0, -0.150, 0.038)},
    "oil_press": {"crank": (0.116, 0, 0.130)},
    "mezzaluna": {"BladePivot": (0, 0, 0)},
}
# Flat single-face discs are the only open meshes allowed.
OPEN_MESHES = {"liquid_surface", "oil_surface", "cliff_top", "grass_field"}

failures = []


def check(ok, model, message):
    print(("  ok    " if ok else "  FAIL  ") + message)
    if not ok:
        failures.append(f"{model}: {message}")


def world_bounds(objs):
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p[i] for p in pts) for i in range(3)))
    hi = Vector((max(p[i] for p in pts) for i in range(3)))
    return lo, hi


def triangles(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def non_manifold(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bad = sum(1 for e in bm.edges if not e.is_manifold)
    bm.free()
    return bad


def validate(name):
    glb, budget, size, tol, origin, objects, slots = SPEC[name]
    print(f"\n{name}")
    blend = os.path.join(ROOT, "models", name + ".blend")
    check(os.path.isfile(blend), name, f"models/{name}.blend exists")
    check(os.path.isfile(os.path.join(ROOT, glb)), name, f"{glb} exists")
    bpy.ops.wm.open_mainfile(filepath=blend)
    scene_objs = {o.name: o for o in bpy.context.scene.objects}
    check(set(scene_objs) == set(objects), name, f"objects {sorted(scene_objs)}")
    for oname, otype in objects.items():
        if oname in scene_objs:
            check(scene_objs[oname].type == otype, name, f"{oname} is {otype}")
    for o in scene_objs.values():
        check(tuple(o.rotation_euler) == (0, 0, 0) and tuple(o.scale) == (1, 1, 1), name,
              f"{o.name} has identity rotation and scale")
    meshes = [o for o in scene_objs.values() if o.type == "MESH"]
    used_slots = {m.name for o in meshes for m in o.data.materials}
    check(used_slots == slots, name, f"material slots {sorted(used_slots)}")
    tris = sum(triangles(o) for o in meshes)
    check(budget[0] <= tris <= budget[1], name, f"{tris} triangles (budget {budget[0]}-{budget[1]})")
    for o in meshes:
        if o.name not in OPEN_MESHES:
            bad = non_manifold(o)
            check(bad == 0, name, f"{o.name} is closed ({bad} non-manifold edges)")

    lo, hi = world_bounds(meshes)
    dims = hi - lo
    print(f"  size  {dims.x:.4f} x {dims.y:.4f} x {dims.z:.4f} m, bounds z {lo.z:.4f}..{hi.z:.4f}")
    for axis, want in zip("xyz", size):
        if want is not None:
            got = getattr(dims, axis)
            check(abs(got - want) <= want * tol, name, f"{axis} size {got:.4f} ~ {want} (+/-{tol:.0%})")

    eps = 1e-4
    if origin == "base":
        check(abs(lo.z) < eps, name, "rests on Z = 0")
        # the footprint: every vertex within 2 mm of the surface it rests on
        foot = [o.matrix_world @ v.co for o in meshes for v in o.data.vertices]
        foot = [p for p in foot if p.z < lo.z + 0.002]
        centre = Vector((min(p.x for p in foot) + max(p.x for p in foot),
                         min(p.y for p in foot) + max(p.y for p in foot), 0)) / 2
        check(abs(centre.x) < 1e-3 and abs(centre.y) < 1e-3, name,
              f"footprint centred on origin ({centre.x:.4f}, {centre.y:.4f})")
    elif origin == "bbox_base":  # organic shapes: bounds centred, resting on Z = 0
        check(abs(lo.z) < eps, name, "rests on Z = 0")
        check(abs(lo.x + hi.x) < eps and abs(lo.y + hi.y) < eps, name, "bounds centred on origin")
    elif origin == "top":
        check(abs(hi.z) < eps, name, "top surface at Z = 0")
        check(abs(lo.x + hi.x) < eps and abs(lo.y + hi.y) < 2e-3, name, "centred in X and Y")
    elif origin == "handle_end":
        check(abs(lo.x) < eps, name, "origin at the end of the handle")
    elif origin == "disc_back":
        mesh = meshes[0].data
        near = min(mesh.vertices, key=lambda v: v.co.length)
        check(near.co.length < 0.006, name, f"origin on the back of the seed disc ({near.co.length * 1000:.1f} mm)")
    elif origin == "edge_centre":
        blade = scene_objs["Blade"]
        blo, bhi = world_bounds([blade])
        check(abs(blo.z) < eps, name, "BladePivot on the lowest point of the cutting edge")
        check(abs((bhi.x - blo.x) - 0.17) < 0.005, name, f"blade tip to tip {bhi.x - blo.x:.4f} ~ 0.17")
        mid = [v.co for v in blade.data.vertices if abs(v.co.x) < 1e-6]
        depth = max(v.z for v in mid) - min(v.z for v in mid)
        check(abs(depth - 0.05) < 0.002, name, f"blade depth at centre {depth:.4f} ~ 0.05")
        thick = bhi.y - blo.y
        check(abs(thick - 0.0025) < 1e-4, name, f"blade thickness {thick * 1000:.2f} mm")
        for h in ("HandleLeft", "HandleRight"):
            o = scene_objs[h]
            check(o.parent == scene_objs["BladePivot"], name, f"{h} parented to BladePivot")
            hlo, hhi = world_bounds([o])
            check(abs((hhi.z - hlo.z) - 0.078) < 0.01, name, f"{h} rises {hhi.z - hlo.z:.3f} m (0.07 grip)")
        check(blade.parent == scene_objs["BladePivot"], name, "Blade parented to BladePivot")
    for oname, loc in PIVOTS.get(name, {}).items():
        got = scene_objs[oname].matrix_world.translation
        check((got - Vector(loc)).length < 1e-5, name, f"{oname} pivot at {tuple(round(c, 4) for c in got)}")
    if name == "oil_press":  # the oil cup (0.086 m wide with spout, 0.073 m tall) stands under the spout
        spout = scene_objs["oil_spout"].matrix_world.translation
        frame = scene_objs["frame"]
        feet = [p for p in (frame.matrix_world @ v.co for v in frame.data.vertices) if p.z < 0.020]
        gap_lo = max(p.x for p in feet if p.x < spout.x)
        gap_hi = min(p.x for p in feet if p.x > spout.x)
        check(gap_lo < spout.x - 0.043 and spout.x + 0.043 < gap_hi and spout.z > 0.073, name,
              f"oil cup fits under the spout between the feet ({gap_lo:.3f}..{gap_hi:.3f}, spout z {spout.z:.3f})")
    for o in meshes:
        if "interior_volume_ml" in o:
            print(f"  info  {o.name} interior {o['interior_volume_ml']} ml")

    # Re-import the glb: names survive, and every slot a face uses is exported.
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT, glb))
    imported = {o.name for o in bpy.context.scene.objects}
    check(set(objects) <= imported, name, "glb keeps every object name")
    glb_slots = {m.name for m in bpy.data.materials}
    dropped = slots - glb_slots
    if dropped:
        print(f"  note  glb omits unused reserved slot(s) {sorted(dropped)}; they stay in the .blend")
    check(glb_slots <= slots and slots - glb_slots <= {"flesh"}, name, f"glb materials {sorted(glb_slots)}")
    return tris


def main():
    for name in SPEC:
        validate(name)
    print()
    if failures:
        print(f"VALIDATION FAILED ({len(failures)}):")
        for f in failures:
            print("  " + f)
        sys.exit(1)
    print(f"VALIDATION PASSED: {len(SPEC)} models")


main()
