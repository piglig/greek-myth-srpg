shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, unshaded, shadows_disabled;
// One level sheet of water. How much of the bed shows through it, and its colour, follow
// how far below it the ground lies, read from a picture of the ground's height.
#include "res://view/pixel_pigment.gdshaderinc"
uniform sampler2D bed : filter_linear, repeat_disable;
uniform vec2 bed_from;
uniform vec2 bed_size;
uniform float level = .04;
uniform vec3 shallows = vec3(.205,.300,.262);
uniform vec3 depths = vec3(.030,.066,.098);
// Looping pictures packed in cells, each with a border of its own far side (bake_water.py).
uniform sampler2D waves : filter_linear, repeat_disable;
uniform sampler2D caustics : filter_linear, repeat_disable;
const float CELL = 264.;
const float BORDER = 4.;
varying vec3 point;
vec3 cell_at(sampler2D atlas, vec2 uv, float frame, vec2 grid) {
	vec2 cell = vec2(mod(frame,grid.x),floor(frame/grid.x));
	vec2 inner = (BORDER+fract(uv)*(CELL-2.*BORDER))/CELL;
	return texture(atlas,(cell+inner)/grid).rgb;
}
// One moment of a loop of `count` frames: the two frames either side of it, blended.
vec3 looped(sampler2D atlas, vec2 uv, float at, float count, vec2 grid) {
	float first = floor(mod(at,count));
	return mix(cell_at(atlas,uv,first,grid),cell_at(atlas,uv,mod(first+1.,count),grid),fract(at));
}
float hash(vec2 q) {
	return fract(sin(dot(q,vec2(127.1,311.7)))*43758.5453);
}
float noise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f*f*(3.-2.*f);
	return mix(mix(hash(i),hash(i+vec2(1.,0.)),f.x),mix(hash(i+vec2(0.,1.)),hash(i+vec2(1.,1.)),f.x),f.y);
}
float fbm(vec2 q) {
	return .57*noise(q)+.29*noise(q*2.03+11.)+.14*noise(q*4.01+23.);
}
void vertex() {
	point = VERTEX + vec3(bed_from.x+bed_size.x*.5,0.,bed_from.y+bed_size.y*.5);
}
void fragment() {
	vec2 p = pigment_cell(point.xz, 44.);
	float ground = texture(bed,(p-bed_from)/bed_size).r;
	float depth = level-ground;
	if (depth <= 0.) discard;
	// Clear over the first hand's depth, then green, then dark.
	float deep = smoothstep(.10,.52,depth);
	vec3 tone = mix(shallows,depths,deep);
	float cover = smoothstep(.0,.035,depth)*mix(.34,.93,smoothstep(.02,.40,depth));
	// The surface is a filmed one: a looping picture of small waves, laid twice at two
	// sizes and drifting across each other, gives its slope and height at every point.
	vec3 broad = looped(waves, p*.115+vec2(.012,.007)*TIME, TIME*6., 50., vec2(10.,5.));
	vec3 fine = looped(waves, p*.27-vec2(.009,.016)*TIME+.37, TIME*8.+17., 50., vec2(10.,5.));
	vec2 slope = (broad.rg-.5)*1.25+(fine.rg-.5)*.85;
	float height = broad.b*.6+fine.b*.4;
	vec3 lie = normalize(vec3(-slope.x*2.2,1.,-slope.y*2.2));
	float open = smoothstep(.02,.20,depth);
	// Crests are paler and hollows darker, more so over deep water where nothing shows through.
	tone *= 1.+open*(height-.5)*mix(.22,.50,deep);
	// The low sun lies along the crests that face it.
	vec3 eye = normalize((INV_VIEW_MATRIX*vec4(VIEW,0.)).xyz);
	vec3 sun = normalize(vec3(-.45,.62,-.38));
	float glitter = pow(max(dot(lie,normalize(sun+eye)),0.),160.);
	tone += open*glitter*vec3(.20,.20,.17);
	// And the sky lies on the faces turned away from us.
	tone += open*vec3(.050,.066,.076)*smoothstep(.0,.30,1.-lie.y)*1.6;
	// In the shallows the ripples throw nets of light on the bed.
	float net = looped(caustics, p*.47+slope*.10, TIME*11., 16., vec2(4.)).r;
	tone += (1.-deep)*smoothstep(.03,.14,depth)*net*vec3(.105,.120,.098);
	// Where a wave stands up the bed shows through less.
	cover = clamp(cover+.12*open*(height-.5)*(1.-deep),0.,1.);
	// At the edge the water comes in and draws back, and leaves a pale broken line.
	float lap = sin(TIME*.9+fbm(p*1.1)*9.);
	float reach = .018+.016*lap;
	float rim = (1.-smoothstep(reach,reach+.022,depth))*smoothstep(.0,.004,depth);
	float torn = smoothstep(.30,.62,fbm(p*6.+vec2(TIME*.25,0.)));
	tone = mix(tone,vec3(.60,.66,.61),.75*rim*torn);
	cover = max(cover,.72*rim*torn);
	ALBEDO = pigment_bands(tone,34.);
	ALPHA = cover;
}
