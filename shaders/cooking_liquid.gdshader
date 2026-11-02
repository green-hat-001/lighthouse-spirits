shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled, depth_draw_always;

// The surface of whatever is in the pot. Everything here is driven from
// the simulation so the cook can read the liquid by eye: oil shimmers more
// the hotter it gets (convection cells catching the light), darkens as it
// breaks down, and water trembles, then rolls, as it comes to the boil.

uniform vec4 liquid_color : source_color = vec4(0.95, 0.78, 0.3, 1.0);
uniform float clarity : hint_range(0.0, 1.0) = 0.55;
// 0 still to 1 the fine, restless shimmer of oil near frying heat.
uniform float shimmer : hint_range(0.0, 1.0) = 0.0;
// 0 still to 1 a rolling boil or a vigorous fry.
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
uniform float gloss : hint_range(0.0, 1.0) = 0.8;

varying vec3 world_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float field(vec2 p) {
	float slow = noise(p * 60.0 + vec2(TIME * 0.6, -TIME * 0.4));
	float cells = noise(p * 140.0 + vec2(-TIME * 1.7, TIME * 1.3)) * shimmer;
	float boil = noise(p * 90.0 + vec2(TIME * 4.0, TIME * 3.1)) * agitation;
	return slow * 0.15 + cells * 0.6 + boil * 0.9;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float e = 0.0015;
	float h = field(p);
	vec2 slope = vec2(field(p + vec2(e, 0.0)) - h, field(p + vec2(0.0, e)) - h) / e;
	vec3 tilted = normalize(vec3(-slope.x * 0.004, 1.0, -slope.y * 0.004));
	NORMAL = normalize((VIEW_MATRIX * vec4(tilted, 0.0)).xyz);
	ALBEDO = liquid_color.rgb * (0.85 + 0.15 * h);
	ROUGHNESS = mix(0.6, 0.05, gloss);
	SPECULAR = mix(0.3, 0.9, gloss);
	ALPHA = clamp(1.0 - clarity + agitation * 0.15, 0.2, 1.0);
}
