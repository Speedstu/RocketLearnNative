shader_type spatial;
render_mode cull_disabled;

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D detail_normal : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform float detail_scale = 2.0;
uniform float detail_strength = 0.08;

varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 weights = pow(abs(world_normal), vec3(6.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	vec3 detail_x = texture(detail_normal, world_position.yz * detail_scale).rgb * 2.0 - 1.0;
	vec3 detail_y = texture(detail_normal, world_position.xz * detail_scale).rgb * 2.0 - 1.0;
	vec3 detail_z = texture(detail_normal, world_position.xy * detail_scale).rgb * 2.0 - 1.0;
	vec3 detail = detail_x * weights.x + detail_y * weights.y + detail_z * weights.z;
	vec3 perturbation = detail - world_normal * dot(detail, world_normal);
	float grain = (detail.x + detail.y) * 0.5;
	ALBEDO = base_color.rgb * (1.0 + grain * 0.025);
	NORMAL = normalize(NORMAL + mat3(VIEW_MATRIX) * perturbation * detail_strength);
	METALLIC = 0.0;
	ROUGHNESS = clamp(0.70 - grain * 0.08, 0.58, 0.82);
	SPECULAR = 0.25;
}
