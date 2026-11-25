shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
// The bed of the marsh and its banks. The water is a sheet of its own (lerna_water).
// Three grounds: rippled sand where it is dry, mud with stones in it where the water
// reaches, bedded rock where it is cut steep (ambientCG, CC0). Bog is painted over them.
#include "res://view/pixel_pigment.gdshaderinc"
uniform sampler2D silt : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D sand_relief : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D mud : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D mud_relief : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D rock_relief : hint_normal, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D wet_cells : filter_linear, repeat_disable;
uniform vec2 field_size;
uniform float water_level = .04;
uniform vec3 dry_tint : source_color = vec3(.80,.74,.66);
uniform bool grid_lines = true;
varying vec3 ground_point;
varying vec3 ground_up;
void vertex() {
	ground_point = VERTEX;
	ground_up = NORMAL;
}
void fragment() {
	vec2 p = pigment_cell(ground_point.xz, 44.);
	vec3 ink = texture(silt, p*.22).rgb;
	float grain = dot(ink, vec3(.26,.57,.17));
	vec2 bank = p + .13*vec2(sin(2.9*p.y+.7*p.x),sin(2.4*p.x+.6*p.y));
	vec3 soak = texture(wet_cells, bank / field_size).rgb;
	float above = ground_point.y - water_level;
	vec3 up = normalize(ground_up);
	float steep = smoothstep(.20,.52,1.-up.y);
	// Where each ground lies.
	float damp = 1.-smoothstep(-.02,.24+.14*(grain-.3),above);
	float face = steep*smoothstep(-.05,.12,above);
	// Rock is laid on the face it belongs to, so its beds run level along the bank.
	vec2 along = abs(up.x) > abs(up.z) ? vec2(p.y,ground_point.y*1.6) : vec2(p.x,ground_point.y*1.6);
	// The sand is a photograph of a yellow beach: keep its ripples, take most of its colour
	// from the field's own earth.
	vec3 sand_ink = texture(sand, p*.31).rgb;
	sand_ink = mix(vec3(dot(sand_ink,vec3(.3,.59,.11))),sand_ink,.38)*dry_tint*1.12;
	vec3 mud_ink = texture(mud, p*.27).rgb*vec3(.72,.70,.66);
	vec3 rock_ink = texture(rock, along*.42).rgb*vec3(.80,.74,.66);
	vec3 paint = mix(sand_ink, mud_ink, damp);
	paint = mix(paint, rock_ink, face);
	// The same choice for the small relief that catches the light.
	vec3 bump = mix(texture(sand_relief, p*.31).rgb, texture(mud_relief, p*.27).rgb, damp)*2.-1.;
	vec3 rough = texture(rock_relief, along*.42).rgb*2.-1.;
	vec3 lifted = normalize(up + mix(.55*vec3(bump.x,0.,-bump.y), .8*vec3(rough.x,rough.y*.5,rough.x*.4), face));
	NORMAL = normalize((VIEW_MATRIX * vec4(lifted,0.)).xyz);
	// Paler and drier the higher it stands; dark where the water has just been.
	paint *= mix(.90,1.12,smoothstep(.15,1.4,above));
	paint *= 1.-.34*damp*(1.-face);
	// Bog: dark, green, and flecked with duckweed, so nobody mistakes it for a path.
	float bog = smoothstep(.34,.66,soak.g + .22*(grain-.32));
	vec3 mire = vec3(.060,.082,.050) + ink*.30 + vec3(.0,.020,.0)*sin(9.*p.x+7.*p.y);
	float weed = smoothstep(.74,.92,sin(13.*p.x+4.*sin(5.*p.y))*sin(11.*p.y+3.*sin(6.*p.x)));
	mire = mix(mire,vec3(.215,.270,.105),.55*weed);
	paint = mix(paint,mire,bog*smoothstep(-.10,-.02,above));
	// Under the water the bed keeps its grain and loses its warmth.
	float under = smoothstep(.0,-.10,above);
	paint = mix(paint, paint*vec3(.70,.86,.80), under);
	if (grid_lines && all(greaterThanEqual(p,vec2(0.))) && all(lessThan(p,field_size))) {
		vec2 edge = min(fract(p),1.-fract(p));
		paint *= 1.-.15*(1.-smoothstep(0.,.022,min(edge.x,edge.y)));
	}
	ALBEDO = pigment_bands(paint,34.);
	ROUGHNESS = 1.;
}
