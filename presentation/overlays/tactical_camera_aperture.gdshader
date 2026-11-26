shader_type spatial;

uniform vec4 surface_color : source_color = vec4(1.0);
uniform sampler2D surface_texture : source_color, hint_default_white, filter_linear_mipmap;
uniform vec2 surface_uv_scale = vec2(1.0);
uniform vec2 surface_uv_offset = vec2(0.0);
uniform bool surface_vertex_color = false;
uniform float surface_roughness = 0.88;
uniform float surface_metallic = 0.0;
uniform float surface_specular = 0.5;
instance uniform float opening = 0.0;
instance uniform float aperture_radius;
instance uniform float cut_floor = -100000.0;
instance uniform vec3 aperture_eye;
instance uniform vec3 aperture_subject;

varying vec3 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = surface_color.rgb * texture(surface_texture, UV * surface_uv_scale + surface_uv_offset).rgb;
	if (surface_vertex_color) {
		ALBEDO *= COLOR.rgb;
	}
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	SPECULAR = surface_specular;
	if (opening > 0.0 && !IN_SHADOW_PASS) {
		vec3 aim = aperture_subject - aperture_eye;
		float range = length(aim);
		vec3 direction = aim / max(range, 0.001);
		vec3 offset = world_position - aperture_eye;
		float depth = dot(offset, direction);
		// Keep every surface at or beyond the subject intact. Taper toward
		// the camera so the opening follows the silhouette at any zoom.
		if (depth > 0.0 && depth < range) {
			float radius = aperture_radius * depth / range * sqrt(opening);
			float radial = length(offset - direction * depth);
			// Keep a solid band at the actor's floor so the prop still
			// reads as cover and its ground marker has a visible anchor.
			float above_base = smoothstep(cut_floor, cut_floor + 0.10, world_position.y);
			float cut = (1.0 - smoothstep(radius * 0.90, radius, radial)) * above_base;
			// Stable grain softens the edge without a transparent draw pass.
			vec3 grain = floor(world_position * 140.0);
			float threshold = fract(sin(dot(grain, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
			if (cut > threshold) {
				discard;
			}
		}
	}
}
