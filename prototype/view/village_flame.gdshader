shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;

uniform sampler2D atlas : source_color, filter_linear;
instance uniform float growth = 1.0;
varying float phase;
void vertex(){
	phase = dot(MODEL_MATRIX[3].xz,vec2(2.31,3.97));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment() {
	float cycle = TIME*5.0+phase;
	float frame = mod(floor(cycle),4.0);
	vec2 uv = UV;
	uv.y = 1.0-(1.0-uv.y)/mix(0.18,1.0,growth);
	uv.x += 0.018*sin(uv.y*5.0 + phase + TIME*5.0)*(1.0-uv.y);
	vec4 ink = texture(atlas,vec2((frame+clamp(uv.x,0.002,0.998))*0.25,clamp(uv.y,0.002,0.998)));
	vec4 next_ink = texture(atlas,vec2((mod(frame+1.0,4.0)+clamp(uv.x,0.002,0.998))*.25,clamp(uv.y,.002,.998)));
	float blend = smoothstep(0.0,1.0,fract(cycle));
	float opacity = mix(ink.a,next_ink.a,blend);
	ALBEDO = mix(ink.rgb*ink.a,next_ink.rgb*next_ink.a,blend)/max(.001,opacity);
	ALPHA = opacity*growth*step(0.0,uv.y);
}
