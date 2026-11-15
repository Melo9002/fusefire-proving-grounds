shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 boundary_color : source_color = vec4(0.93, 0.76, 0.32, 1.0);
uniform float dash_count = 25.0;

void fragment() {
	if (fract(UV.x * dash_count) > 0.625) {
		discard;
	}
	ALBEDO = boundary_color.rgb;
}
