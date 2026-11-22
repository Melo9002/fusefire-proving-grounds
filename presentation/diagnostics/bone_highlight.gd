class_name BoneHighlight
extends Node
## Optional, read-only highlight of chosen bones in the viewport: a ring-cross at each bone's FINAL position and a line to its parent, so "which bones does this stage or role touch" can be seen on the body.
## Positions are read only from the skeleton's `skeleton_updated` signal (the pose is final there; see ContactErrorDiagnostics). With no bones chosen it is not connected to anything and draws nothing.

var rig: CharacterRig
var bone_names: Array[String] = []
var colour := Color(1.0, 0.35, 0.95)
var _skeleton: Skeleton3D
var _lines: MeshInstance3D
var _mesh: ImmediateMesh
var _open := false

static func attach(p_rig: CharacterRig) -> BoneHighlight:
	if not is_instance_valid(p_rig) or p_rig.skeleton == null:
		return null
	var highlight := BoneHighlight.new()
	highlight.name = "BoneHighlight"
	highlight.rig = p_rig
	highlight._skeleton = p_rig.skeleton
	p_rig.add_child(highlight)
	return highlight

## Highlights these bones (an empty list clears the highlight and disconnects).
func set_bones(names: Array[String], p_colour := Color(1.0, 0.35, 0.95)) -> void:
	bone_names = names
	colour = p_colour
	if names.is_empty():
		_release()
		return
	if _lines == null:
		_lines = MeshInstance3D.new()
		_lines.name = "BoneHighlightLines"
		_lines.top_level = true
		_mesh = ImmediateMesh.new()
		_lines.mesh = _mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.no_depth_test = true
		_lines.material_override = material
		_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_lines)
	if not _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		_skeleton.skeleton_updated.connect(_on_skeleton_updated)

func is_active() -> bool:
	return _lines != null or (is_instance_valid(_skeleton) and _skeleton.skeleton_updated.is_connected(_on_skeleton_updated))

func _release() -> void:
	if is_instance_valid(_skeleton) and _skeleton.skeleton_updated.is_connected(_on_skeleton_updated):
		_skeleton.skeleton_updated.disconnect(_on_skeleton_updated)
	if is_instance_valid(_lines):
		_lines.queue_free()
	_lines = null
	_mesh = null

func _exit_tree() -> void:
	_release()

func _on_skeleton_updated() -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	var origin := _skeleton.global_transform
	_open = false
	for bone_name in bone_names:
		var index := _skeleton.find_bone(bone_name)
		if index < 0:
			continue
		var at: Vector3 = origin * _skeleton.get_bone_global_pose(index).origin
		var parent := _skeleton.get_bone_parent(index)
		if parent >= 0:
			_segment(origin * _skeleton.get_bone_global_pose(parent).origin, at)
		for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
			_segment(at - axis * 0.025, at + axis * 0.025)
	if _open:
		_mesh.surface_end()

func _segment(a: Vector3, b: Vector3) -> void:
	if not _open:
		_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		_open = true
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(a)
	_mesh.surface_set_color(colour)
	_mesh.surface_add_vertex(b)
