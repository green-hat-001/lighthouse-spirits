shader_type spatial;
render_mode diffuse_toon, specular_toon;

// The sea below the cliff. Long swells roll in from the horizon; colour
// deepens with distance and pales towards the horizon; white foam bands
// wash against anything that breaks the surface - the cliff foot, the rocks.

uniform vec3 near_color : source_color = vec3(0.1, 0.4, 0.47);
uniform vec3 deep_color : source_color = vec3(0.05, 0.22, 0.36);
uniform vec3 horizon_tint : source_color = vec3(0.5, 0.63, 0.72);
uniform vec3 foam_color : source_color = vec3(0.96, 0.98, 0.97);
uniform float swell_height = 0.45;
uniform float foam_reach = 1.6;
uniform sampler2D depth_texture : hint_depth_texture, filter_linear_mipmap;

varying vec3 world_position;

float swell(vec2 p) {
	float t = TIME;
	float h = sin(dot(p, vec2(0.08, 0.05)) + t * 0.6) * 0.5;
	h += sin(dot(p, vec2(-0.05, 0.11)) + t * 0.8) * 0.3;
	h += sin(dot(p, vec2(0.19, -0.07)) + t * 1.3) * 0.15;
	h += sin(dot(p, vec2(0.31, 0.23)) + t * 1.9) * 0.05;
	return h * swell_height;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = swell(world.xz);
	float step_m = 0.6;
	vec3 normal = normalize(vec3(h - swell(world.xz + vec2(step_m, 0.0)), step_m, h - swell(world.xz + vec2(0.0, step_m))));
	VERTEX.y += h;
	NORMAL = normal;
	world_position = world + vec3(0.0, h, 0.0);
}

void fragment() {
	float distance_m = length(world_position - CAMERA_POSITION_WORLD);
	vec3 color = mix(near_color, deep_color, smoothstep(15.0, 160.0, distance_m));
	float grazing = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	color = mix(color, horizon_tint, grazing * 0.45);

	// Foam where the sea meets something standing in it.
	float scene_depth = texture(depth_texture, SCREEN_UV).x;
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	scene_view.xyz /= scene_view.w;
	float water_gap = -scene_view.z - (-VERTEX.z);
	float wash = 1.0 - smoothstep(0.0, foam_reach, water_gap);
	float foam = step(0.55, wash + sin(TIME * 1.4 + water_gap * 5.0) * 0.18);

	ALBEDO = mix(color, foam_color, foam);
	ROUGHNESS = mix(0.12, 0.9, foam);
	SPECULAR = mix(0.7, 0.2, foam);
}
