shader_type spatial;

uniform bool large_pad = false;
uniform bool active = true;

varying vec3 local_position;

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 half_size = large_pad ? vec2(0.0842, 0.0748) : vec2(0.0479, 0.0442);
	vec2 center_offset = large_pad ? vec2(0.0, -0.0148) : vec2(0.0, -0.0042);
	vec2 point = (local_position.xy - center_offset) / half_size;
	float radius = length(point);
	float angle = atan(point.y, point.x);
	float segment_count = large_pad ? 6.0 : 3.0;
	float segment = smoothstep(0.12, 0.72, cos(angle * segment_count));
	float center = 1.0 - smoothstep(0.25, 0.48, radius);
	float ring = smoothstep(0.31, 0.46, radius) * (1.0 - smoothstep(0.55, 0.68, radius));
	float outer = smoothstep(0.55, 0.72, radius) * (1.0 - smoothstep(0.94, 1.12, radius));
	float panel = outer * segment;
	float activity = active ? 1.0 : 0.0;
	vec3 graphite = vec3(0.012, 0.017, 0.026);
	vec3 silver = vec3(0.28, 0.32, 0.38);
	vec3 gold = vec3(1.0, 0.54, 0.035);
	vec3 hot_gold = vec3(1.0, 0.76, 0.16);
	vec3 color = large_pad ? graphite : silver;
	color = mix(color, silver, ring);
	color = mix(color, gold, panel * activity);
	color = mix(color, hot_gold, center * activity);
	float pulse = 0.94 + sin(TIME * 3.2) * 0.06;
	ALBEDO = color;
	METALLIC = mix(0.72, 0.28, max(center, panel) * activity);
	ROUGHNESS = mix(0.22, 0.36, max(center, panel) * activity);
	SPECULAR = 0.75;
	EMISSION = gold * (center * 0.62 + panel * 0.28) * pulse * activity;
}
