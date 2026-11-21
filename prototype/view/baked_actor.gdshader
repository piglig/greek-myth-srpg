shader_type spatial;
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
uniform sampler2D sheet : source_color, filter_nearest, repeat_disable;
uniform sampler2D motion_sheet : source_color, filter_nearest, repeat_disable;
uniform sampler2D pivot_sheet : source_color, filter_nearest, repeat_disable;
instance uniform float pivot_frame = -1.;
uniform float source_columns;
uniform sampler2D painted_action_sheet : source_color, filter_nearest, repeat_disable;
uniform vec4 parry_warp=vec4(0.);
uniform float painted_action_key = -1.;
uniform float art_scale = 1.;
instance uniform vec4 reveal_region = vec4(0.0);
uniform bool spear_carrier;
uniform bool wolf_coat;
uniform bool bow_carrier;
instance uniform float bow_tension;
instance uniform float bow_drop;
instance uniform float bow_pose;
instance uniform bool live_arrow;
uniform float breath_phase;
instance uniform float roar_lift = 0.;
instance uniform vec2 motion_tile = vec2(-1.0);
instance uniform vec2 stride;
instance uniform vec2 nearby_stone;
instance uniform vec2 recoil = vec2(0.0);
varying float ground_y;
void vertex() {
	if (painted_action_key >= 0.) { VERTEX.x *= float(textureSize(painted_action_sheet,0).x)/(8.*160.); }
	VERTEX.xy += max(VERTEX.y,0.0)*(recoil+stride);
	VERTEX.y += max(VERTEX.y,0.0)*.009*sin(TIME*2.6+breath_phase);
	ground_y = MODEL_MATRIX[3].y;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0]*length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX[1]*length(MODEL_MATRIX[1].xyz), INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}
void fragment() {
	// Project foreground feet onto their actual support plane. A flat billboard
	// otherwise buries pixels below the pivot when seen from above.
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX,1.0)).xyz;
	vec3 view_point = VERTEX;
	view_point.z += max(0.0, ground_y-world.y) / max(0.1,INV_VIEW_MATRIX[2].y);
	// A camera-facing sprite leans into the scenery behind its feet. At a
	// boulder, test the upper body at the depth of an upright silhouette.
	vec3 eye = INV_VIEW_MATRIX[2].xyz;
	if (dot(nearby_stone,eye.xz)<-.02) {
		view_point.z += max(0.,world.y-ground_y)*eye.y/max(.15,1.-eye.y*eye.y);
	}
	vec4 clip = PROJECTION_MATRIX * vec4(view_point,1.0);
	DEPTH = clip.z/clip.w;
	LIGHT_VERTEX = view_point;
	vec2 tile_grid = vec2(source_columns,2.0);
	vec2 tile = floor(UV*tile_grid);
	vec2 frame_size = vec2(320.0,256.0);
	vec2 pixel = fract(UV*tile_grid)*frame_size;
	float weapon_side = tile.y < 0.5 ? -1.0 : 1.0;
	bool pivoting = pivot_frame >= 0.;
	if (pivoting) {
		float angle = pivot_frame * (6.2831853/64.);
		weapon_side = clamp(3.0*sin(angle-.25),-1.,1.);
	}
	// Lift the painted muzzle and mane against the planted paws in both source views.
	if (roar_lift != 0.) {
		vec2 muzzle = tile.y < .5 ? vec2(121.,150.) : vec2(206.,71.);
		vec2 local = (pixel-muzzle)/vec2(75.,84.);
		float neck = exp(-dot(local,local))*(1.-smoothstep(180.,220.,pixel.y));
		pixel.y += 23.*neck*roar_lift;
		pixel.x -= 5.*weapon_side*neck*roar_lift;
	}
	float outboard = (pixel.x-160.0)*weapon_side;
	if (spear_carrier) {
		// Open the weapon arm away from the torso while keeping the feet registered.
		float arm = smoothstep(3.0,35.0,outboard)*(1.0-smoothstep(146.0,194.0,pixel.y));
		pixel.x -= weapon_side*arm*(7.0+max(125.0-pixel.y,0.0)*0.105);
	}
	// Carry and draw tiles share the weapon side.
	
	float bow_side = weapon_side;
	float bow_edge = (pixel.x-160.)*bow_side;
	float bow_arm = smoothstep(0.,43.,bow_edge)*(1.-smoothstep(161.,204.,pixel.y));
	if (bow_carrier) {
		pixel.x -= bow_side*bow_arm*mix(15.,5.+11.*bow_tension,bow_pose);
		pixel.y -= bow_pose*bow_arm*(bow_drop+(1.-bow_tension)*24.);
	}
	bool moving = motion_tile.x >= 0.0;
	vec2 origin = (moving ? motion_tile : tile)*frame_size;
	vec2 atlas_size = moving ? vec2(textureSize(motion_sheet,0)) : vec2(textureSize(sheet,0));
	vec2 atlas_uv = (origin+clamp(pixel,vec2(.5),frame_size-.5))*art_scale/atlas_size;
	vec4 pigment = moving ? texture(motion_sheet,atlas_uv) : texture(sheet,atlas_uv);
	if (pivoting) {
		vec2 cell = vec2(mod(pivot_frame,8.),floor(pivot_frame/8.));
		atlas_size = vec2(textureSize(pivot_sheet,0));
		atlas_uv = (cell*frame_size+clamp(pixel,vec2(.5),frame_size-.5))*art_scale/atlas_size;
		pigment = texture(pivot_sheet,atlas_uv);
	}
	if (painted_action_key >= 0.) {
		vec2 cell = vec2(mod(painted_action_key,8.),floor(painted_action_key/8.)+7.*tile.y);
		vec2 local=fract(UV*tile_grid);
		if(parry_warp.x>0.){
			vec2 px=local*vec2(256.,128.);
			float reach=parry_warp.y-parry_warp.x;
			float dx=clamp(parry_warp.z*sign(reach),-.85*abs(reach),abs(reach))*sign(reach);
			float arm=clamp((px.x-parry_warp.x)/(reach+dx),0.,1.);
			float source_y=px.y-parry_warp.w*arm;
			arm*=1.-smoothstep(72.,91.,max(px.y,source_y));
			local-=vec2(dx,parry_warp.w)*arm/vec2(256.,128.);
		}
		pigment = texture(painted_action_sheet,(cell+clamp(local,vec2(.0001),vec2(.9999)))/vec2(8.,14.));
	}
	if (spear_carrier) {
		// Keep the narrow shaft visible at the native battlefield zoom.
		if (painted_action_key < 0. && pigment.a < .5 && outboard > 23.0 && pixel.y < 158.0) {
			vec2 inward = vec2(weapon_side*1.75,0.0)*art_scale/atlas_size;
			vec4 edge = moving ? texture(motion_sheet,atlas_uv-inward) : texture(sheet,atlas_uv-inward);
			if (pivoting) { edge = texture(pivot_sheet,atlas_uv-inward); }
			if (edge.a > .7 && pixel.x > 3. && pixel.x < 317.) {
				pigment = vec4(edge.rgb*.78,edge.a);
			}
		}
		float terracotta = smoothstep(.028,.18,pigment.r-pigment.g);
		pigment.rgb *= mix(vec3(1.08,1.04,1.),vec3(1.32,.98,.86),terracotta);
	}
	if (bow_carrier) {
		float limb = smoothstep(19.,40.,bow_edge)*(1.-smoothstep(165.,190.,pixel.y));
		if (painted_action_key < 0. && limb>.1 && pigment.a<.5) {
			vec2 inward = vec2(bow_side*1.6,0.)*art_scale/atlas_size;
			vec4 rim = moving ? texture(motion_sheet,atlas_uv-inward) : texture(sheet,atlas_uv-inward);
			if (pivoting) { rim = texture(pivot_sheet,atlas_uv-inward); }
			if (rim.a>.72) { pigment = rim; }
		}
		float value = dot(pigment.rgb,vec3(.21,.72,.07));
		float mantle = (1.-smoothstep(.07,.22,value))*(1.-limb);
		pigment.rgb *= mix(vec3(1.22,1.13,.99),vec3(.81,1.15,1.12),mantle);
		pigment.rgb = mix(pigment.rgb,pigment.rgb*vec3(1.18,1.11,.82)+vec3(.07,.036,.004),limb);
		// Leave the arrowhead to the live sprite once it is nocked.
		if (painted_action_key < 0. && !pivoting && bow_pose>.05 && live_arrow) {
			float grip = tile.y < .5 ? 114. : 206.;
			float shaft_y = tile.y < .5 ? 109.-(pixel.x-grip)*.27 : 69.-(pixel.x-grip)*.5;
			if ((pixel.x-grip)*bow_side>5. && abs(pixel.y-shaft_y)<5.) { pigment.a=0.; }
		}
	}
	if (wolf_coat) {
		float value = dot(pigment.rgb,vec3(.2126,.7152,.0722));
		float silver = smoothstep(.035,.30,value);
		pigment.rgb = mix(pigment.rgb,vec3(value)*vec3(.83,1.04,1.26),.70);
		pigment.rgb *= mix(.79,1.24,silver);
	}
	// Thin only the foreground pixels that cover the inspected unit.
	if (reveal_region.z > 0.) {
		vec2 offset = (SCREEN_UV-reveal_region.xy)/reveal_region.zw;
		if (dot(offset,offset)<1. && mod(floor(FRAGCOORD.x)+floor(FRAGCOORD.y),2.)<1.) { discard; }
	}
	ALPHA = pigment.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALBEDO = pigment.rgb;
	EMISSION = pigment.rgb * vec3(0.40,0.43,0.49);
}
void light() {
	// Form lighting is already in the atlas. Only the local shadow modulates it.
	if (LIGHT_IS_DIRECTIONAL) {
		DIFFUSE_LIGHT += vec3(0.60,0.57,0.51) * ATTENUATION;
	}
}
