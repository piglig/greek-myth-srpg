shader_type canvas_item;
uniform float region;
uniform vec4 paper : source_color;
uniform vec4 hills : source_color;
uniform vec4 water : source_color;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p),f=fract(p); f=f*f*(3.-2.*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+1.),f.x),f.y);
}
void fragment(){
	vec2 q=UV*vec2(1.7,1.0);
	vec2 p=q+vec2(region*3.9,region*.74);
	float h=.50*noise(p*3.)+.26*noise(p*6.)+.13*noise(p*12.)+.065*noise(p*24.)+.025*noise(p*51.);
	h+=.22*(1.-UV.y)-.38*smoothstep(.76,1.03,UV.x)*smoothstep(.27,.85,UV.y);
	float step_h=floor(h*19.)/19.;
	vec3 ink=mix(paper.rgb,hills.rgb,clamp((step_h-.30)*1.35,0.,.80));
	float contour=1.-smoothstep(.012,.071,abs(fract(h*19.+.5)-.5));
	ink*=1.-.12*contour;
	float coast=smoothstep(.325,.331,h);
	vec3 sea=water.rgb*(.98+.06*cos(h*265.));
	ink=mix(sea,ink,coast);
	ink*=.968+.065*hash(floor(q*900.));
	COLOR=vec4(ink,1.);
}
