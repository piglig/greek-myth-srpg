shader_type canvas_item;
render_mode unshaded;
void fragment() {
	vec2 p = UV;
	vec3 land = texture(TEXTURE, UV).rgb;
	float shade = smoothstep(.66, .99, p.y) * .92;
	shade = max(shade, .76 * (1.0-smoothstep(.04,.35,p.y)) * (1.0-smoothstep(.05,.54,p.x)));
	shade = max(shade, .73 * (1.0-smoothstep(.02,.22,p.y)) * smoothstep(.58,.94,p.x));
	float breeze = sin(p.x*15.0+p.y*4.0+TIME*.22)*.012;
	COLOR = vec4(mix(land*(1.0+breeze),vec3(.048,.064,.060),shade),1.0);
}
