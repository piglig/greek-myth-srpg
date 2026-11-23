shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
// A looping pixelfx fire (36 square frames in one row), turned to face the camera.
uniform sampler2D atlas : source_color, filter_nearest;
uniform float frames = 36.0;
uniform float fps = 12.0;
instance uniform float growth = 1.0;
varying float phase;
void vertex() {
	phase = fract(dot(MODEL_MATRIX[3].xz,vec2(2.31,3.97)))*frames;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
	// Bring the card forward so the light pool at its foot is not cut by the ground.
	VERTEX.z += .45;
}
void fragment() {
	float frame = mod(floor(TIME*fps+phase),frames);
	vec2 uv = UV;
	// A fire that is catching grows up from its base.
	uv.y = 1.0-(1.0-uv.y)/mix(0.25,1.0,growth);
	vec4 ink = texture(atlas,vec2((frame+clamp(uv.x,0.002,0.998))/frames,clamp(uv.y,0.002,0.998)));
	ALBEDO = ink.rgb;
	ALPHA = ink.a*growth*step(0.0,uv.y);
}
