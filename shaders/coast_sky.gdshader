shader_type sky;

// A painted coastal sky: a warm haze at the horizon rising to clear blue,
// a soft sun glow, and slow cel-shaded cumulus drifting on the sea wind.
// The horizon colour matches the environment fog so the sea melts into it.

uniform vec3 zenith_color : source_color = vec3(0.28, 0.50, 0.78);
uniform vec3 upper_color : source_color = vec3(0.52, 0.70, 0.88);
uniform vec3 horizon_color : source_color = vec3(0.93, 0.86, 0.76);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.7);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.97, 0.92);
uniform vec3 cloud_shade : source_color = vec3(0.64, 0.70, 0.82);
uniform float cloud_coverage : hint_range(0.0, 1.0) = 0.56;
uniform float cloud_edge : hint_range(0.0, 0.2) = 0.07;
uniform float cloud_scale = 0.55;
uniform vec2 cloud_drift = vec2(0.006, 0.002);
uniform float sun_disc = 0.9994;

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float total = 0.0;
	float amplitude = 0.5;
	// Each octave is turned, so no grid shows through as blocky clouds.
	mat2 turn = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int octave = 0; octave < 5; octave++) {
		total += value_noise(p) * amplitude;
		p = turn * p * 2.03 + vec2(1.7, 9.2);
		amplitude *= 0.5;
	}
	return total;
}

void sky() {
	vec3 dir = EYEDIR;
	float height = dir.y;
	vec3 color = mix(horizon_color, upper_color, smoothstep(0.0, 0.22, height));
	color = mix(color, zenith_color, smoothstep(0.18, 0.85, height));
	if (height < 0.0) {
		color = horizon_color;
	}

	float toward_sun = max(dot(dir, LIGHT0_DIRECTION), 0.0);
	color += sun_color * (pow(toward_sun, 6.0) * 0.18 + pow(toward_sun, 64.0) * 0.45);

	if (height > 0.0) {
		vec2 layer = dir.xz / (height + 0.1) * cloud_scale + TIME * cloud_drift;
		float density = fbm(layer);
		float cover = smoothstep(cloud_coverage, cloud_coverage + cloud_edge, density);
		cover *= smoothstep(0.0, 0.12, height);
		// Clouds are lit where they thin out towards the sun: two tones, as if painted.
		float sunward = fbm(layer + LIGHT0_DIRECTION.xz * 0.08);
		float lit = smoothstep(-0.015, 0.015, density - sunward);
		vec3 cloud = mix(cloud_shade, cloud_lit, lit);
		cloud += sun_color * pow(toward_sun, 10.0) * 0.35;
		cloud = mix(cloud, horizon_color, 1.0 - smoothstep(0.0, 0.3, height));
		color = mix(color, cloud, cover);
	}

	if (dot(dir, LIGHT0_DIRECTION) > sun_disc) {
		color = sun_color * 4.0;
	}
	COLOR = color;
}
