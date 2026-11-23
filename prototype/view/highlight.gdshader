shader_type spatial;
// Opaque stipple overlay: discarding every other low-res pixel keeps it out of the transparent
// pass, so the pixel post-process (which reads the screen texture) still sees it.
render_mode unshaded, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform int pattern = 0; // 0 / 1 = checker phase, 2 = solid

uniform float inset = 0.0;
instance uniform int edges = 0;
uniform bool frame = false;

void fragment() {
	vec2 sides = min(UV,1.0-UV);
	float edge = min(sides.x,sides.y);
	// A frame is drawn a little inside the cell, clear of the strip where a cliff may begin.
	if (edge < inset || (frame && (edge < 0.05 || edge > 0.12))) { discard; }
	ivec2 p = ivec2(FRAGCOORD.xy);
	if (pattern == 3) {
		bool rim = (UV.x < .047 && (edges & 1) != 0) || (UV.x > .953 && (edges & 2) != 0)
			|| (UV.y < .047 && (edges & 4) != 0) || (UV.y > .953 && (edges & 8) != 0);
		if (!rim && (p.x % 3 != 0 || p.y % 3 != 0)) { discard; }
	}
	if (pattern < 2 && ((p.x + p.y + pattern) % 2) == 0) {
		discard;
	}
	ALBEDO = color.rgb;
}
