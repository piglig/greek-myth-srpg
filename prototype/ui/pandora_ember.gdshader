shader_type canvas_item;
render_mode unshaded;

uniform vec2 look_offset;

// Each drifting cell carries a soft mote at a stable, irregular position.
float dust(vec2 pos, float density, vec2 breeze) {
	vec2 field = (pos - TIME * breeze) * density;
	vec2 cell = floor(field);
	float seed = fract(sin(dot(cell, vec2(17.13, 93.77))) * 4137.53);
	vec2 center = vec2(seed, fract(seed * 43.19)) * 0.66 + 0.17;
	center.y += 0.07 * sin(TIME * 0.65 + seed * 21.0);
	float distance_to_mote = length(fract(field) - center);
	return exp(-distance_to_mote * distance_to_mote * 940.0) * smoothstep(0.45, 0.88, seed);
}

// All distances are in cover-image heights, so the fire stays on the painted coal
// when TextureRect crops the composition for a different window shape.
void fragment() {
	vec2 aspect = vec2(TEXTURE_PIXEL_SIZE.y / TEXTURE_PIXEL_SIZE.x, 1.0);
	vec2 camera = vec2(sin(TIME * 0.37), sin(TIME * 0.29)) * vec2(0.0038, 0.0024) + look_offset;
	vec2 uv = (UV - 0.5) * 0.973 + 0.5;
	float interior = length((uv - vec2(0.682, 0.615)) / vec2(0.242, 0.304));
	float near_clay = smoothstep(0.72, 1.09, interior) * smoothstep(0.31, 0.55, uv.x);
	uv += camera * (0.30 + 0.70 * near_clay);
	vec2 p = (uv - vec2(0.681, 0.764)) * aspect;
	float height = -p.y;
	float pulse = 0.54 + 0.25 * sin(TIME * 2.6) + 0.14 * sin(TIME * 5.7 + 1.7) + 0.07 * sin(TIME * 10.1);
	float column = (1.0 - smoothstep(0.012, 0.083, abs(p.x))) * smoothstep(0.0, 0.04, height) * (1.0 - smoothstep(0.09, 0.23, height));
	uv.x += sin(height * 90.0 - TIME * 3.8) * column * 0.0014;
	vec3 clay = texture(TEXTURE, uv).rgb;
	float bounce = exp(-length(p * vec2(0.79, 1.10)) * 8.5);
	clay *= 1.0 + vec3(0.96, 0.54, 0.19) * (pulse - 0.30) * bounce;
	float fire_height = 0.016 + pulse * 0.016;
	float tip = clamp(height / fire_height, 0.0, 1.0);
	float axis = p.x - sin(TIME * 5.0 + tip * 3.5) * tip * 0.004;
	float flame = (1.0 - smoothstep(0.001, 0.007, abs(axis) + tip * 0.004))
			* smoothstep(-0.003, 0.001, height) * (1.0 - smoothstep(0.55, 1.0, tip));
	clay += vec3(1.0, 0.60, 0.17) * (flame + exp(-length(p) * 73.0) * pulse * 0.66);
	if (height > 0.0 && height < 0.27 && abs(p.x) < 0.11) {
		// A thin strand of smoke drifts sideways as it rises.
		float drift = sin(height * 22.0 - TIME * 0.9) * height * 0.15;
		float ridge = (p.x - drift + height * 0.12) / (0.0025 + height * 0.075);
		float smoke = exp(-ridge * ridge) * column * (0.55 + 0.45 * sin(height * 44.0 - TIME * 1.5));
		clay += vec3(0.21, 0.16, 0.12) * smoke;
		for (int i = 0; i < 12; i++) {
			float seed = fract(float(i) * 0.618034);
			float age = fract(TIME * (0.20 + 0.09 * seed) + float(i) * 0.383);
			float travel = age * (0.12 + 0.14 * seed);
			float x = (seed - 0.5) * travel * 0.66 + sin(age * 7.0 + seed * 28.0) * (0.002 + age * 0.012);
			vec2 d = (p - vec2(x, -travel)) * vec2(1.0, 0.72);
			float spark = exp(-dot(d,d) / (0.0000021 + seed * 0.0000016));
			clay += vec3(1.0, 0.58, 0.19) * spark * smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(0.65, 1.0, age));
		}
	}
	// A shifting band of daylight reveals the painted frieze and airborne dust.
	float shaft = uv.x + uv.y * 0.30 - 0.80 - 0.055 * sin(TIME * 0.43);
	float daylight = exp(-shaft * shaft * 70.0);
	float high_wall = 1.0 - smoothstep(0.29, 0.52, uv.y);
	clay *= 1.0 + daylight * high_wall * 0.16;
	vec2 room = UV * aspect + camera * 1.6;
	float motes = dust(room, 10.0, vec2(0.023, 0.007)) +
			0.62 * dust(room, 17.0, vec2(0.014, 0.003));
	float lit_air = smoothstep(0.32, 0.48, UV.x) * (0.36 + 0.64 * daylight);
	clay += vec3(0.45, 0.37, 0.28) * motes * lit_air;
	COLOR = vec4(clay, 1.0);
}
