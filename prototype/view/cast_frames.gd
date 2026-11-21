class_name CastFrames
extends MeshInstance3D
## Eight registered views share the same painted ground anchor and camera projection.
var clips: Dictionary
var materials: Array[ShaderMaterial]=[]
var active_clip := ""
var active_view := -1
var active_frame := -1

func setup(kind: String):
	var folder="res://art/original/cast/%s/"%kind
	clips=load(folder+"frames.json").data
	mesh=QuadMesh.new()
	extra_cull_margin=3.
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for d in 8:
		var material=ShaderMaterial.new()
		material.shader=preload("res://view/hoplite_frame.gdshader")
		material.set_shader_parameter("atlas",load(folder+"view_%d.webp"%d))
		materials.append(material)
	display("idle",0,0)

func view_angle(yaw: float) -> float:
	var camera=get_viewport().get_camera_3d()
	if camera:
		var eye=camera.global_basis.z
		yaw-=atan2(eye.x,eye.z)
	return fposmod(yaw+deg_to_rad(15.),TAU)/TAU

func display(clip: String,d: int,index: int):
	var sequence: Array=clips[clip][d]
	index=clampi(index,0,sequence.size()-1)
	if active_clip==clip and active_view==d and active_frame==index: return
	if active_view!=d: material_override=materials[d]
	active_clip=clip
	active_view=d
	active_frame=index
	var r=sequence[index]
	set_instance_shader_parameter("frame_rect",Vector4(r[0],r[1],r[2],r[3]))
	set_instance_shader_parameter("frame_origin",Vector2(r[4],r[5]))

func sample(clip: String,d: int,progress: float):
	display(clip,d,roundi(clampf(progress,0.,1.)*(clips[clip][d].size()-1)))
