shader_type spatial;
render_mode unshaded, depth_test_disabled, depth_draw_never, cull_disabled, fog_disabled;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform bool enabled = true;
void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}
void fragment() {
	vec3 value = texture(screen_tex,SCREEN_UV).rgb;
	ALBEDO = enabled ? pow(round(pow(max(value,vec3(0.0)),vec3(0.5))*32.0)/32.0,vec3(2.0)) : value;
}
