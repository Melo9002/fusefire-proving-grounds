class_name WarehouseRoofCutaway
extends Node3D

## Presentation only: the layout owns roof walkability and ceiling LOS.
## Bounds are in this node's local space. The camera supplies its existing
## selected-unit/cinematic-target focuses; no second selection authority.
var interior_bounds := AABB()
var roof_bounds := AABB()
var surface_height := INF

func _ready() -> void:
	add_to_group("tactical_roof_cutaways")

func update_view(camera_position: Vector3, focuses: Array[Vector3]) -> void:
	var local_camera := to_local(camera_position)
	# A rooftop subject takes precedence over indoor cutaway. Visibility does
	# not remove the floor collider or change the authoritative roof/slab cells.
	for focus in focuses:
		var point := to_local(focus)
		if point.y >= surface_height and point.x >= interior_bounds.position.x and point.x < interior_bounds.end.x and point.z >= interior_bounds.position.z and point.z < interior_bounds.end.z:
			visible = true
			return
	var cutaway := interior_bounds.has_point(local_camera)
	for focus in focuses:
		var local_focus := to_local(focus)
		if interior_bounds.has_point(local_focus) or roof_bounds.intersects_segment(local_camera, local_focus) != null:
			cutaway = true
			break
	visible = not cutaway

func restore_view() -> void:
	visible = true
