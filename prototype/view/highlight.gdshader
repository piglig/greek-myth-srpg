shader_type spatial;
// Opaque stipple overlay: discarding every other low-res pixel keeps it out of the transparent
// pass, so the pixel post-process (which reads the screen texture) still sees it.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform int pattern = 0; // 0 / 1 = checker phase, 2 = solid

void fragment() {
	ivec2 p = ivec2(FRAGCOORD.xy);
	if (pattern < 2 && ((p.x + p.y + pattern) % 2) == 0) {
		discard;
	}
	ALBEDO = color.rgb;
}
