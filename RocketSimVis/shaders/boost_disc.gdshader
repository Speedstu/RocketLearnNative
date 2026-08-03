shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	float radius = length(local_position.xz) / 0.34;
	float core = 1.0 - smoothstep(0.22, 0.95, radius);
	float ring = smoothstep(0.42, 0.62, radius) * (1.0 - smoothstep(0.80, 1.0, radius));
	float pulse = 0.90 + sin(TIME * 3.4) * 0.10;
	ALBEDO = vec3(1.0, 0.52, 0.025);
	EMISSION = vec3(1.0, 0.44, 0.025) * (core * 1.05 + ring * 0.62) * pulse;
	ALPHA = clamp(core * 0.65 + ring * 0.52, 0.0, 0.78);
}
