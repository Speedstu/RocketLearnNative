shader_type spatial;

void fragment() {
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.4);
	float pulse = 0.92 + sin(TIME * 2.8) * 0.08;
	vec3 gold = vec3(0.88, 0.34, 0.015);
	vec3 highlight = vec3(1.0, 0.66, 0.10);
	ALBEDO = mix(gold, highlight, rim * 0.34);
	METALLIC = 0.78;
	ROUGHNESS = 0.22;
	SPECULAR = 0.9;
	EMISSION = highlight * (0.38 + rim * 0.42) * pulse;
}
