shader_type canvas_item;
render_mode unshaded;
uniform sampler2D work_pose : source_color, filter_linear;
uniform sampler2D registration : filter_linear, repeat_disable;
varying vec2 rest_uv;
varying float blend;

void vertex() {
	rest_uv=VERTEX/vec2(1366.,768.);
	float rate=rest_uv.x<.30 ? 1.35 : (rest_uv.x<.69 ? .91 : 1.62);
	float offset=rest_uv.x<.30 ? .4 : (rest_uv.x<.69 ? 2.3 : 4.7);
	float cycle=.5-.5*cos(TIME*rate+offset);
	float key=smoothstep(.10,.92,cycle);
	blend=key*COLOR.r;
	VERTEX=mix(VERTEX,UV*vec2(1366.,768.),key);
}

void fragment() {
	vec2 uv=rest_uv;
	vec2 fire=vec2(.311,.442);
	float flame=1.-smoothstep(.003,.032,length((uv-fire)*vec2(1.7,.8)));
	uv.x+=.0012*flame*sin(uv.y*170.+TIME*4.);
	// Residual optical flow registers the fine features between the joint landmarks.
	vec4 shift=(texture(registration,(rest_uv+UV)*.5)*255.-128.)*(22./127.);
	vec2 ref_size=vec2(1024.,576.);
	vec3 rest=texture(TEXTURE,uv-blend*shift.xy/ref_size).rgb;
	vec3 work=texture(work_pose,UV-(1.-blend)*shift.zw/ref_size).rgb;
	vec3 land=mix(rest,work,blend);
	float pulse=.55*sin(TIME*3.3)+.25*sin(TIME*7.2);
	land+=vec3(.12,.057,.018)*pulse*exp(-length((uv-fire)*vec2(1.7,1.))*14.);
	land+=vec3(.10,.047,.012)*sin(TIME*2.4)*exp(-length((uv-vec2(.964,.554))*vec2(1.7,1.))*25.);
	float edge=smoothstep(.80,1.,uv.y)*.48+(1.-smoothstep(.0,.20,uv.y))*(1.-smoothstep(.02,.46,uv.x))*.45;
	COLOR=vec4(land*(1.-edge),1.);
}
