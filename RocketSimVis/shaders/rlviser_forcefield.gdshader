shader_type spatial;
render_mode blend_mix, cull_disabled, depth_prepass_alpha, unshaded, shadows_disabled;

uniform sampler2D hex_texture : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 tint_color : source_color = vec4(0.62, 0.72, 0.84, 0.3);

void fragment() {
	float hex = texture(hex_texture, UV).r;
	ALBEDO = tint_color.rgb;
	EMISSION = tint_color.rgb * hex * 0.22;
	ALPHA = 0.025 + smoothstep(0.08, 0.85, hex) * 0.42;
}

