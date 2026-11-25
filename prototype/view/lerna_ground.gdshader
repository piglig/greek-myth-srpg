shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://view/pixel_pigment.gdshaderinc"
uniform sampler2D silt : source_color, repeat_enable, filter_linear_mipmap_anisotropic;
uniform sampler2D wet_cells : filter_linear, repeat_disable;
uniform vec2 field_size;
uniform vec2 channel = vec2(0.);
uniform vec3 shallows = vec3(.115,.218,.196);
uniform vec3 depths = vec3(.051,.120,.122);
uniform bool grid_lines = true;
varying vec3 ground_point;
void vertex() {
	ground_point = VERTEX;
}
void fragment() {
	vec2 p = pigment_cell(ground_point.xz, 44.);
	vec3 ink = texture(silt, p*.22).rgb;
	float grain = dot(ink, vec3(.26,.57,.17));
	vec2 bank = p + .13*vec2(sin(2.9*p.y+.7*p.x),sin(2.4*p.x+.6*p.y));
	vec2 soak = texture(wet_cells, bank / field_size).rg;
	float wet = soak.r;
	// Beyond the near and far edges of the map the channel opens into standing water.
	// lerna_field.gd draws the ground level there with the same shape.
	float beyond = max(-p.y, p.y-field_size.y);
	float inside = min(p.x-channel.x, channel.y-p.x) + .35*beyond;
	float open = channel.y > channel.x ? smoothstep(1.2,3.6,beyond+.5*sin(p.x*.9))*smoothstep(-.6,.6,inside) : 0.;
	wet = max(wet, open);
	soak.g *= 1.-open;
	float shore = smoothstep(.23,.77,wet + .30*(grain-.14));
	vec3 mud = ink*.78 + vec3(.103,.089,.075);
	mud *= mix(.80,1.10,smoothstep(-.06,.48,ground_point.y));
	vec3 water = mix(shallows,depths,smoothstep(.68,1.,wet));
	float stroke = sin(28.*p.y+3.7*sin(p.x*1.8+p.y)+2.*sin(p.y*1.8-.7*p.x)+TIME*1.32);
	float gaps = sin(p.x*3.7+p.y*.85+sin(p.y*2.)-TIME*.46);
	float open_water = sin(.83*p.x+.61*p.y)+.62*sin(1.24*p.y-.34*p.x);
	float glint = smoothstep(.82,.98,stroke)*smoothstep(.30,.86,gaps)*smoothstep(-.22,.81,open_water);
	water += .28*(ink-vec3(grain)) + grain*.24 + glint*vec3(.043,.052,.048);
	vec3 paint = mix(mud,water,shore);
	// Bog: dark, green, and flecked with duckweed, so nobody mistakes it for a path.
	float bog = smoothstep(.34,.66,soak.g + .22*(grain-.32));
	vec3 mire = vec3(.060,.082,.050) + ink*.30 + vec3(.0,.020,.0)*sin(9.*p.x+7.*p.y);
	float weed = smoothstep(.74,.92,sin(13.*p.x+4.*sin(5.*p.y))*sin(11.*p.y+3.*sin(6.*p.x)));
	mire = mix(mire,vec3(.215,.270,.105),.55*weed);
	paint = mix(paint,mire,bog*(1.-shore));
	// A narrow lip of freshly wetted silt describes the bank at normal zoom.
	paint *= 1.-.13*(1.-abs(2.*shore-1.));
	if (grid_lines && all(greaterThanEqual(p,vec2(0.))) && all(lessThan(p,field_size))) {
		vec2 edge = min(fract(p),1.-fract(p));
		paint *= 1.-.15*(1.-smoothstep(0.,.022,min(edge.x,edge.y)));
	}
	ALBEDO = pigment_bands(paint,34.);
	ROUGHNESS = 1.;
}
