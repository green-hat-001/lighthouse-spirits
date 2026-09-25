shader_type spatial;
render_mode cull_disabled, diffuse_toon, specular_disabled;

// Grass on the cliff top, swaying in gusts off the sea. The kit stores how
// far up its blade each vertex is in COLOR.a (0 root, 1 tip), so only the
// tips move. Blades are lit as if they were the ground they grow from, which
// keeps a field of them soft and painterly instead of glittering.

uniform vec3 root_color : source_color = vec3(0.3, 0.5, 0.24);
uniform vec3 tip_color : source_color = vec3(0.74, 0.8, 0.46);
// Direction the wind blows towards, in world X/Z: in from the sea.
uniform vec2 wind_toward = vec2(0.35, 1.0);
uniform float wind_sway_m = 0.07;

varying float along_blade;

void vertex() {
	along_blade = COLOR.a;
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float gust = sin(TIME * 1.6 + dot(world.xz, vec2(0.35, 0.22))) * 0.5 + 0.5;
	gust *= 0.55 + 0.45 * sin(TIME * 0.4 + world.x * 0.06 + world.z * 0.04);
	vec2 sway = normalize(wind_toward) * wind_sway_m * gust * along_blade * along_blade;
	VERTEX.xz += sway;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	ALBEDO = mix(root_color, tip_color, along_blade);
	ROUGHNESS = 1.0;
}
