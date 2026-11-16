class_name TacticalVisualOccluder
extends Node3D

## Explicit opt-in for visual-only scenery that physics camera rays cannot hit.
## Bounds include child transforms and are local to this presentation wrapper.
var occlusion_bounds := AABB()
var _original_transparency: Dictionary = {}

func _ready() -> void:
	add_to_group("tactical_visual_occluders")
	_cache_geometry()

func _cache_geometry() -> void:
	# Runtime helpers can supply bounds directly. Saved scene instances do not
	# serialize this cache, so derive missing bounds from their actual meshes.
	var derive_bounds := occlusion_bounds.size == Vector3.ZERO
	var found_bounds := false
	for geometry in find_children("*", "GeometryInstance3D", true, false):
		_original_transparency[geometry] = geometry.transparency
		if derive_bounds and geometry is MeshInstance3D and geometry.mesh:
			var local_transform: Transform3D = global_transform.affine_inverse() * geometry.global_transform
			var bounds: AABB = local_transform * geometry.get_aabb()
			occlusion_bounds = occlusion_bounds.merge(bounds) if found_bounds else bounds
			found_bounds = true

func update_view(camera_position: Vector3, focuses: Array[Vector3], fade_aperture_meshes := true, active_apertures: Dictionary = {}) -> void:
	# Generated walls may attach their meshes after entering the scene tree.
	if _original_transparency.is_empty():
		_cache_geometry()
	var obscures := false
	for focus in focuses:
		if occlusion_bounds.intersects_segment(to_local(camera_position), to_local(focus)) != null:
			obscures = true
			break
	for geometry in _original_transparency:
		if is_instance_valid(geometry):
			var fade := obscures and not active_apertures.has(geometry) and (fade_aperture_meshes or not geometry is TacticalCameraAperture)
			geometry.transparency = maxf(_original_transparency[geometry], 0.82) if fade else _original_transparency[geometry]

func restore_view() -> void:
	update_view(Vector3.ZERO, [])
