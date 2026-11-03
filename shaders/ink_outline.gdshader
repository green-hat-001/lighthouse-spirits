shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

// Ink lines, drawn over the whole view by a quad that sits on the camera:
// wherever the depth jumps - the silhouette of a fry against the board, a
// fillet's edge, the lip of the pot - the nearer surface gets a warm line,
// as if drawn round with a brush; where the surface folds sharply (a cut
// edge, the rim of a crock) a lighter line marks the crease. Lines fade
// with distance, so the near work reads crisply and the sea stays a
// painting. Creases need the normal buffer, which only Forward+ has; the
// silhouettes work everywhere.

uniform sampler2D depth_texture : hint_depth_texture, filter_nearest;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D normal_texture : hint_normal_roughness_texture, filter_nearest;
#endif
uniform vec4 ink_color : source_color = vec4(0.16, 0.1, 0.07, 1.0);
uniform float strength : hint_range(0.0, 1.0) = 0.8;
uniform float crease_strength : hint_range(0.0, 1.0) = 0.45;
// How big a jump in depth, as a share of the depth, draws a line.
uniform float threshold = 0.012;
// How sharply the surface must turn (1 - cosine) to draw a crease.
uniform float crease_threshold = 0.35;
// Lines are full strength out to fade_from metres and gone by fade_to.
uniform float fade_from = 1.2;
uniform float fade_to = 8.0;
uniform float width_px = 1.4;

void vertex() {
	// Cover the screen whatever the camera does.
	POSITION = vec4(VERTEX.xy * 2.0, 0.0, 1.0);
}

float linear_depth(vec2 uv, mat4 inv_projection) {
	float raw = texture(depth_texture, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, raw) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw);
#endif
	vec4 view = inv_projection * vec4(ndc, 1.0);
	return -view.z / view.w;
}

#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
vec3 view_normal(vec2 uv) {
	return normalize(texture(normal_texture, uv).xyz * 2.0 - 1.0);
}
#endif

void fragment() {
	vec2 texel = width_px / VIEWPORT_SIZE;
	vec2 offsets[4] = vec2[](vec2(texel.x, 0.0), vec2(-texel.x, 0.0), vec2(0.0, texel.y), vec2(0.0, -texel.y));
	float centre = linear_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float jump = 0.0;
	for (int i = 0; i < 4; i++) {
		jump = max(jump, linear_depth(SCREEN_UV + offsets[i], INV_PROJECTION_MATRIX) - centre);
	}
	float line = smoothstep(threshold, threshold * 3.0, jump / max(centre, 0.001)) * strength;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
	vec3 n = view_normal(SCREEN_UV);
	float turn = 0.0;
	for (int i = 0; i < 4; i++) {
		turn = max(turn, 1.0 - dot(n, view_normal(SCREEN_UV + offsets[i])));
	}
	line = max(line, smoothstep(crease_threshold, crease_threshold * 1.8, turn) * crease_strength);
#endif
	float near = 1.0 - smoothstep(fade_from, fade_to, centre);
	ALBEDO = ink_color.rgb;
	ALPHA = line * near;
}
