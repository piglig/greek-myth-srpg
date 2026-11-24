shader_type spatial;
render_mode specular_disabled;
// Tents, bedrolls and logs from the Kenney Survival Kit (CC0). Its palette is a modern
// camper's orange and yellow; here only its light and dark are kept, and painted as
// undyed linen and weathered wood so the pieces sit in a Greek hillside camp.
uniform sampler2D albedo_map : source_color, filter_nearest;
uniform vec3 linen : source_color = vec3(.80,.74,.61);
uniform vec3 wood : source_color = vec3(.37,.26,.18);
void fragment() {
	vec3 paint = texture(albedo_map,UV).rgb;
	float light = dot(paint,vec3(.30,.59,.11));
	ALBEDO = mix(wood,linen,smoothstep(.46,.58,light));
	ROUGHNESS = 1.0;
}
