extends SceneTree

const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
const Parcels = preload("res://systems/generation/authored_parcel_catalog.gd")
const Recording = preload("res://systems/replay/battle_replay_recording.gd")
const FRONT := Vector3i(8, 0, 7)
const SIDE := Vector3i(27, 0, 24)
const UPPER_AISLE := Vector3i(16, 4, 19)
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _generate(map_seed: int, manifest: Dictionary = {}) -> MapData:
	return Catalog.generate(Catalog.PARKING_GARAGE, Vector2i.ONE, map_seed, 1.0, manifest)

func _run() -> void:
	var parcel = Parcels.get_definition(Parcels.PARKING_GARAGE_A)
	var authored: Node3D = parcel.instantiate()
	var sockets: Array[Dictionary] = parcel.population_sockets()
	check(sockets.size() == 16, "Four authored rows have four bays each")
	var aisle := AABB(Vector3(5, 0, 16), Vector3(21, 8, 6))
	var obstacles: Array[AABB] = parcel.fixed_population_obstacles(authored)
	for socket in sockets:
		var bounds: AABB = socket.local_bounds
		var peer_collision := sockets.any(func(peer): return peer.socket_id != socket.socket_id and bounds.intersects(peer.local_bounds))
		check(not peer_collision and not bounds.intersects(aisle), "Bay %s leaves its peers and cross aisle clear" % socket.socket_id)
		check(not obstacles.any(func(obstacle): return bounds.intersects(obstacle)), "Bay %s clears fixed columns and parapets" % socket.socket_id)
	var measured_cars := 0
	for occupant in authored.find_children("*Bay?", "Node3D", true, false):
		if not occupant.has_meta("population_socket_id"):
			continue
		measured_cars += 1
		var car := occupant as Node3D
		var visual := _mesh_bounds(car.get_node("Visual"), car.transform)
		var floor_height := car.position.y
		check(absf(visual.position.y - floor_height) < 0.06 and visual.end.y < floor_height + 2.5, "%s rests on its authored floor with headroom: %s" % [car.name, visual])
		check(visual.size.x < 2.9 and visual.size.z < 5.5, "%s physically fits between the bay stripes in either heading: %s" % [car.name, visual])
	check(measured_cars == sockets.size(), "The imported geometry check covers every authored bay")
	authored.free()
	var prior: Array = []
	for map_seed in [16, 17, 18, 19]:
		var data := _generate(map_seed)
		check(data.generation_errors.is_empty(), "Garage seed %d resolves: %s" % [map_seed, data.generation_errors])
		if not data.generation_errors.is_empty():
			continue
		check(data.map_size == Vector2i(32, 32) and data.get_cell(Vector3i(16, 0, 32)) == null, "Ramp and surroundings do not extend the tactical map")
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		check(MapValidator.validate(data, graph).is_valid(), "Seed %d has valid connected deployments" % map_seed)
		check(data.traversal_links.size() == 2, "Garage has two explicit climbs")
		for bottom in [FRONT, SIDE]:
			check(not graph.calculate_3d_path(bottom, UPPER_AISLE).is_empty(), "Climb %s reaches the upper aisle" % bottom)
		var choices: Array = data.content_manifest.placements[0].population
		check(choices.any(func(choice): return String(choice.region_id).begins_with("upper_")), "Upper deck gets cars")
		check(choices.any(func(choice): return String(choice.region_id).begins_with("ground_")), "Ground floor gets cars")
		check(choices == _generate(map_seed).content_manifest.placements[0].population, "Same seed reproduces exact bay and heading choices")
		if map_seed == 16:
			prior = choices
		if map_seed == 18:
			check(prior != choices, "Different seeds vary the selected bays")
		for choice: Dictionary in choices:
			var index := sockets.find_custom(func(socket): return socket.socket_id == choice.socket_id)
			var cell := data.get_cell(Vector3i(sockets[index].local_position))
			check(cell != null and not cell.can_stop and cell.blocks_line_of_sight, "Selected bay %s compiles tactical occupancy on its own floor" % choice.socket_id)

	var empty := _generate(17, {"population_enabled": false})
	check(empty.generation_errors.is_empty() and empty.content_manifest.placements[0].population.is_empty(), "Population-off preserves the garage without cars")
	for socket in sockets:
		var cell := empty.get_cell(Vector3i(socket.local_position))
		check(cell != null and cell.can_stop, "Empty bay %s retains its stopping surface" % socket.socket_id)
	var links := empty.traversal_links.duplicate()
	for link in links:
		empty.traversal_links.assign([link])
		var graph := Pathfinder.new()
		MapGraphBuilder.build(empty, graph)
		check(not graph.calculate_3d_path(link.from_cell, UPPER_AISLE).is_empty(), "Climb %s works with the other climb removed" % link.from_cell)
		check(not graph.calculate_3d_path(UPPER_AISLE, link.from_cell).is_empty(), "Climb %s works downhill" % link.from_cell)
	empty.traversal_links.clear()
	var disconnected := Pathfinder.new()
	MapGraphBuilder.build(empty, disconnected)
	check(disconnected.calculate_3d_path(FRONT, UPPER_AISLE).is_empty(), "No implicit floor jump replaces an authored climb")

	var original := _generate(17)
	var recording := Recording.new()
	recording.configuration = {"content_manifest": original.content_manifest}
	var restored := Recording.from_dictionary(recording.to_dictionary())
	var reconstructed := _generate(999, restored.configuration.content_manifest)
	check(reconstructed.content_manifest == original.content_manifest, "Replay restores the original plot, seed, parcel, bays and car headings")
	check(reconstructed.generation_errors.is_empty(), "Replay compiles the recorded garage")
	var stale := original.content_manifest.duplicate(true)
	stale.plot_revision += 1
	check(_generate(17, stale).generation_errors.any(func(error): return error.code == "STALE_PLOT_REVISION"), "Stale garage plot fails explicitly")
	var stage := Node3D.new()
	root.add_child(stage)
	check(Catalog.present_special(reconstructed, stage, 1.0), "Battlefield presenter reconstructs the garage")
	var ramp := stage.find_child("ServiceRamp", true, false) as MeshInstance3D
	var slab := stage.find_child("ConcreteSlab", true, false) as MeshInstance3D
	var approach := stage.find_child("EntranceDrive", true, false) as MeshInstance3D
	var asphalt := stage.find_child("Asphalt", true, false) as MeshInstance3D
	if ramp and slab and approach and asphalt:
		var ramp_top := ramp.to_global(Vector3(0, ramp.get_aabb().end.y, ramp.get_aabb().position.z))
		var slab_edge := slab.to_global(Vector3(0, slab.get_aabb().end.y, slab.get_aabb().end.z))
		check(ramp_top.distance_to(slab_edge) < 0.002, "Scenery ramp meets deck top and boundary: %s vs %s" % [ramp_top, slab_edge])
		var approach_edge := approach.to_global(Vector3(0, approach.get_aabb().end.y, approach.get_aabb().end.z))
		var asphalt_edge := asphalt.to_global(Vector3(0, asphalt.get_aabb().end.y, asphalt.get_aabb().position.z))
		check(approach_edge.distance_to(asphalt_edge) < 0.002, "Driveway meets the authored approach height and boundary: %s vs %s" % [approach_edge, asphalt_edge])
	else:
		check(false, "Presented garage contains both measured scenery seams")
	var deck := stage.find_child("UpperDeck", true, false) as WarehouseRoofCutaway
	check(deck != null, "Presentation registers the upper slab and upper cars as one cutaway")
	if deck:
		deck.update_view(Vector3(0, 22, 18), [deck.to_global(Vector3(16, 1, 19))])
		check(not deck.visible and original.get_cell(UPPER_AISLE).can_stop, "Ground-floor camera focus hides only the upper visuals")
		deck.update_view(Vector3(0, 22, 18), [deck.to_global(Vector3(16, 4, 19))])
		check(deck.visible, "Upper-floor camera focus restores the upper visuals")
	stage.free()
	print("Parking garage: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _mesh_bounds(node: Node, parent_transform: Transform3D) -> AABB:
	var transform: Transform3D = parent_transform * node.transform if node is Node3D else parent_transform
	var bounds: AABB = transform * node.get_aabb() if node is MeshInstance3D else AABB()
	for child in node.get_children():
		var child_bounds := _mesh_bounds(child, transform)
		if child_bounds.has_volume():
			bounds = bounds.merge(child_bounds) if bounds.has_volume() else child_bounds
	return bounds
