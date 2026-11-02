shader_type spatial;
render_mode diffuse_toon, specular_toon;

// Liquid seen through a vessel's glass, drawn only up to how full the
// vessel really is.

uniform vec4 liquid_color : source_color = vec4(0.95, 0.8, 0.3, 1.0);
// Height of the liquid's surface in the mesh's own space, in metres.
uniform float fill_height = 0.0;

varying float local_height;

void vertex() {
	local_height = VERTEX.y;
}

void fragment() {
	if (local_height > fill_height) {
		discard;
	}
	ALBEDO = liquid_color.rgb;
	ROUGHNESS = 0.2;
	SPECULAR = 0.7;
}
