shader_type spatial;
render_mode unshaded, shadows_disabled, depth_draw_never;
// Burnt ground under a fire: an uneven charred patch that fades out inside its tile.
varying vec3 world_point;
void vertex() {
	world_point = (MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
}
void fragment() {
	vec2 from_centre = UV-.5;
	float angle = atan(from_centre.y,from_centre.x);
	float ragged = .055*sin(angle*3.+world_point.x*2.3)+.04*sin(angle*7.-world_point.z*3.1);
	float reach = length(from_centre)+ragged;
	vec2 fleck = floor(world_point.xz*40.);
	float ash = fract(sin(dot(fleck,vec2(12.9898,78.233)))*43758.5453);
	ALBEDO = mix(vec3(.085,.06,.05),vec3(.26,.22,.19),step(.82,ash));
	ALPHA = .62*(1.-smoothstep(.20,.47,reach))*(.82+.18*ash);
}
