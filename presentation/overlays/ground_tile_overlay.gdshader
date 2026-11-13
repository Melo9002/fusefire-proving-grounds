shader_type spatial;
render_mode unshaded, cull_front, depth_test_disabled, depth_draw_never, fog_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint : source_color;
uniform vec3 tile_half_size;
varying flat vec3 tile_center;

void vertex() {
	tile_center = vec3(UV.x, UV2.x, UV.y);
}

void fragment() {
	float depth = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = depth * 2.0 - 1.0;
#endif
	vec4 position = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vec3 surface = position.xyz / position.w;
	vec3 normal = cross(dFdx(surface), dFdy(surface));
	// Project onto terrain and slopes within this floor's band. Vertical faces
	// and objects standing above the band should not acquire a ground tint.
	if (depth <= 0.0 || any(greaterThanEqual(abs(surface - tile_center), tile_half_size))
		|| abs(normal.y) <= length(normal) * 0.45) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = tint.a;
}
