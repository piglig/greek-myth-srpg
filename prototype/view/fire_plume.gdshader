shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
#include "res://view/field_wind.gdshaderinc"
instance uniform float density = 1.0;
varying float age;
varying float seed;
varying float spark;
void vertex() {
	vec3 source = MODEL_MATRIX[3].xyz;
	seed = fract(dot(source.xz,vec2(0.381,0.717)) + COLOR.r);
	spark = COLOR.g;
	age = fract(TIME*mix(0.32,0.64,spark)+seed);
	float gust = field_gust(source.xz,TIME);
	vec2 drift = WIND_DIR*age*age*(0.66+0.54*gust);
	drift += vec2(sin(age*7.0+seed*31.0),cos(age*5.0+seed*19.0))*age*.12;
	vec3 center = source+vec3(drift.x,0.27+age*mix(1.55,1.15,spark),drift.y);
	vec2 size = mix(vec2(.25+.75*age,.25+.64*age),vec2(.032,.055),spark);
	vec3 world = center + INV_VIEW_MATRIX[0].xyz*VERTEX.x*size.x
		+ INV_VIEW_MATRIX[1].xyz*VERTEX.y*size.y;
	POSITION = PROJECTION_MATRIX*VIEW_MATRIX*vec4(world,1.0);
}
void fragment() {
	vec2 p = UV*2.0-1.0;
	p.x += .12*sin(p.y*5.1+age*5.0+seed*19.0);
	float r = length(p) + .10*sin(p.x*4.3+seed*24.0)*cos(p.y*4.7-age*4.0);
	float fade = smoothstep(0.0,.13,age)*(1.0-smoothstep(.50,1.0,age));
	float opacity = (1.0-smoothstep(.32,1.0,r))*fade;
	ALBEDO = mix(mix(vec3(.12,.10,.085),vec3(.32,.29,.25),age),vec3(1.0,.44,.08),spark);
	ALPHA = opacity*mix(.38,.90,spark)*density;
}
