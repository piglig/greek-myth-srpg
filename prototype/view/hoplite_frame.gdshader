shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform sampler2D atlas : source_color, filter_linear, repeat_disable;
instance uniform vec4 frame_rect;
instance uniform vec2 frame_origin;
instance uniform vec4 reveal_region;
varying float ground;
void vertex() {
	ground=MODEL_MATRIX[3].y;
	vec2 pixel=frame_origin+UV*frame_rect.zw;
	vec2 offset=(pixel-vec2(160.))*vec2(.015,-.015);
	offset.y+=1.18*cos(radians(38.));
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
	VERTEX=vec3(offset,0.);
}
void fragment() {
	vec2 texel=frame_rect.xy+clamp(UV*frame_rect.zw,vec2(.5),frame_rect.zw-.5);
	vec4 ink=texture(atlas,texel/vec2(textureSize(atlas,0)));
	if(ink.a<.12) discard;
	if(reveal_region.z>0.) {
		vec2 d=(SCREEN_UV-reveal_region.xy)/reveal_region.zw;
		if(dot(d,d)<1. && mod(floor(FRAGCOORD.x)+floor(FRAGCOORD.y),2.)<1.) discard;
	}
	vec3 point=VERTEX;
	float below=ground-(INV_VIEW_MATRIX*vec4(point,1.)).y;
	point.z+=max(0.,below)/max(.1,INV_VIEW_MATRIX[2].y);
	vec4 clip=PROJECTION_MATRIX*vec4(point,1.);
	DEPTH=clip.z/clip.w;
	ALBEDO=ink.rgb;
	ALPHA=ink.a;
}
