// Keep pigment cells attached to their surface. Soften their boundaries only
// across the projected pixel footprint when the camera turns or zooms out.
vec2 pigment_cell(vec2 uv, float density) {
	vec2 grid = uv*density;
	vec2 width = clamp(fwidth(grid),vec2(.045),vec2(1.));
	vec2 edge = fract(grid)-.5;
	return (floor(grid)+.5+sign(edge)*.5*smoothstep(.5-width*.5,vec2(.5),abs(edge)))/density;
}

vec3 pigment_bands(vec3 color, float levels) {
	float value = sqrt(max(.001,dot(color,vec3(.2126,.7152,.0722))));
	float band = floor(value*levels+.5)/levels;
	return color*mix(1.,band*band/(value*value),.68);
}
