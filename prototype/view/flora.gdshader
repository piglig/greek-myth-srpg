shader_type spatial;
render_mode specular_disabled, cull_disabled;
// Trees, bushes and grass from the Quaternius Stylized Nature MegaKit (CC0). Its leaf
// textures carry shape only, so the colour is ours: a dusty Mediterranean ramp, light on
// the crown and dark underneath, quantised like the rest of the field.
#include "res://view/field_wind.gdshaderinc"
#include "res://view/pixel_pigment.gdshaderinc"
uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform int part = 0; // 0 bark, 1 leaves, 2 grass
uniform vec3 shade_pigment : source_color = vec3(.20,.26,.16);
uniform vec3 light_pigment : source_color = vec3(.52,.58,.36);
instance uniform vec3 crown_centre = vec3(0.,1.,0.);
instance uniform vec3 crown_reach = vec3(1.);
instance uniform float tallness = 1.0;
varying float daylight;
varying vec3 outward;
varying vec3 world_point;
void vertex() {
	vec3 world = (MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
	daylight = field_daylight(world.xz,TIME);
	outward = normalize((VERTEX-crown_centre)/crown_reach);
	if (part != 0) {
		// Light every leaf card as part of one rounded crown.
		NORMAL = normalize(mix(NORMAL,outward,part == 1 ? .85 : .0)+vec3(0.,part == 2 ? 1.2 : 0.,0.));
	}
	float size = length(MODEL_MATRIX[0].xyz);
	float lift = clamp(VERTEX.y/tallness,0.,1.);
	float gust = field_gust(world.xz,TIME);
	float flutter = part == 0 ? 0. : .012*sin(dot(world.xz,vec2(3.9,2.2))+TIME*4.2);
	vec3 drift = vec3(WIND_DIR.x,0.,WIND_DIR.y)*(.05*lift*lift+flutter*lift)*gust*(part == 2 ? 1.8 : 1.);
	VERTEX += transpose(mat3(MODEL_MATRIX))*drift/(size*size);
	world_point = world;
}
float speckle(vec3 at) {
	return fract(sin(dot(floor(at),vec3(12.9898,78.233,37.719)))*43758.5453);
}
void fragment() {
	vec4 paint = texture(albedo_map,UV);
	vec3 surface;
	if (part == 0) {
		float value = dot(paint.rgb,vec3(.2126,.7152,.0722));
		surface = mix(paint.rgb,vec3(value)*vec3(1.05,.98,.86),.55)*1.25;
	} else {
		if (part == 1 && paint.a < .5) {
			discard;
		}
		float crown = smoothstep(-.55,.85,outward.y);
		float clump = speckle(world_point*5.);
		float dab = speckle(world_point*26.);
		surface = mix(shade_pigment,light_pigment,clamp(crown*.85+.22*(clump-.5),0.,1.));
		surface *= .86+.26*dab;
		if (part == 2) {
			float value = dot(paint.rgb,vec3(.2126,.7152,.0722));
			surface = mix(shade_pigment,light_pigment,clamp(UV.y*.2+value*1.1,0.,1.))*(.9+.2*dab);
		}
	}
	ALBEDO = pigment_bands(surface,20.)*daylight;
	ROUGHNESS = 1.;
}
