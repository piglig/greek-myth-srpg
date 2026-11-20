shader_type spatial;
// Full-screen pixel-art post process, drawn on a quad attached to the camera inside the
// low-resolution SubViewport: posterize + ordered (Bayer) dither + depth-edge outline.
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform bool enabled = true;
uniform float levels = 8.0;
uniform float dither = 0.55;
uniform float edge_threshold = 0.2;
uniform float edge_darken = 0.5;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inv_proj) {
	float d = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return -v.z / v.w;
}

vec3 to_srgb(vec3 c) {
	return mix(12.92 * c, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), c));
}

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 col = texture(screen_tex, SCREEN_UV).rgb;
	if (enabled) {
		vec2 px = 1.0 / VIEWPORT_SIZE;
		float d = view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
		float farther = 0.0;
		farther = max(farther, view_depth(SCREEN_UV + vec2(px.x, 0.0), INV_PROJECTION_MATRIX) - d);
		farther = max(farther, view_depth(SCREEN_UV - vec2(px.x, 0.0), INV_PROJECTION_MATRIX) - d);
		farther = max(farther, view_depth(SCREEN_UV + vec2(0.0, px.y), INV_PROJECTION_MATRIX) - d);
		farther = max(farther, view_depth(SCREEN_UV - vec2(0.0, px.y), INV_PROJECTION_MATRIX) - d);

		vec3 s = to_srgb(clamp(col, 0.0, 1.0));
		ivec2 p = ivec2(FRAGCOORD.xy) % 4;
		float b = (BAYER[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5;
		s = floor(s * (levels - 1.0) + 0.5 + b * dither) / (levels - 1.0);
		if (farther > edge_threshold) {
			s *= edge_darken;
		}
		col = to_linear(clamp(s, 0.0, 1.0));
	}
	ALBEDO = col;
}
