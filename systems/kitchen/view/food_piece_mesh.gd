class_name FoodPieceMesh
extends RefCounted

## Builds the mesh of one cut piece of food from what the simulation knows
## about it: its size and which of its six faces still carry skin. The
## mesh fills exactly the piece's box, so what the player sees is what the
## simulation cuts, and it is never rotated off the box's axes.
##
## Each face rounds over at its edges by its own radius: a face with skin
## rounds generously (FoodLook.roundness of its half-depth), a face the
## knife made keeps only the knife's tiny bevel. Where two skin faces meet
## the piece is as round as the whole was; where two cuts meet the edge is
## crisp; and a cut face's outline takes the curve of the skin around it,
## the way the inside of a halved potato is an oval. Skin faces are also
## dimpled inward by a little noise (never outward, so the mesh stays in
## the box); cut faces stay flat.
##
## The rounding is a rounded box with a different radius on each side:
## a point p on the box is clamped into the box shrunk by the radii, and
## pushed back out along the ellipsoid those radii make. Neighbouring faces
## map their shared edge identically, so there are no seams.
##
## Vertex data for the food shader, in UV2: x is how much of the surface
## there is skin (by the normal, so the skin stops crisply at the cut), y is
## nearness to an edge (edges brown first). The mesh is in metres with its
## origin at the piece's minimum corner, like the piece's box.

const MM_TO_M: float = 0.001
## The smallest radius any edge is given, in mm.
const MIN_RADIUS_MM: float = 0.25
## Samples across a generous rounding, and across a knife bevel.
const ROUND_STEPS: int = 3
const BEVEL_STEPS: int = 1
## Longest spacing between samples across a flat face, in mm.
const INTERIOR_STEP_MM: float = 9.0
## How far in from an edge the edge browning reaches, in mm.
const EDGE_BAND_MM: float = 1.8
## Only edges this tight brown ahead of their faces: a crisp knife edge,
## not the broad curve of skin.
const CRISP_EDGE_MM: float = 1.5

## Meshes already built, by key: many pieces share a size (a tray of fries).
const CACHE_LIMIT: int = 256
static var _cache: Dictionary = {}
static var _noise: FastNoiseLite

## The mesh for a piece of `size_mm` whose faces (FoodPiece.Face order)
## have `skin` (0 cut flesh to 1 skin).
static func build(size_mm: Vector3, skin: PackedFloat64Array, look: FoodLook) -> ArrayMesh:
	var key := _key(size_mm, skin, look)
	if _cache.has(key):
		return _cache[key]
	var mesh := _build(size_mm, skin, look)
	if _cache.size() >= CACHE_LIMIT:
		_cache.erase(_cache.keys()[0])
	_cache[key] = mesh
	return mesh

static func _key(size_mm: Vector3, skin: PackedFloat64Array, look: FoodLook) -> String:
	var parts := PackedStringArray()
	for axis in 3:
		parts.append(str(snappedf(size_mm[axis], 0.1)))
	for value in skin:
		parts.append(str(snappedf(value, 0.05)))
	parts.append(str(look.get_instance_id()))
	return ",".join(parts)

## The rounding radius of a face, along its own axis, in mm.
static func face_radius(size_mm: Vector3, skin: PackedFloat64Array, look: FoodLook, face: int) -> float:
	var axis: int = face / 2
	var skin_radius: float = look.roundness * size_mm[axis] * 0.5
	var radius: float = lerpf(look.cut_edge_mm, maxf(skin_radius, look.cut_edge_mm), clampf(skin[face], 0.0, 1.0))
	return clampf(radius, MIN_RADIUS_MM, maxf(size_mm[axis] * 0.49, MIN_RADIUS_MM * 0.5))

static func _build(size_mm: Vector3, skin: PackedFloat64Array, look: FoodLook) -> ArrayMesh:
	if _noise == null:
		_noise = FastNoiseLite.new()
		_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		_noise.seed = 7
	var r_neg := Vector3.ZERO
	var r_pos := Vector3.ZERO
	for axis in 3:
		r_pos[axis] = face_radius(size_mm, skin, look, axis * 2)
		r_neg[axis] = face_radius(size_mm, skin, look, axis * 2 + 1)
	var samples: Array[PackedFloat64Array] = []
	for axis in 3:
		samples.append(_axis_samples(size_mm[axis], r_neg[axis], r_pos[axis]))

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var data := PackedVector2Array()
	var indices := PackedInt32Array()
	var frequency: float = 1.0 / maxf(look.wobble_size_mm, 0.5)
	for face in 6:
		var axis: int = face / 2
		var positive: bool = face % 2 == 0
		var b: int = (axis + 1) % 3
		var c: int = (axis + 2) % 3
		var along_b := samples[b]
		var along_c := samples[c]
		var first: int = vertices.size()
		for i in along_b.size():
			for j in along_c.size():
				var p := Vector3.ZERO
				p[axis] = size_mm[axis] if positive else 0.0
				p[b] = along_b[i]
				p[c] = along_c[j]
				_emit(p, size_mm, r_neg, r_pos, skin, look, frequency, axis, b, c, vertices, normals, data)
		# Quads, wound clockwise seen from outside (Godot's front face).
		var columns: int = along_c.size()
		var flip: bool = positive
		for i in along_b.size() - 1:
			for j in columns - 1:
				var v00: int = first + i * columns + j
				var v01: int = v00 + 1
				var v10: int = v00 + columns
				var v11: int = v10 + 1
				if flip:
					indices.append_array([v00, v01, v11, v00, v11, v10])
				else:
					indices.append_array([v00, v11, v01, v00, v10, v11])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV2] = data
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## Where to sample one axis of the box: densely through each rounding,
## once at the edge-browning band, and evenly across the flat between.
static func _axis_samples(extent: float, r_low: float, r_high: float) -> PackedFloat64Array:
	var points := PackedFloat64Array()
	var steps_low: int = ROUND_STEPS if r_low > 1.5 else BEVEL_STEPS
	var steps_high: int = ROUND_STEPS if r_high > 1.5 else BEVEL_STEPS
	for k in steps_low + 1:
		points.append(r_low * (1.0 - cos(float(k) / steps_low * PI * 0.5)))
	var flat_from: float = r_low
	var flat_to: float = extent - r_high
	var inner := PackedFloat64Array()
	if flat_to - flat_from > EDGE_BAND_MM * 2.5:
		inner.append(flat_from + EDGE_BAND_MM)
		inner.append(flat_to - EDGE_BAND_MM)
	var span_from: float = inner[0] if not inner.is_empty() else flat_from
	var span_to: float = inner[1] if not inner.is_empty() else flat_to
	var gaps: int = maxi(ceili((span_to - span_from) / INTERIOR_STEP_MM), 1)
	if not inner.is_empty():
		points.append(inner[0])
	for k in range(1, gaps):
		points.append(lerpf(span_from, span_to, float(k) / gaps))
	if not inner.is_empty():
		points.append(inner[1])
	for k in range(steps_high, -1, -1):
		points.append(extent - r_high * (1.0 - cos(float(k) / steps_high * PI * 0.5)))
	points.sort()
	var unique := PackedFloat64Array()
	for value in points:
		if unique.is_empty() or value - unique[unique.size() - 1] > 0.05:
			unique.append(value)
	unique[unique.size() - 1] = extent
	return unique

static func _emit(p: Vector3, size_mm: Vector3, r_neg: Vector3, r_pos: Vector3, skin: PackedFloat64Array,
		look: FoodLook, frequency: float, axis: int, b: int, c: int,
		vertices: PackedVector3Array, normals: PackedVector3Array, data: PackedVector2Array) -> void:
	var q := Vector3.ZERO
	var radius := Vector3.ZERO
	var unit := Vector3.ZERO
	for i in 3:
		q[i] = clampf(p[i], r_neg[i], size_mm[i] - r_pos[i])
		var d: float = p[i] - q[i]
		radius[i] = r_neg[i] if d < 0.0 else r_pos[i]
		unit[i] = d / radius[i]
	unit = unit.normalized()
	var surface := q + unit * radius
	var normal := Vector3(unit.x / radius.x, unit.y / radius.y, unit.z / radius.z).normalized()
	var skin_share: float = 0.0
	for i in 3:
		var face: int = i * 2 + (0 if normal[i] >= 0.0 else 1)
		skin_share += normal[i] * normal[i] * skin[face]
	# Only skin dimples: a knife leaves its face flat.
	var wobble: float = look.wobble_mm * skin_share * skin_share
	if wobble > 0.0:
		var n: float = _noise.get_noise_3d(surface.x * frequency * 100.0, surface.y * frequency * 100.0, surface.z * frequency * 100.0)
		surface -= normal * wobble * (0.5 + 0.5 * n)
	# Distance to the nearest crisp edge of this face (both faces meeting
	# there have only a knife's bevel).
	var to_edge: float = INF
	var own: float = r_pos[axis] if p[axis] > size_mm[axis] * 0.5 else r_neg[axis]
	if own < CRISP_EDGE_MM:
		for side_axis: int in [b, c]:
			if r_neg[side_axis] < CRISP_EDGE_MM:
				to_edge = minf(to_edge, p[side_axis])
			if r_pos[side_axis] < CRISP_EDGE_MM:
				to_edge = minf(to_edge, size_mm[side_axis] - p[side_axis])
	vertices.append(surface * MM_TO_M)
	normals.append(normal)
	data.append(Vector2(skin_share, 0.0 if is_inf(to_edge) else 1.0 - smoothstep(0.0, EDGE_BAND_MM, to_edge)))
