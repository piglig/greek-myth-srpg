// One travelling gust for plants, fabric and smoke, independent of camera orientation.
const vec2 WIND_DIR = vec2(0.88, 0.475);
float field_gust(vec2 p, float t) {
	float wave = sin(dot(p,WIND_DIR)*0.81 - t*1.64 + 0.48*sin(p.y*0.58-t*0.38));
	return 0.28 + 0.72*smoothstep(-0.72,0.85,wave);
}

float field_daylight(vec2 p, float t) {
	vec2 q = p - WIND_DIR*t*0.56;
	float cover = sin(q.x*.49+q.y*.23) + 0.58*sin(q.y*.48-q.x*.27);
	return mix(1.0,0.87,smoothstep(0.13,1.25,cover));
}
