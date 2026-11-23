shader_type spatial;
render_mode specular_disabled;
#include "res://view/field_wind.gdshaderinc"
#include "res://view/pixel_pigment.gdshaderinc"
uniform bool pixel_pigment = true;
instance uniform float flexibility = 0.0;
// 1 for boulders and cave arches: bedded limestone that matches the cliff faces.
instance uniform float limestone = 0.0;
uniform sampler2D cliff : source_color, repeat_enable, filter_linear_mipmap;
// Leaf strokes for the rounded tree masses (finish 7).
uniform sampler2D leaf_strokes : repeat_enable, filter_linear_mipmap;
varying float daylight;
uniform sampler2D grain : source_color, repeat_enable, filter_linear_mipmap;
varying vec3 point;
varying vec3 facing;
void vertex() {
	point = VERTEX;
	facing = NORMAL;
	vec3 world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	daylight = field_daylight(world.xz,TIME);
	float finish = floor(UV.x);
	float gust = field_gust(world.xz,TIME);
	if (finish == 6.0) {
		vec2 root = MODEL_MATRIX[3].xz;
		float seed = fract(dot(root,vec2(.347,.631)));
		float age = clamp(fract(TIME*(.085+.025*seed)+seed)*1.7,0.0,1.0);
		float envelope = smoothstep(0.0,.075,age)*(1.0-smoothstep(.89,1.0,age));
		vec3 pivot = vec3(.307,.578,.098);
		vec3 leaf = (VERTEX-pivot)*envelope;
		float roll = age*16.0+seed*8.0;
		leaf.xy = mat2(vec2(cos(roll),sin(roll)),vec2(-sin(roll),cos(roll)))*leaf.xy;
		vec2 slide = WIND_DIR*(age*(.8+.3*gust)) + vec2(-WIND_DIR.y,WIND_DIR.x)*.13*sin(age*10.0);
		VERTEX = pivot + leaf + transpose(mat3(MODEL_MATRIX))*vec3(slide.x,0.0,slide.y)/length(MODEL_MATRIX[0].xyz);
		VERTEX.y += -.56*age+.045*sin(age*14.0);
	} else if (flexibility > 0.0) {
		float bend = max(VERTEX.y,0.0);
		float flutter = finish == 4.0 ? 0.016*sin(dot(world.xz,vec2(3.9,2.2)) + TIME*4.2)*bend : 0.0;
		vec3 drift = vec3(WIND_DIR.x,0.0,WIND_DIR.y)*(0.12*bend*bend + flutter)*gust*flexibility;
		// The imported meshes have uniform scale and distinct rotations.
		VERTEX += transpose(mat3(MODEL_MATRIX))*drift / length(MODEL_MATRIX[0].xyz);
	} else if (finish == 5.0) {
		float hem = smoothstep(0.31,0.57,VERTEX.z);
		float ripple = sin(TIME*3.8 - VERTEX.x*9.0 + dot(world.xz,WIND_DIR));
		VERTEX.y += hem*gust*(0.028+0.022*ripple);
		VERTEX.z += hem*gust*0.016*ripple;
	}
}
void fragment() {
	vec3 weights = abs(normalize(facing));
	weights /= max(0.001, weights.x + weights.y + weights.z);
	float brush = dot(weights, vec3(texture(grain, point.yz * 2.1).r,
		texture(grain, point.xz * 2.1).r, texture(grain, point.xy * 2.1).r));
	float finish = floor(UV.x);
	vec2 board = vec2((fract(UV.x)-0.25)/0.3, UV.y);
	float fibre = texture(grain, board * vec2(1.8,26.0)).r;
	vec3 surface = COLOR.rgb * (0.82 + 0.66 * brush);
	if (finish == 1.0) {
		surface = COLOR.rgb * (0.66 + fibre);
	} else if (finish == 2.0) {
		surface = COLOR.rgb * (0.96 + 0.28 * brush);
	} else if (finish == 3.0) {
		surface = mix(vec3(0.023,0.019,0.017),COLOR.rgb,0.30 + 0.35*fibre);
	}
	if (pixel_pigment) {
		vec3 broad = vec3(textureLod(grain,pigment_cell(point.yz,52.)*1.4,3.).r,
			textureLod(grain,pigment_cell(point.xz,52.)*1.4,3.).r,
			textureLod(grain,pigment_cell(point.xy,52.)*1.4,3.).r);
		float wash = dot(weights,broad);
		vec3 paint = COLOR.rgb*(.91+.34*wash);
		if (finish == 3.) {
			paint = mix(vec3(.023,.019,.017),paint,.42);
		}
		surface = pigment_bands(paint,20.);
	}
	if (finish == 7.) {
		vec3 spread = mat3(MODEL_MATRIX)*point/1.3;
		// Explicit LOD: the stepped coordinates would otherwise pick a blurred mip.
		vec3 dabs = vec3(textureLod(leaf_strokes,pigment_cell(spread.yz,52.),0.).r,
			textureLod(leaf_strokes,pigment_cell(spread.xz,52.),0.).r,
			textureLod(leaf_strokes,pigment_cell(spread.xy,52.),0.).r);
		float dab = dot(weights,dabs);
		surface = COLOR.rgb*(.34+1.40*dab);
		if (pixel_pigment) {
			surface = pigment_bands(surface,20.);
		}
		// Fray the outline into leaves where the mass turns away from the viewer.
		if (normalize(NORMAL).z < .04+.62*dab*dab) {
			discard;
		}
	}
	if (limestone > 0.) {
		vec3 world = (MODEL_MATRIX*vec4(point,1.)).xyz;
		vec3 away = normalize(mat3(MODEL_MATRIX)*facing);
		vec3 blend = abs(away);
		blend /= blend.x+blend.y+blend.z;
		vec2 side = pixel_pigment ? pigment_cell(vec2((world.x+world.z)*.19,-world.y*.62),88.) : vec2((world.x+world.z)*.19,-world.y*.62);
		vec2 cap = pixel_pigment ? pigment_cell(world.xz*.16,88.) : world.xz*.16;
		vec3 bed = mix(texture(cliff,side).rgb,texture(cliff,cap).rgb*vec3(1.05,1.02,.96),blend.y);
		// Darken the foot so each stone sits in the ground.
		bed *= mix(.70,1.,smoothstep(0.,.42,point.y));
		surface = pixel_pigment ? pigment_bands(bed,20.) : bed;
		// Round off the facets: light the stone as a lump as well as by its planes.
		vec3 lump = normalize(mat3(VIEW_MATRIX)*mat3(MODEL_MATRIX)*normalize(point-vec3(0.,.12,0.)));
		NORMAL = normalize(mix(NORMAL,lump,.62));
	}
	ALBEDO = surface*daylight;
	ROUGHNESS = 1.0;
}
