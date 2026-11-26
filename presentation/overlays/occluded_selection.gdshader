shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 tint : source_color;

void fragment() {
	float nearest = textureLod(scene_depth, SCREEN_UV, 0.0).r;
	if (FRAGCOORD.z >= nearest - 0.00002) {
		discard;
	}
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, nearest);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	ndc.z = nearest * 2.0 - 1.0;
#endif
	vec4 scene_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	// Reject close self-overlap from the character's own arms and equipment.
	float separation = scene_view.z / scene_view.w - VERTEX.z;
	float reveal = smoothstep(0.25, 0.42, separation);
	if (reveal <= 0.0) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = tint.a * reveal;
}
