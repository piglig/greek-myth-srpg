shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled;
#include "res://view/field_wind.gdshaderinc"
void vertex() {
	float bend = UV.y*UV.y*field_gust(VERTEX.xz,TIME);
	VERTEX.xz += vec2(.065,.028)*bend;
}
void fragment() {
	ALBEDO = COLOR.rgb;
}
