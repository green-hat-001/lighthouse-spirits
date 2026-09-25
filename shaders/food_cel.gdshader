shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Cel-shaded food. Every parameter below is driven from the simulation
// through FoodAppearance, so the player judges doneness by eye: raw flesh
// turns glassy as it cooks, a dry surface goes golden then brown, burnt
// patches blacken, and oil makes it shine.

uniform vec4 skin_color : source_color = vec4(0.85, 0.74, 0.5, 1.0);
uniform vec4 flesh_color : source_color = vec4(0.96, 0.9, 0.68, 1.0);
// 0 for a whole item still in its skin, 1 for a piece that is all cut faces.
uniform float cut_share : hint_range(0.0, 1.0) = 0.0;
uniform float browning : hint_range(0.0, 1.0) = 0.0;
uniform float char_amount : hint_range(0.0, 1.0) = 0.0;
uniform float gloss : hint_range(0.0, 1.0) = 0.0;
uniform float translucency : hint_range(0.0, 1.0) = 0.0;
uniform float crumble : hint_range(0.0, 1.0) = 0.0;

uniform vec4 golden_color : source_color = vec4(0.86, 0.6, 0.22, 1.0);
uniform vec4 brown_color : source_color = vec4(0.45, 0.24, 0.09, 1.0);
uniform vec4 char_color : source_color = vec4(0.07, 0.05, 0.04, 1.0);

varying vec3 world_position;

float hash(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}

void vertex() {
	// Crumbled food loses its clean edges.
	VERTEX += NORMAL * (hash(floor(VERTEX * 500.0)) - 0.5) * crumble * 0.0015;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 base = mix(skin_color.rgb, flesh_color.rgb, cut_share);
	// Cooked starch and flesh go glassy and slightly warmer.
	base = mix(base, base * vec3(1.0, 0.93, 0.78), translucency * 0.45);

	vec3 cooked = browning < 0.5
		? mix(base, golden_color.rgb, browning * 2.0)
		: mix(golden_color.rgb, brown_color.rgb, (browning - 0.5) * 2.0);

	// Char comes in patches, not an even coat.
	float speckle = hash(floor(world_position * 600.0));
	float charred = smoothstep(1.0 - char_amount, 1.0 - char_amount + 0.2, speckle) * step(0.001, char_amount);
	ALBEDO = mix(cooked, char_color.rgb, max(charred, char_amount * 0.35));

	ROUGHNESS = mix(0.95, 0.2, gloss);
	SPECULAR = mix(0.1, 0.7, gloss);
}
