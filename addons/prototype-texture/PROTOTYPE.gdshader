shader_type spatial;

uniform sampler2D texture_albedo : source_color, repeat_enable, filter_nearest_mipmap_anisotropic;

// World-space size of one texture repeat.
// 1.0 = texture covers exactly 1 meter.
uniform float texture_size_m = 1.0;

uniform vec4 base_color : source_color = vec4(1.0);

varying vec3 triplanar_position;
varying vec3 triplanar_normal;

void vertex() {
    // Extract object scale from MODEL_MATRIX.
    vec3 object_scale = vec3(
        length(MODEL_MATRIX[0].xyz),
        length(MODEL_MATRIX[1].xyz),
        length(MODEL_MATRIX[2].xyz)
    );

    // Local axes + scale, but NOT object rotation.
    // This keeps the triplanar projection attached to the object.
    triplanar_position = VERTEX * object_scale / texture_size_m;

    // Correct the normal for non-uniform scaling.
    triplanar_normal = normalize(NORMAL / object_scale);
}

void fragment() {
    vec3 weights = abs(triplanar_normal);

    weights *= weights;
    weights *= weights;
    weights /= dot(weights, vec3(1.0));

    vec4 x = texture(texture_albedo, triplanar_position.yz);
    vec4 y = texture(texture_albedo, triplanar_position.xz);
    vec4 z = texture(texture_albedo, triplanar_position.xy);

    vec4 projected =
        x * weights.x +
        y * weights.y +
        z * weights.z;

    ALBEDO = mix(
        base_color.rgb,
        projected.rgb,
        projected.a
    );
}