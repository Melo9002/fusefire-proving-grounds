class_name LadderOverlay
extends Node3D
## READ-ONLY overlay for the climbing body against the ladder, drawn in the world so a person can SEE where the legs meet the bars: a red marker on every skinned leg vertex that is inside a rung or a rail (up to a
## limit, deepest first), a text label at the worst one (bone, bar, depth), yellow markers on the knee centres, a green marker on the pelvis and orange ones on the planned foot targets. It owns its nodes and
## writes nothing to the character: it takes the LadderClearance sample the owner already made inside `skeleton_updated`, so it costs nothing until `show_sample` is called.

const MARKER_LIMIT := 40
const THRESHOLD := 0.003

var _markers: Array[MeshInstance3D] = []
var _knee_markers: Array[MeshInstance3D] = []
var _pelvis_marker: MeshInstance3D
var _target_markers: Array[MeshInstance3D] = []
var _label: Label3D
var _material_hit: StandardMaterial3D
var rig: CharacterRig


static func attach(character_rig: CharacterRig) -> LadderOverlay:
	var overlay := LadderOverlay.new()
	overlay.name = "LadderOverlay"
	overlay.rig = character_rig
	overlay.top_level = true
	character_rig.add_child(overlay)
	overlay._build()
	return overlay


func _build() -> void:
	_material_hit = _flat(Color(1.0, 0.1, 0.1))
	for i in MARKER_LIMIT:
		_markers.append(_sphere(0.007, _material_hit))
	for i in 2:
		_knee_markers.append(_sphere(0.03, _flat(Color(1.0, 0.9, 0.1))))
		_target_markers.append(_sphere(0.025, _flat(Color(1.0, 0.55, 0.1))))
	_pelvis_marker = _sphere(0.04, _flat(Color(0.2, 1.0, 0.3)))
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.no_depth_test = true
	_label.fixed_size = true
	_label.pixel_size = 0.0007
	_label.font_size = 28
	_label.outline_size = 8
	_label.modulate = Color(1.0, 0.85, 0.85)
	_label.visible = false
	add_child(_label)


func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	return material


func _sphere(radius: float, material: Material) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	marker.mesh = mesh
	marker.material_override = material
	marker.visible = false
	add_child(marker)
	return marker


## Draws the last sample of `clearance` for the ladder `geometry` at floor level `climbed`.
func show_sample(clearance: LadderClearance, geometry: LadderGeometry, climbed: float, foot_targets_local: Array[Vector3]) -> void:
	if clearance.joints.is_empty():
		return
	var found := clearance.offenders(geometry, climbed, THRESHOLD, MARKER_LIMIT)
	for i in MARKER_LIMIT:
		_markers[i].visible = i < found.size()
		if i < found.size():
			_markers[i].global_position = rig.character_root.to_global(found[i].point)
	for side in 2:
		_knee_markers[side].visible = true
		_knee_markers[side].global_position = rig.character_root.to_global(clearance.joints.knee[side])
		_target_markers[side].visible = side < foot_targets_local.size()
		if side < foot_targets_local.size():
			_target_markers[side].global_position = rig.character_root.to_global(foot_targets_local[side])
	_pelvis_marker.visible = true
	_pelvis_marker.global_position = rig.character_root.to_global(clearance.joints.hips)
	if found.is_empty():
		_label.visible = false
	else:
		_label.visible = true
		_label.global_position = rig.character_root.to_global((found[0].point as Vector3) + Vector3(0.0, 0.0, 0.0)) + Vector3(0.25, 0.1, 0.0)
		_label.text = "%s\n%s  %.0f mm\n%d vertices inside" % [found[0].bone, found[0].bar, float(found[0].depth) * 1000.0, found.size()]


func shutdown() -> void:
	queue_free()
