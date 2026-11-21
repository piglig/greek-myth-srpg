shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D pigments: source_color,filter_linear,repeat_disable;
void fragment(){
vec3 paint=mix(COLOR.rgb,texture(pigments,UV).rgb,COLOR.a);
vec3 n=normalize(mat3(INV_VIEW_MATRIX)*NORMAL);
ALBEDO=paint*(.89+.15*max(dot(n,normalize(vec3(-.4,.8,.45))),0.));
}
