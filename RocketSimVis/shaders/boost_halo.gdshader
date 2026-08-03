shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

void fragment() {
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float pulse = 0.88 + sin(TIME * 2.8) * 0.12;
	ALBEDO = vec3(1.0, 0.42, 0.02);
	EMISSION = vec3(1.0, 0.40, 0.025) * 1.15;
	ALPHA = (0.035 + rim * 0.17) * pulse;
}
