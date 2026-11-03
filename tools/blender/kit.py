"""Shared geometry, material and export helpers for the Lighthouse Spirits model kit.

Every model is built procedurally in mesh space, so object transforms stay at
identity (location only, for pivoted parts) and a rebuild is deterministic.
Axes follow docs/models_needed.md: X is length, Y is depth, Z is height.
"""

import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
BLEND_DIR = os.path.join(ROOT, "models")


# --------------------------------------------------------------------------
# Scene and materials
# --------------------------------------------------------------------------

def reset():
    """Start every model from an empty factory scene."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 backups
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.scale_length = 1.0


def _linear(channel):
    return channel / 12.92 if channel <= 0.04045 else ((channel + 0.055) / 1.055) ** 2.4


def srgb(hex_colour):
    """'#rrggbb' in sRGB to a linear RGB tuple, as Principled BSDF expects."""
    h = hex_colour.lstrip("#")
    return tuple(_linear(int(h[i:i + 2], 16) / 255.0) for i in (0, 2, 4))


def material(name, hex_colour, metallic=0.0, roughness=0.8, alpha=1.0, image=None):
    """A flat-colour slot material. The cel shader replaces it per slot in Godot."""
    mat = bpy.data.materials.new(name)
    if hasattr(mat, "use_nodes"):
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    rgb = srgb(hex_colour)
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Alpha"].default_value = alpha
    mat.diffuse_color = (*rgb, alpha)
    mat.metallic = metallic
    mat.roughness = roughness
    if alpha < 1.0:
        if hasattr(mat, "surface_render_method"):
            mat.surface_render_method = "BLENDED"
        elif hasattr(mat, "blend_method"):
            mat.blend_method = "BLEND"
    if image is not None:
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.location = (-400, 200)
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return mat


# --------------------------------------------------------------------------
# Geometry primitives. All of them write into a caller-owned BMesh and tag
# faces with a material index into the object's slot list.
# --------------------------------------------------------------------------

def _tag(faces, mat_index, smooth=True):
    for f in faces:
        f.material_index = mat_index
        f.smooth = smooth
    return faces


def lathe(bm, profile, segments, mat_index, center=(0, 0, 0), shape=None,
          closed=False, mats=None):
    """Revolve a (radius, z) profile around a vertical axis.

    Walk the profile so the solid is on the left (bottom centre outward, up the
    outside, over the rim, down the inside): faces then point outward. A radius
    of 0 collapses a ring into a pole. `shape(p, angle, index)` may displace a
    vertex; `mats` optionally gives a material index per profile band.
    """
    c = Vector(center)
    rings = []
    for i, (r, z) in enumerate(profile):
        if r == 0:
            p = Vector((0.0, 0.0, z))
            rings.append([bm.verts.new(c + (shape(p, 0.0, i) if shape else p))])
            continue
        ring = []
        for s in range(segments):
            a = 2.0 * math.pi * s / segments
            p = Vector((r * math.cos(a), r * math.sin(a), z))
            if shape:
                p = shape(p, a, i)
            ring.append(bm.verts.new(c + p))
        rings.append(ring)
    count = len(rings) if closed else len(rings) - 1
    faces = []
    for i in range(count):
        a_ring, b_ring = rings[i], rings[(i + 1) % len(rings)]
        band = []
        for s in range(segments):
            s1 = (s + 1) % segments
            if len(a_ring) == 1 and len(b_ring) == 1:
                continue
            if len(a_ring) == 1:
                band.append(bm.faces.new((a_ring[0], b_ring[s1], b_ring[s])))
            elif len(b_ring) == 1:
                band.append(bm.faces.new((a_ring[s], a_ring[s1], b_ring[0])))
            else:
                band.append(bm.faces.new((a_ring[s], a_ring[s1], b_ring[s1], b_ring[s])))
        _tag(band, mats[i] if mats else mat_index)
        faces += band
    return rings, faces


def tube(bm, path, radii, sides, mat_index, up=(0, 0, 1), closed=False,
         cap_start=True, cap_end=True, shape=None):
    """Sweep a cross-section along a polyline with parallel-transport frames.

    `radii` is a list with one entry per path point, or a single entry used
    for all of them. An entry is a float or an (r_normal, r_binormal) tuple for
    an elliptical section, with the normal seeded from `up`. A radius of 0
    collapses that ring into a pole. `shape(angle, index)` scales the radius
    per vertex.
    """
    pts = [Vector(p) for p in path]
    n_pts = len(pts)
    if not isinstance(radii, list):
        radii = [radii] * n_pts
    tangents = []
    for i in range(n_pts):
        if closed:
            t = pts[(i + 1) % n_pts] - pts[i - 1]
        elif i == 0:
            t = pts[1] - pts[0]
        elif i == n_pts - 1:
            t = pts[-1] - pts[-2]
        else:
            t = (pts[i + 1] - pts[i]).normalized() + (pts[i] - pts[i - 1]).normalized()
        tangents.append(t.normalized())
    ref = Vector(up)
    if abs(ref.normalized().dot(tangents[0])) > 0.95:
        ref = Vector((1, 0, 0)) if abs(tangents[0].x) < 0.9 else Vector((0, 1, 0))
    normal = (ref - tangents[0] * ref.dot(tangents[0])).normalized()
    rings = []
    for i, (p, t) in enumerate(zip(pts, tangents)):
        normal = (normal - t * normal.dot(t)).normalized()
        binormal = t.cross(normal)
        r = radii[i]
        rn, rb = (r, r) if not isinstance(r, (list, tuple)) else r
        if rn == 0 and rb == 0:
            rings.append([bm.verts.new(p)])
            continue
        ring = []
        for s in range(sides):
            a = 2.0 * math.pi * s / sides
            k = shape(a, i) if shape else 1.0
            ring.append(bm.verts.new(p + (normal * math.cos(a) * rn + binormal * math.sin(a) * rb) * k))
        rings.append(ring)
    faces = []
    count = n_pts if closed else n_pts - 1
    for i in range(count):
        a_ring, b_ring = rings[i], rings[(i + 1) % n_pts]
        for s in range(sides):
            s1 = (s + 1) % sides
            if len(a_ring) == 1:
                faces.append(bm.faces.new((a_ring[0], b_ring[s1], b_ring[s])))
            elif len(b_ring) == 1:
                faces.append(bm.faces.new((a_ring[s], a_ring[s1], b_ring[0])))
            else:
                faces.append(bm.faces.new((a_ring[s], a_ring[s1], b_ring[s1], b_ring[s])))
    if not closed:
        if cap_start and len(rings[0]) > 1:
            faces.append(bm.faces.new(list(reversed(rings[0]))))
        if cap_end and len(rings[-1]) > 1:
            faces.append(bm.faces.new(rings[-1]))
    _tag(faces, mat_index)
    return rings, faces


def cylinder(bm, start, end, radius, sides, mat_index, up=(0, 0, 1)):
    return tube(bm, [start, end], [radius, radius], sides, mat_index, up=up)


def merge(bm, sub):
    """Append the geometry of `sub` (which is freed) to `bm`."""
    tmp = bpy.data.meshes.new("_merge")
    sub.to_mesh(tmp)
    sub.free()
    bm.from_mesh(tmp)
    bpy.data.meshes.remove(tmp)


def box_bm(center, size, mat_index, rot_z=0.0, bevel=0.0, segments=1, taper_top=None,
           bevel_filter=None):
    """A standalone box BMesh, optionally tapered at the top (x, y scale),
    rotated about Z and bevelled. `bevel_filter(edge)` limits which edges are
    bevelled; it sees the box scaled but still centred on the origin."""
    sub = bmesh.new()
    bmesh.ops.create_cube(sub, size=1.0)
    for v in sub.verts:
        x, y, z = v.co
        if taper_top and z > 0:
            x *= taper_top[0]
            y *= taper_top[1]
        v.co = Vector((x * size[0], y * size[1], z * size[2]))
    _tag(sub.faces, mat_index, smooth=False)
    if bevel > 0:
        edges = [e for e in sub.edges if bevel_filter is None or bevel_filter(e)]
        bmesh.ops.bevel(sub, geom=edges, offset=bevel, segments=segments,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.transform(sub, matrix=Matrix.Translation(center) @ Matrix.Rotation(rot_z, 4, "Z"),
                        verts=sub.verts)
    return sub


def box(bm, center, size, mat_index, **kwargs):
    merge(bm, box_bm(center, size, mat_index, **kwargs))


def prism(bm, outline, direction, mat_index):
    """Extrude a planar polygon (listed counter-clockwise when looking against
    `direction`) along `direction`."""
    base = [bm.verts.new(Vector(p)) for p in outline]
    d = Vector(direction)
    top = [bm.verts.new(v.co + d) for v in base]
    n = len(base)
    faces = [bm.faces.new(list(reversed(base))), bm.faces.new(top)]
    for i in range(n):
        j = (i + 1) % n
        faces.append(bm.faces.new((base[i], base[j], top[j], top[i])))
    _tag(faces, mat_index, smooth=False)
    return faces


def disc(bm, center, radius, sides, mat_index):
    """A flat upward-facing disc (one n-gon)."""
    c = Vector(center)
    verts = [bm.verts.new(c + Vector((radius * math.cos(2 * math.pi * s / sides),
                                      radius * math.sin(2 * math.pi * s / sides), 0)))
             for s in range(sides)]
    return _tag([bm.faces.new(verts)], mat_index)


def bumpy(p, scale, amount, seed):
    """Deterministic Perlin displacement factor, 1 +/- amount."""
    return 1.0 + amount * noise.noise(p * scale + Vector((seed * 1.37, seed * 2.11, seed * 0.73)))


def fit_to_box(bm, size, anchor="base"):
    """Scale and move all vertices so the bounds equal `size` exactly.

    anchor 'base': centred in X/Y, resting on Z = 0. 'top': top at Z = 0.
    """
    lo = Vector((min(v.co[i] for v in bm.verts) for i in range(3)))
    hi = Vector((max(v.co[i] for v in bm.verts) for i in range(3)))
    dims = hi - lo
    for v in bm.verts:
        rel = v.co - lo
        v.co = Vector((rel.x / dims.x * size[0] - size[0] / 2,
                       rel.y / dims.y * size[1] - size[1] / 2,
                       rel.z / dims.z * size[2] - (size[2] if anchor == "top" else 0.0)))


# --------------------------------------------------------------------------
# Objects
# --------------------------------------------------------------------------

def mesh_object(name, bm, mats, location=(0, 0, 0), parent=None, smooth_angle=35.0,
                recalc=True, uv="smart"):
    """Turn a BMesh into a linked object with its slot materials.

    Edges sharper than `smooth_angle` (or between materials) are marked sharp so
    the cel shader gets crisp creases and soft curves.
    """
    if recalc:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    for f in bm.faces:
        f.smooth = True
    limit = math.radians(smooth_angle)
    for e in bm.edges:
        faces = e.link_faces
        if len(faces) != 2:
            e.smooth = False
            continue
        crease = faces[0].material_index != faces[1].material_index
        e.smooth = not crease and e.calc_face_angle(math.pi) <= limit
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for m in mats:
        mesh.materials.append(m)
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
    if uv == "smart":
        _smart_uv(obj)
    return obj


def _smart_uv(obj):
    view_layer = bpy.context.view_layer
    for o in view_layer.objects:
        o.select_set(False)
    view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.02)
    bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)


def empty(name, location, parent=None, size=0.01, display="PLAIN_AXES"):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = display
    obj.empty_display_size = size
    obj.location = location
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
    return obj


def cavity_volume_ml(profile, segments):
    """Volume of a closed lathe profile (litres * 1000), used to prove that
    vessels hold what their equipment data says."""
    bm = bmesh.new()
    lathe(bm, profile, segments, 0)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    volume = abs(bm.calc_volume(signed=False)) * 1e6
    bm.free()
    return volume


# --------------------------------------------------------------------------
# Save and export
# --------------------------------------------------------------------------

def _frame_viewports():
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if not objs:
        return
    pts = [o.matrix_world @ Vector(c) for o in objs for c in o.bound_box]
    lo = Vector((min(p[i] for p in pts) for i in range(3)))
    hi = Vector((max(p[i] for p in pts) for i in range(3)))
    for screen in bpy.data.screens:
        for area in screen.areas:
            for space in area.spaces:
                if space.type != "VIEW_3D":
                    continue
                space.clip_start = 0.0005
                space.clip_end = 100.0
                r3d = space.region_3d
                if r3d is not None:
                    r3d.view_location = (lo + hi) / 2
                    r3d.view_distance = max((hi - lo).length * 1.6, 0.03)


def save(slug, glb_rel, vertex_colors=False):
    """Write models/<slug>.blend and export <glb_rel> as binary glTF.

    With `vertex_colors`, the active colour attribute is exported even though
    no material reads it (a Godot shader does)."""
    for obj in bpy.context.scene.objects:
        assert tuple(obj.rotation_euler) == (0.0, 0.0, 0.0), obj.name
        assert tuple(obj.scale) == (1.0, 1.0, 1.0), obj.name
    _frame_viewports()
    if vertex_colors:
        # The exporter's "active" colour is the one marked for rendering.
        for obj in bpy.context.scene.objects:
            if obj.type == "MESH" and obj.data.color_attributes.active_color is not None:
                obj.data.color_attributes.render_color_index = obj.data.color_attributes.active_color_index
    os.makedirs(BLEND_DIR, exist_ok=True)
    blend_path = os.path.join(BLEND_DIR, slug + ".blend")
    bpy.ops.wm.save_as_mainfile(filepath=blend_path, compress=True)
    glb_path = os.path.join(ROOT, glb_rel)
    os.makedirs(os.path.dirname(glb_path), exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=glb_path,
        export_format="GLB",
        export_apply=True,
        export_yup=True,
        export_extras=True,
        export_materials="EXPORT",
        use_selection=False,
        # Only the active attribute, as COLOR_0: by default the exporter also
        # writes a fake white COLOR_0 and moves the real one to COLOR_1.
        **({"export_vertex_color": "ACTIVE", "export_all_vertex_colors": False} if vertex_colors else {}),
    )
    print(f"SAVED {slug}: {os.path.relpath(blend_path, ROOT)} + {glb_rel}")
