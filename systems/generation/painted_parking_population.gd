extends RefCounted
## Exported paint carries reviewed bay geometry. Only a resolved battle choice
## creates a vehicle node and its authored tactical volume.

const Vehicles := preload("res://systems/generation/parking_vehicle_templates.gd")
const Region := preload("res://systems/generation/parcel_population_region.gd")
const BAYS := &"painted_parking_bays"

static func regions(root: Node) -> Array:
	var result: Array = []
	if not root.has_meta(BAYS): return result
	var assets := Vehicles.new().asset_ids()
	for bay: Dictionary in root.get_meta(BAYS):
		var region := Region.new()
		region.region_id = StringName(bay.id)
		region.role = &"parked_vehicle"
		region.surface_id = StringName(bay.surface)
		region.local_rect = bay.rect
		region.allowed_asset_ids = assets
		region.max_count = 1
		result.append(region)
	return result

static func sockets(root: Node) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not root.has_meta(BAYS) or root.has_meta("painted_parking_resolved"): return result
	var templates := Vehicles.new()
	var assets := templates.asset_ids()
	if assets.is_empty(): return result
	for bay: Dictionary in root.get_meta(BAYS):
		var socket := templates.candidate_for_asset(bay, assets[0])
		for asset in assets:
			socket.local_bounds = socket.local_bounds.merge(templates.candidate_for_asset(bay, asset).local_bounds)
		socket.erase("template")
		socket.region_id = socket.socket_id
		socket.asset_options = assets
		result.append(socket)
	return result

static func apply(root: Node, accepted: Dictionary) -> void:
	if not root.has_meta(BAYS): return
	root.set_meta("painted_parking_resolved", true)
	var templates := Vehicles.new()
	for bay: Dictionary in root.get_meta(BAYS):
		var id := StringName(bay.id)
		if not accepted.has(id): continue
		var choice: Dictionary = accepted[id]
		var candidate := templates.candidate_for_asset(bay, String(choice.asset_id))
		if candidate.is_empty(): continue
		var name := "Car_" + String(id)
		var car := root.get_node_or_null(NodePath(name)) as Node3D
		if car and String(car.get_meta("asset_id", "")) != candidate.asset_id:
			car.free()
			car = null
		if not car:
			car = candidate.template.duplicate()
			car.name = name
			car.set_meta("population_socket_id", id)
			car.set_meta("population_region_id", id)
			car.set_meta("population_surface_id", candidate.surface_id)
			car.set_meta("population_yaw_turns", candidate.allowed_yaw_turns)
			root.add_child(car)
		car.position = candidate.local_position
		car.rotation.y = -(int(candidate.heading) + int(choice.get("yaw_turns", 0))) * PI * 0.5
		car.show()
