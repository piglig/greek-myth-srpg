shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec3 land = texture(TEXTURE, UV).rgb;
	float shadow = (1.0 - smoothstep(.16,.64,UV.x)) * .82;
	float firelight = exp(-length((UV-vec2(.31,.78))*vec2(1.7,1.0))*13.0);
	land += vec3(.12,.055,.01)*firelight*(1.0+sin(TIME*4.5)*.35);
	COLOR = vec4(mix(land,vec3(.069,.055,.05),shadow),1.0);
}
