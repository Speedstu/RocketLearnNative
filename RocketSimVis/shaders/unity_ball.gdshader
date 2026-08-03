shader_type spatial;

uniform sampler2D diffuse_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D packed_normal_texture : filter_linear_mipmap_anisotropic;

void fragment() {
	vec4 diffuse = texture(diffuse_texture, UV);
	vec4 packed_normal = texture(packed_normal_texture, UV);
	vec2 normal_xy = vec2(packed_normal.a, packed_normal.g) * 2.0 - 1.0;
	float normal_z = sqrt(max(1.0 - dot(normal_xy, normal_xy), 0.0));
	float cyan_mask = smoothstep(0.06, 0.20, min(diffuse.g - diffuse.r, diffuse.b - diffuse.r * 0.9));
	vec3 cyan = vec3(0.04, 0.62, 1.0);
	ALBEDO = mix(diffuse.rgb, cyan, cyan_mask * 0.78);
	NORMAL_MAP = vec3(normal_xy * 0.5 + 0.5, normal_z);
	NORMAL_MAP_DEPTH = 1.0;
	METALLIC = 0.03;
	ROUGHNESS = 0.7;
	SPECULAR = 0.5;
	EMISSION = cyan * cyan_mask * 1.8;
}
