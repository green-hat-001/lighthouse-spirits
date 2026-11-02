shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// A ring of gas flame tongues around the burner head. The mesh only
// supplies topology: UV.x is each tongue's place around the ring (0-1),
// UV.y how far up the tongue (0 base, 1 tip), UV2.x the side across it
// (-1 to 1). Everything else comes from the burner's state, so the flame
// the player sees is the flame the simulation burns: wider and taller
// with more gas, leaning with the wind.

uniform float level : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius = 0.035;
uniform float outer_radius = 0.06;
uniform float tongue_height = 0.02;
uniform float tongue_width = 0.006;
uniform vec2 wind = vec2(0.0);
uniform vec4 core_color : source_color = vec4(0.25, 0.45, 1.0, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.35, 0.9, 1.0);
uniform vec4 lick_color : source_color = vec4(1.0, 0.55, 0.2, 1.0);

varying float v_height;
varying float v_side;
varying float v_flicker;

float hash(float n) {
	return fract(sin(n * 91.345) * 47453.5453);
}

float noise(float x) {
	float i = floor(x);
	float f = fract(x);
	return mix(hash(i), hash(i + 1.0), smoothstep(0.0, 1.0, f));
}

void vertex() {
	float angle = UV.x * TAU;
	float up = UV.y;
	float side = UV2.x;
	float seed = UV.x * 37.0;
	float flicker = 0.75 + 0.5 * noise(TIME * 9.0 + seed * 3.1) - 0.15 * noise(TIME * 23.0 + seed);
	vec3 outward = vec3(cos(angle), 0.0, sin(angle));
	vec3 tangent = vec3(-sin(angle), 0.0, cos(angle));
	float radius = mix(inner_radius, outer_radius, up * up);
	float width = tongue_width * (1.0 - up * 0.85) * (0.6 + 0.4 * level);
	float height = tongue_height * up * flicker;
	vec3 lean = vec3(wind.x, 0.0, wind.y) * up * up * 0.004 * (1.0 + noise(TIME * 4.0 + seed));
	VERTEX = outward * radius + tangent * side * width + vec3(0.0, height, 0.0) + lean;
	v_height = up;
	v_side = side;
	v_flicker = flicker;
}

void fragment() {
	float edge = 1.0 - abs(v_side);
	float body = smoothstep(0.0, 0.5, edge) * (1.0 - smoothstep(0.55, 1.0, v_height));
	vec3 color = mix(core_color.rgb, tip_color.rgb, smoothstep(0.2, 0.8, v_height));
	// A big flame licks yellow at its tips.
	color = mix(color, lick_color.rgb, smoothstep(0.6, 1.0, v_height) * smoothstep(0.6, 1.0, level) * 0.6);
	float intensity = step(0.001, level) * (0.6 + 0.6 * level) * v_flicker;
	ALBEDO = color * intensity * 1.6;
	ALPHA = clamp(body * intensity, 0.0, 1.0);
}
