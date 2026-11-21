shader_type spatial;
render_mode cull_disabled;
uniform sampler2D pigments : source_color, filter_linear, repeat_disable;
instance uniform vec4 reveal_region = vec4(0.0);
void fragment() {
	if (reveal_region.z > 0.) {
		vec2 delta = (SCREEN_UV-reveal_region.xy)/reveal_region.zw;
		if (dot(delta,delta)<1. && mod(floor(FRAGCOORD.x)+floor(FRAGCOORD.y),2.)<1.) { discard; }
	}
	vec3 paint = texture(pigments, UV).rgb;
	vec3 surface = mix(COLOR.rgb,paint,COLOR.a);
	ALBEDO = surface;
	// A small fill preserves painted shadow details when the mesh turns away.
	EMISSION = surface * COLOR.a * .09;
	ROUGHNESS = .85;
	SPECULAR = .23;
}
