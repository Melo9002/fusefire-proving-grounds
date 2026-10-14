class_name TacticalVisualOccluder
extends Node3D

## Explicit opt-in for visual-only scenery that physics camera rays cannot hit.
## Bounds include child transforms and are local to this presentation wrapper.
var occlusion_bounds := AABB()
var _original_transparency: Dictionary = {}

func _ready() -> void:
	add_to_group("tactical_visual_occluders")
	for geometry in find_children("*", "GeometryInstance3D", true, false):
		_original_transparency[geometry] = geometry.transparency

func update_view(camera_position: Vector3, focuses: Array[Vector3]) -> void:
	# Generated walls may attach their meshes after entering the scene tree.
	if _original_transparency.is_empty():
		for geometry in find_children("*", "GeometryInstance3D", true, false):
			_original_transparency[geometry] = geometry.transparency
	var obscures := false
	for focus in focuses:
		if occlusion_bounds.intersects_segment(to_local(camera_position), to_local(focus)) != null:
			obscures = true
			break
	for geometry in _original_transparency:
		if is_instance_valid(geometry):
			geometry.transparency = maxf(_original_transparency[geometry], 0.82) if obscures else _original_transparency[geometry]

func restore_view() -> void:
	update_view(Vector3.ZERO, [])
