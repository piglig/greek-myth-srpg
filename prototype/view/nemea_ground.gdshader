shader_type spatial;
render_mode specular_disabled, cull_disabled;
#include "res://view/field_wind.gdshaderinc"
#include "res://view/pixel_pigment.gdshaderinc"
uniform bool pixel_pigment = true;
uniform sampler2D stone : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D cliff : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec2 field_size;
uniform bool village_lane;
uniform bool woodland;
varying vec3 local_point;
varying vec3 face_normal;
void vertex() {
	local_point = VERTEX;
	face_normal = NORMAL;
}
void fragment() {
	vec3 p = local_point;
	vec3 n = normalize(face_normal);
	vec2 coords = p.xz * 0.19;
	vec3 earth = texture(stone,coords).rgb;
	float grain = texture(stone,p.xz*.44).r;
	if (village_lane) {
		// Compacted earth from the central approach to the north gate.
		float path_x = mix(8.5,2.7,smoothstep(.5,7.8,p.z));
		float distance_to_path = abs(p.x-path_x)+.21*sin(p.z*1.5);
		float tread = (1.0-smoothstep(.7,3.4,distance_to_path))*smoothstep(.80,.98,n.y);
		vec3 patch = (earth+texture(stone,coords+vec2(.014,.008)).rgb+texture(stone,coords-vec2(.009,.017)).rgb)/3.;
		float broad_value = dot(patch,vec3(.2126,.7152,.0722));
		vec3 dust = vec3(.40,.32,.225)*(.83+.48*broad_value);
		earth = mix(earth,dust,tread*.73);
	}
	float grade = 1.0-n.y;
	float exposed = smoothstep(.10,.52,grade+(grain-.4)*.12);
	vec2 strata = vec2((p.x+p.z)*.23,-p.y*.56 + .025*sin(p.x*2.7+p.z));
	vec3 rock = texture(cliff,strata).rgb;
	if (pixel_pigment) {
		vec2 plane = pigment_cell(p.xz,14.);
		vec3 wash = textureLod(stone,plane*.17,4.).rgb;
		float ochre = dot(wash,vec3(.2126,.7152,.0722));
		float lane = village_lane ? 1.-smoothstep(.7,3.4,abs(p.x-mix(8.5,2.7,smoothstep(.5,7.8,p.z)))) : .55;
		vec3 soil = mix(vec3(.34,.263,.175),vec3(.48,.377,.256),lane);
		vec3 quiet_soil = pigment_bands(soil*(.64+1.02*ochre)+.14*wash,18.);
		// Let the original painted limestone show through along sloping shoulders.
		float shoulder = smoothstep(.025,.23,grade);
		earth = mix(quiet_soil,earth,.80*shoulder);
		vec2 ledge = pigment_cell(strata,70.);
		vec3 mineral = textureLod(cliff,ledge,2.5).rgb;
		rock = mix(rock,pigment_bands(mineral,22.),.23);
	}
	if (woodland) {
		float verge = smoothstep(.62,2.1,abs(p.z-5.9-.42*sin(p.x*.7))+.38*(grain-.5));
		earth *= mix(vec3(1.08,.97,.80),vec3(.56,.74,.52),verge);
	}
	vec3 base = mix(earth,rock*.93,exposed);
	if (n.y > 0.96 && p.x >= 0.0 && p.x < field_size.x && p.z >= 0.0 && p.z < field_size.y) {
		vec2 seams = min(fract(p.xz),1.0-fract(p.xz));
		float line = 1.0-smoothstep(0.0,0.021,min(seams.x,seams.y));
		base *= 1.0 - line*0.15;
	}
	float margin = max(max(-p.x,p.x-field_size.x),max(-p.z,p.z-field_size.y));
	base *= mix(vec3(1.0),vec3(0.55,0.63,0.61),smoothstep(0.0,4.5,margin));
	ALBEDO = base*field_daylight(p.xz,TIME);
}
