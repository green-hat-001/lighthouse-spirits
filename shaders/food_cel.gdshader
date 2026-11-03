shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Cel-shaded food. Every parameter below is driven from the simulation
// through FoodAppearance, so the player judges doneness by eye: raw flesh
// turns glassy as it cooks, a dry surface goes golden then brown (its edges
// first), a crust blisters, burnt patches blacken and crack, oil makes it
// shine, and cooked fillets curl.
//
// Browning, char, skin and wetness are per face of the piece's box, as
// (+X, +Y, +Z) and (-X, -Y, -Z). Food is never rotated off the world's
// axes in the kitchen, so the world normal picks the face; on a rounded
// surface the faces blend by how squarely it faces each way.
//
// Two kinds of mesh wear it:
// - a cut piece's body (FoodPieceMesh), with vertex_data on: UV2.x is how
//   much of the surface there is skin, UV2.y how near it is to an edge;
// - a whole model, with vertex_tint on: COLOR is its painted shading.
//
// The flesh carries the ingredient's own grain (FoodLook.Pattern), painted
// in the mesh's own space so it moves with the piece.

uniform vec4 skin_color : source_color = vec4(0.85, 0.74, 0.5, 1.0);
uniform vec4 flesh_color : source_color = vec4(0.96, 0.9, 0.68, 1.0);
uniform vec3 browning_pos = vec3(0.0);
uniform vec3 browning_neg = vec3(0.0);
uniform vec3 char_pos = vec3(0.0);
uniform vec3 char_neg = vec3(0.0);
uniform vec3 skin_pos = vec3(1.0);
uniform vec3 skin_neg = vec3(1.0);
uniform vec3 wet_pos = vec3(1.0);
uniform vec3 wet_neg = vec3(1.0);
uniform float gloss : hint_range(0.0, 1.0) = 0.0;
uniform float translucency : hint_range(0.0, 1.0) = 0.0;
uniform float crumble : hint_range(0.0, 1.0) = 0.0;
// Light given off by glowing essences awake in the food.
uniform vec4 glow_color : source_color = vec4(1.0, 0.9, 0.6, 1.0);
uniform float glow_energy = 0.0;

uniform bool vertex_data = false;
uniform bool vertex_tint = false;
// FoodLook.Pattern: 0 none, 1 speckle, 2 fibre, 3 flake, 4 marble, 5 vein,
// 6 pore, 7 rings.
uniform int pattern = 1;
uniform vec4 pattern_color : source_color = vec4(1.0);
uniform float pattern_strength = 0.15;
uniform float pattern_size = 0.002;
uniform vec3 pattern_offset = vec3(0.0);
uniform float crust_blister = 0.5;
// 0 flat to 1 fully curled; and the size of the cut piece (m), so the curl
// bends about its middle.
uniform float curl = 0.0;
uniform vec3 piece_size = vec3(0.05);

uniform vec4 golden_color : source_color = vec4(0.86, 0.6, 0.22, 1.0);
uniform vec4 brown_color : source_color = vec4(0.45, 0.24, 0.09, 1.0);
uniform vec4 char_color : source_color = vec4(0.07, 0.05, 0.04, 1.0);

varying vec3 world_position;
varying vec3 world_normal;
varying vec3 local_position;
varying vec2 surface_data;
varying vec3 tint;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

// Smooth value noise, 0..1.
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

float per_face(vec3 n, vec3 positive, vec3 negative) {
	vec3 w = n * n;
	vec3 side = mix(negative, positive, step(0.0, n));
	return dot(w, side) / max(w.x + w.y + w.z, 0.0001);
}

// How strongly the flesh's grain shows at a point, 0..1.
float grain(vec3 p) {
	if (pattern == 1) {  // speckle: starch flecks
		return step(0.82, hash(floor(p * 1.5))) * 0.8 + vnoise(p * 0.7) * 0.2;
	} else if (pattern == 2) {  // fibre: streaks running along the length
		float wave = vnoise(vec3(p.x * 0.08, p.y, p.z) * 0.6) * 2.0;
		return pow(1.0 - abs(sin((p.y + p.z * 0.6) * 1.6 + wave)), 6.0);
	} else if (pattern == 3) {  // flake: chevrons of fish muscle
		float band = fract(p.x * 0.18 + abs(p.z - pattern_offset.z * 8.0) * 0.1);
		return smoothstep(0.08, 0.0, band) + smoothstep(0.92, 1.0, band);
	} else if (pattern == 4) {  // marble: threads of fat
		return pow(1.0 - abs(vnoise(p * 0.35) * 2.0 - 1.0), 10.0);
	} else if (pattern == 5) {  // vein: veins off a midrib
		float side = pow(1.0 - abs(sin((p.x - abs(p.z) * 0.8) * 0.9)), 18.0);
		return max(side, smoothstep(0.6, 0.0, abs(p.z)));
	} else if (pattern == 6) {  // pore
		return smoothstep(0.62, 0.8, vnoise(p * 1.4));
	} else if (pattern == 7) {  // rings
		return pow(1.0 - abs(sin(length(p.yz) * 1.4 + vnoise(p * 0.3) * 2.0)), 8.0);
	}
	return 0.0;
}

void vertex() {
	local_position = VERTEX;
	surface_data = vertex_data ? UV2 : vec2(0.0);
	tint = vertex_tint ? COLOR.rgb : vec3(1.0);
	vec3 n_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float browning_here = per_face(n_world, browning_pos, browning_neg);
	// A crisping crust bubbles up off the surface.
	float bubble = vnoise(VERTEX * 1400.0 + pattern_offset * 10.0);
	VERTEX += NORMAL * smoothstep(0.55, 0.85, bubble) * smoothstep(0.2, 0.6, browning_here) * crust_blister * 0.0005;
	// Crumbled food loses its clean edges.
	VERTEX += NORMAL * (hash(floor(VERTEX * 500.0)) - 0.5) * crumble * 0.0015;
	// Cooked protein tightens and the piece curls up at its ends.
	if (vertex_data && curl > 0.0) {
		float along = VERTEX.x / max(piece_size.x, 0.0001) * 2.0 - 1.0;
		VERTEX.y += curl * along * along * min(piece_size.x * 0.12, piece_size.y * 1.2);
	}
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = n_world;
}

void fragment() {
	vec3 n = normalize(world_normal);
	float browning = per_face(n, browning_pos, browning_neg);
	float char_amount = per_face(n, char_pos, char_neg);
	float skin = vertex_data ? surface_data.x : per_face(n, skin_pos, skin_neg);
	float edge = surface_data.y;
	float wet = per_face(n, wet_pos, wet_neg);

	vec3 base = mix(flesh_color.rgb, skin_color.rgb, skin) * tint;
	// The flesh's own grain, fading out under skin.
	float g = grain(local_position / max(pattern_size, 0.00001) + pattern_offset * 37.0);
	base = mix(base, pattern_color.rgb * tint, clamp(g * pattern_strength * (1.0 - skin * 0.8), 0.0, 1.0));
	// Skin carries a fine mottle of its own.
	base *= 1.0 - skin * 0.08 * vnoise(local_position * 900.0 + pattern_offset * 5.0);
	// Cooked starch and flesh go glassy and slightly warmer.
	base = mix(base, base * vec3(1.0, 0.93, 0.78), translucency * 0.45);

	// Edges and corners brown ahead of the faces between them, and a crisping
	// crust's tiny bubbles brown a shade ahead of the surface around them.
	float blister = vnoise(local_position * 1400.0 + pattern_offset * 10.0);
	float browned = browning * (1.0 + edge * 0.45);
	browned += (blister - 0.5) * 0.3 * smoothstep(0.1, 0.5, browning) * (0.5 + crust_blister);
	browned = clamp(browned, 0.0, 1.0);
	vec3 cooked = browned < 0.5
		? mix(base, golden_color.rgb, browned * 2.0)
		: mix(golden_color.rgb, brown_color.rgb, (browned - 0.5) * 2.0);

	// Char comes in patches that spread from the edges, then cracks.
	float patches = vnoise(world_position * 220.0) * 0.7 + hash(floor(world_position * 600.0)) * 0.3;
	float charred = smoothstep(1.0 - char_amount * (1.0 + edge * 0.6), 1.0 - char_amount + 0.15, patches) * step(0.001, char_amount);
	float cracks = pow(1.0 - abs(vnoise(world_position * 450.0) * 2.0 - 1.0), 14.0) * smoothstep(0.3, 0.8, char_amount);
	vec3 burnt = mix(char_color.rgb, char_color.rgb * 0.35, cracks);
	ALBEDO = mix(cooked, burnt, clamp(max(charred, char_amount * 0.35), 0.0, 1.0));

	EMISSION = glow_color.rgb * glow_energy * (0.8 + 0.2 * sin(TIME * 2.0 + world_position.x * 40.0));
	float shine = clamp(gloss + wet * 0.25, 0.0, 1.0);
	ROUGHNESS = mix(0.95, 0.18, shine);
	SPECULAR = mix(0.1, 0.75, shine);
	// A soft cel rim so pale food keeps its shape against a pale board.
	RIM = 0.35;
	RIM_TINT = 0.6;
	BACKLIGHT = vec3(translucency * 0.25) * base;
}
