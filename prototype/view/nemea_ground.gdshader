shader_type spatial;
render_mode specular_disabled, cull_disabled;
#include "res://view/field_wind.gdshaderinc"
#include "res://view/pixel_pigment.gdshaderinc"
uniform bool pixel_pigment = true;
uniform sampler2D stone : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D cliff : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
// Standing height of every rule cell, in world units, one texel per cell.
uniform sampler2D levels : filter_linear, repeat_disable;
uniform bool grid_lines = true;
uniform vec2 field_size;
uniform bool village_lane;
uniform bool woodland;
// Painted texels per world unit, matched to the unit sprites at the default zoom.
const float TEXEL = 40.;
varying vec3 local_point;
varying vec3 face_normal;
void vertex() {
	local_point = VERTEX;
	face_normal = NORMAL;
}
float land(vec2 at) {
	return texture(levels,at/field_size).r;
}
void fragment() {
	vec3 p = local_point;
	vec3 n = normalize(face_normal);
	float grade = 1.0-n.y;
	vec2 cell = pixel_pigment ? pigment_cell(p.xz,TEXEL) : p.xz;
	float inside = step(0.,min(min(p.x,field_size.x-p.x),min(p.z,field_size.y-p.z)));

	// Walkable ground: pale limestone, warmer and lighter with each level.
	vec3 paint = texture(stone,cell*.19).rgb;
	float mottle = textureLod(stone,cell*.047+vec2(.31,.17),2.).g;
	float grain = texture(stone,cell*.61).r;
	// Pull the painted stone toward pale cream so warm skin and cloth stand clear of it.
	float value = dot(paint,vec3(.2126,.7152,.0722));
	paint = mix(paint,vec3(value)*vec3(1.08,1.02,.90),.42);
	vec3 ground = paint*mix(vec3(.86,.81,.75),vec3(1.10,1.07,1.01),smoothstep(.42,.74,mottle));
	ground *= .93+.14*grain;
	float rise = clamp(p.y/2.25,0.,1.);
	ground *= mix(vec3(.90,.89,.90),vec3(1.07,1.04,.98),rise);
	if (village_lane) {
		// Compacted earth from the central approach to the north gate.
		float path_x = mix(8.5,2.7,smoothstep(.5,7.8,p.z));
		float tread = 1.0-smoothstep(.7,3.4,abs(p.x-path_x)+.21*sin(p.z*1.5));
		ground = mix(ground,vec3(.47,.38,.27)*(.75+.5*grain),tread*.62);
	}
	if (woodland) {
		float verge = smoothstep(.62,2.1,abs(p.z-5.9-.42*sin(p.x*.7))+.38*(grain-.5));
		ground *= mix(vec3(1.08,.97,.80),vec3(.56,.74,.52),verge);
	}

	// Rock faces: horizontal beds, darker and cooler toward the foot.
	vec2 strata = vec2((p.x+p.z)*.23,-p.y*.56+.025*sin(p.x*2.7+p.z));
	if (pixel_pigment) {
		strata = pigment_cell(strata,TEXEL*2.2);
	}
	vec3 rock = texture(cliff,strata).rgb;
	float foot = land(p.xz+n.xz*.6);
	float depth = clamp((p.y-foot)/1.5,0.,1.);
	rock *= mix(vec3(.60,.61,.68),vec3(.98,.95,.90),smoothstep(0.,.75,depth));

	float exposed = smoothstep(.10,.34,grade+(grain-.5)*.06);
	vec3 base = mix(ground,rock,exposed);

	if (inside > 0.) {
		// Contact shade below a rise and a worn light lip above a drop, from the rule heights.
		float around = max(max(land(p.xz+vec2(.42,0.)),land(p.xz-vec2(.42,0.))),
			max(land(p.xz+vec2(0.,.42)),land(p.xz-vec2(0.,.42))));
		float below = min(min(land(p.xz+vec2(.2,0.)),land(p.xz-vec2(.2,0.))),
			min(land(p.xz+vec2(0.,.2)),land(p.xz-vec2(0.,.2))));
		float shade = smoothstep(.04,.62,around-p.y)*(1.-exposed);
		base *= mix(vec3(1.),vec3(.63,.62,.68),shade);
		float lip = smoothstep(.03,.28,p.y-below)*(1.-exposed);
		base *= 1.+.13*lip;
		if (grid_lines && n.y > 0.96) {
			vec2 seams = min(fract(p.xz),1.0-fract(p.xz));
			float line = 1.0-smoothstep(0.0,0.024,min(seams.x,seams.y));
			base *= 1.0-line*0.24;
		}
	}
	if (pixel_pigment) {
		base = pigment_bands(base,20.);
	}
	float margin = max(max(-p.x,p.x-field_size.x),max(-p.z,p.z-field_size.y));
	base *= mix(vec3(1.0),vec3(0.55,0.63,0.61),smoothstep(0.0,4.5,margin));
	ALBEDO = base*field_daylight(p.xz,TIME);
}
