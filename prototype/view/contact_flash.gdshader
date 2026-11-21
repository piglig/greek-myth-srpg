shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled, depth_draw_never;
uniform int strike;
uniform float progress;

float stroke(vec2 p, vec2 a, vec2 b, float radius) {
	vec2 axis = b-a;
	float t = clamp(dot(p-a,axis)/dot(axis,axis),0.,1.);
	float width = radius*(.24+.76*sin(t*3.14159));
	return 1.-smoothstep(width,width+fwidth(p.y),length(p-a-axis*t));
}
void fragment() {
	vec2 p = vec2(UV.x-.5,.5-UV.y)*2.;
	float t = progress;
	float ink;
	vec3 color;
	if (strike == 0) {
		// A short bronze glint travelling along the projected shaft.
		ink = stroke(p,vec2(-.72+t*.75,0.),vec2(.24+t*.42,0.),.064);
		ink = max(ink,stroke(p,vec2(.15,-.22),vec2(.17,.24),.035)*(1.-t));
		color = vec3(1.,.81,.49);
	} else if (strike == 1) {
		// A broad advancing rim reads even when the target is knocked back.
		float r = length(p);
		ink = (1.-smoothstep(.045,.10,abs(r-mix(.22,.79,t))))*smoothstep(.18,.70,p.x/max(r,.001));
		color = vec3(1.,.64,.30);
	} else if (strike == 3) {
		vec2 point = vec2(.08,0.);
		ink = stroke(p,point,vec2(-.27-.12*t,.16+.12*t),.04)
			+ stroke(p,point,vec2(-.20-.10*t,-.18-.08*t),.032);
		color = vec3(1.,.85,.55);
	} else {
		float gap = .25*(1.-t);
		ink = max(stroke(p,vec2(-.36,.39+gap),vec2(.21,gap),.062),
			stroke(p,vec2(-.38,-.36-gap),vec2(.16,-gap),.053));
		color = vec3(.92,.83,.73);
	}
	ALBEDO = color;
	ALPHA = ink*(1.-smoothstep(.36,1.,t));
}
