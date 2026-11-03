shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled, depth_draw_always;

// The surface of whatever is in the pot. Everything here is driven from
// the simulation so the cook can read the liquid by eye: oil shimmers more
// the hotter it gets (convection cells catching the light), darkens as it
// breaks down, and water trembles, then rolls, as it comes to the boil,
// clouding to a broth as flavour dissolves into it. Food dropped in rings
// the surface, and the spoon sets it swirling.

uniform vec4 liquid_color : source_color = vec4(0.95, 0.78, 0.3, 1.0);
uniform float clarity : hint_range(0.0, 1.0) = 0.55;
// 0 still to 1 the fine, restless shimmer of oil near frying heat.
uniform float shimmer : hint_range(0.0, 1.0) = 0.0;
// 0 still to 1 a rolling boil or a vigorous fry.
uniform float agitation : hint_range(0.0, 1.0) = 0.0;
uniform float gloss : hint_range(0.0, 1.0) = 0.8;
// The pot's centre (world x, z) and inner radius (m), and how far the
// liquid has turned about it.
uniform vec2 centre = vec2(0.0);
uniform float radius = 0.09;
uniform float swirl = 0.0;
// Up to six rings: (x, z) from the pot's centre (m), when they started
// (s, on the `now` clock), and how hard.
uniform vec4 ripples[6];
uniform float now = 0.0;

const float RIPPLE_SPEED = 0.14;
const float RIPPLE_LIFE = 1.6;

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

// The liquid's surface swirls: points turn about the middle, the middle
// more than the walls, which hold it back.
vec2 swirled(vec2 p) {
	vec2 rel = p - centre;
	float r = length(rel) / max(radius, 0.001);
	float turn = swirl * (1.0 - smoothstep(0.0, 1.0, r)) * 0.6;
	float c = cos(turn);
	float s = sin(turn);
	return centre + vec2(c * rel.x - s * rel.y, s * rel.x + c * rel.y);
}

float rings(vec2 p) {
	float height = 0.0;
	for (int i = 0; i < 6; i++) {
		float age = now - ripples[i].z;
		if (age < 0.0 || age > RIPPLE_LIFE) {
			continue;
		}
		float d = distance(p - centre, ripples[i].xy);
		float front = age * RIPPLE_SPEED;
		float envelope = exp(-abs(d - front) * 160.0) * (1.0 - age / RIPPLE_LIFE);
		height += sin((d - front) * 520.0) * envelope * ripples[i].w;
	}
	return height;
}

float field(vec2 p) {
	vec2 q = swirled(p);
	float slow = noise(q * 60.0 + vec2(now * 0.6, -now * 0.4));
	float cells = noise(q * 140.0 + vec2(-now * 1.7, now * 1.3)) * shimmer;
	float boil = noise(q * 90.0 + vec2(now * 4.0, now * 3.1)) * agitation;
	return slow * 0.15 + cells * 0.6 + boil * 0.9 + rings(p) * 0.9;
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_position.xz;
	float e = 0.0012;
	float h = field(p);
	vec2 slope = vec2(field(p + vec2(e, 0.0)) - h, field(p + vec2(0.0, e)) - h) / e;
	vec3 tilted = normalize(vec3(-slope.x * 0.004, 1.0, -slope.y * 0.004));
	NORMAL = normalize((VIEW_MATRIX * vec4(tilted, 0.0)).xyz);
	// Streaks of the swirl show as faint bands in the colour.
	float streak = noise(swirled(p) * vec2(30.0, 220.0));
	ALBEDO = liquid_color.rgb * (0.85 + 0.15 * h) * (0.96 + 0.08 * streak * smoothstep(0.05, 0.6, abs(swirl)));
	// The meniscus darkens where the liquid meets the wall.
	float wall = smoothstep(radius * 0.9, radius, distance(p, centre));
	ALBEDO *= 1.0 - wall * 0.18;
	// Glossy, but a painted gloss: a sharp mirror would show only the sky.
	ROUGHNESS = mix(0.6, 0.32, gloss);
	SPECULAR = mix(0.2, 0.4, gloss);
	ALPHA = clamp(1.0 - clarity + agitation * 0.15 + wall * 0.2, 0.2, 1.0);
}
