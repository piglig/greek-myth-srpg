shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
void fragment() {
	float r = length((UV - vec2(0.5)) * 2.0);
	ALBEDO = vec3(0.07, 0.044, 0.03);
	ALPHA = 0.34 * (1.0 - smoothstep(0.15,1.0,r));
}
