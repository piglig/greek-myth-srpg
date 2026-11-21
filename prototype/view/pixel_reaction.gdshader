shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D atlas : source_color, filter_nearest, repeat_disable;
uniform vec4 region;
uniform float sidestep=0.;
varying float floor_y;
void vertex(){
	floor_y=MODEL_MATRIX[3].y;
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
}
void fragment(){
	vec2 uv=UV;
	if(abs(sidestep)>.001){
		vec2 atlas_px=vec2(textureSize(atlas,0));
		vec2 cell=mod(UV*atlas_px,vec2(160.,128.));
		float leg=smoothstep(78.,109.,cell.y);
		float lead=smoothstep(-3.,3.,(cell.x-80.)*sign(sidestep));
		uv-=vec2(sidestep*(lead*9.-3.)*leg,-abs(sidestep)*lead*leg*3.)/atlas_px;
	}
	vec4 ink=texture(atlas,uv);
	if(ink.a<.5) discard;
	if(region.z>0.){
		vec2 delta=(SCREEN_UV-region.xy)/region.zw;
		if(dot(delta,delta)<1. && mod(floor(FRAGCOORD.x)+floor(FRAGCOORD.y),2.)<1.) discard;
	}
	vec3 p=VERTEX;
	p.z+=max(0.,floor_y-(INV_VIEW_MATRIX*vec4(p,1.)).y)/max(.1,INV_VIEW_MATRIX[2].y);
	vec4 clip=PROJECTION_MATRIX*vec4(p,1.);
	DEPTH=clip.z/clip.w;
	ALBEDO=ink.rgb;
}
