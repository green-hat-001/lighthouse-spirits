shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Cel-shaded food. Every parameter below is driven from the simulation
// through FoodAppearance, so the player judges doneness by eye: raw flesh
// turns glassy as it cooks, a dry surface goes golden then brown, burnt
// patches blacken, oil makes it shine, and a crust blisters as it crisps.
//
// Browning, char, skin and wetness are per face of the piece's box, as
// (+X, +Y, +Z) and (-X, -Y, -Z). Food is never rotated off the world's
// axes in the kitchen, so the world normal picks the face; on a rounded
// whole-item model the faces blend by how squarely the surface faces each
// way.

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

uniform vec4 golden_color : source_color = vec4(0.86, 0.6, 0.22, 1.0);
uniform vec4 brown_color : source_color = vec4(0.45, 0.24, 0.09, 1.0);
uniform vec4 char_color : source_color = vec4(0.07, 0.05, 0.04, 1.0);

varying vec3 world_position;
varying vec3 world_normal;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

float per_face(vec3 n, vec3 positive, vec3 negative) {
	vec3 w = n * n;
	vec3 side = mix(negative, positive, step(0.0, n));
	return dot(w, side) / max(w.x + w.y + w.z, 0.0001);
}

void vertex() {
	// Crumbled food loses its clean edges.
	VERTEX += NORMAL * (hash(floor(VERTEX * 500.0)) - 0.5) * crumble * 0.0015;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(world_normal);
	float browning = per_face(n, browning_pos, browning_neg);
	float char_amount = per_face(n, char_pos, char_neg);
	float skin = per_face(n, skin_pos, skin_neg);
	float wet = per_face(n, wet_pos, wet_neg);

	vec3 base = mix(flesh_color.rgb, skin_color.rgb, skin);
	// Cooked starch and flesh go glassy and slightly warmer.
	base = mix(base, base * vec3(1.0, 0.93, 0.78), translucency * 0.45);

	// A crisping crust blisters: tiny bubbles brown a shade ahead of the
	// surface around them.
	float blister = hash(floor(world_position * 900.0));
	float browned = clamp(browning + (blister - 0.5) * 0.25 * smoothstep(0.1, 0.5, browning), 0.0, 1.0);
	vec3 cooked = browned < 0.5
		? mix(base, golden_color.rgb, browned * 2.0)
		: mix(golden_color.rgb, brown_color.rgb, (browned - 0.5) * 2.0);

	// Char comes in patches, not an even coat.
	float speckle = hash(floor(world_position * 600.0));
	float charred = smoothstep(1.0 - char_amount, 1.0 - char_amount + 0.2, speckle) * step(0.001, char_amount);
	ALBEDO = mix(cooked, char_color.rgb, max(charred, char_amount * 0.35));

	EMISSION = glow_color.rgb * glow_energy * (0.8 + 0.2 * sin(TIME * 2.0 + world_position.x * 40.0));
	float shine = clamp(gloss + wet * 0.25, 0.0, 1.0);
	ROUGHNESS = mix(0.95, 0.2, shine);
	SPECULAR = mix(0.1, 0.7, shine);
}
