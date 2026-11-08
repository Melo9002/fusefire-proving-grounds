extends RefCounted
## Bake reviewed rows into ordinary authored sockets. This editor tool owns the
## export, while the registered parcel contract owns compilation and replay.
const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
const Compiler = preload("res://systems/generation/authored_scene_map_compiler.gd")

static func build(source, draft, vehicles, map_seed: int) -> Dictionary:
	if source == null or draft.parcel_id != String(source.parcel_id) or draft.revision != source.revision:
		return {"error": "Draft source parcel revision no longer matches."}
	var source_errors: PackedStringArray = source.validate()
	if not source_errors.is_empty():
		return {"error": "Source parcel contract failed: %s" % "; ".join(source_errors)}
	var scene_root: Node3D = source.instantiate()
	var current := Session.new()
	current.begin(source, scene_root)
	if draft.surfaces != current.surfaces:
		scene_root.free()
		return {"error": "Draft surfaces no longer match the authored parcel."}
	var sockets: Array[Dictionary] = source.population_sockets(scene_root)
	for socket in sockets:
		for turn: int in socket.allowed_yaw_turns:
			if draft.has_protected_overlap(String(socket.surface_id), Session.socket_bounds_at_turn(socket, turn)):
				scene_root.free()
				return {"error": "Protected paint intersects original socket %s. The export preserves original sockets." % socket.socket_id}
	var bays: Array[Dictionary] = draft.parking_bays(sockets, draft.parking_obstacles(source, scene_root), {}, true)
	if bays.is_empty():
		scene_root.free()
		return {"error": "No parking bays fit. Expand the parking paint or adjust the aisle."}
	var signature: Array = [String(source.parcel_id), source.revision]
	for bay in bays:
		if not bay.reason.is_empty():
			scene_root.free()
			return {"error": "%s: %s. Adjust the draft before exporting." % [bay.id, bay.reason]}
		var candidate: Dictionary = vehicles.candidate(bay, map_seed, draft.parcel_id)
		if candidate.is_empty():
			scene_root.free()
			return {"error": "No calibrated vehicle fits %s." % bay.id}
		signature.append([bay.id, bay.heading, candidate.asset_id])
		_add_bay(scene_root, bay, candidate)
	var parcel_id := StringName("%s_rows_%s" % [source.parcel_id, JSON.stringify(signature).sha256_text().substr(0, 16)])
	scene_root.set_meta("parcel_id", parcel_id)
	scene_root.set_meta("revision", 1)
	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	scene_root.free()
	if pack_error != OK:
		return {"error": "Could not pack the authored scene: %s" % error_string(pack_error)}
	var definition := AuthoredParcelDefinition.new(parcel_id, source.display_name + " — parking rows", source.role, 1, source.size, packed)
	var failures := definition.validate()
	if not failures.is_empty():
		return {"error": "Exported parcel contract failed: %s" % "; ".join(failures)}
	var route_error := _check_aisles(definition, bays)
	if not route_error.is_empty():
		return {"error": route_error}
	return {"definition": definition, "bay_count": bays.size()}

static func _add_bay(scene_root: Node3D, bay: Dictionary, candidate: Dictionary) -> void:
	var id := StringName(bay.id)
	var region := Node.new()
	region.name = "Region_" + String(id)
	region.set_meta("population_region_id", id)
	region.set_meta("population_role", &"parked_vehicle")
	region.set_meta("population_surface_id", StringName(bay.surface))
	region.set_meta("local_rect", bay.rect)
	region.set_meta("allowed_asset_ids", PackedStringArray([candidate.asset_id]))
	region.set_meta("min_count", 0)
	region.set_meta("max_count", 1)
	scene_root.add_child(region)
	region.owner = scene_root
	var car: Node3D = candidate.template.duplicate()
	car.name = "Car_" + String(id)
	car.position = candidate.local_position
	car.rotation.y = -int(bay.heading) * PI * 0.5
	car.set_meta("population_socket_id", id)
	car.set_meta("population_region_id", id)
	car.set_meta("population_surface_id", StringName(bay.surface))
	car.set_meta("population_yaw_turns", PackedInt32Array([0, 2]))
	scene_root.add_child(car)
	_set_owner(car, scene_root)

static func _set_owner(node: Node, scene_root: Node3D) -> void:
	node.owner = scene_root
	if not node.scene_file_path.is_empty(): return
	for child in node.get_children():
		_set_owner(child, scene_root)

static func _check_aisles(definition: AuthoredParcelDefinition, bays: Array[Dictionary]) -> String:
	# Compile the fully occupied version. Check the entire aisle and a path
	# from the authored entrance in every supported parcel rotation.
	var aisles := {}
	for bay in bays:
		aisles["%s/%s" % [bay.level, bay.aisle]] = {"rect": bay.aisle, "level": bay.level}
	var entrance := definition.connection()
	for turn in definition.allowed_rotations():
		var extent := ParcelTransform.rotated_size(definition.size, turn)
		var map := FlatMapGenerator.generate(extent.x, extent.y, 1.0, 0)
		var instance := definition.instantiate()
		instance.transform = ParcelTransform.scene_transform(definition.size, Vector3i.ZERO, turn, extent)
		Compiler.compile(instance, map, 1.0)
		instance.free()
		var graph := Pathfinder.new()
		MapGraphBuilder.build(map, graph)
		var start := ParcelTransform.cell(entrance.cell, definition.size, Vector3i.ZERO, turn)
		for position in entrance.world_span(definition.size, Vector3i.ZERO, turn):
			var cell := map.get_cell(position)
			if cell == null or not cell.walkable or not cell.can_stop:
				return "Occupied export blocks entrance cell %s at rotation %d." % [position, turn]
		for aisle: Dictionary in aisles.values():
			var rect: Rect2i = aisle.rect
			for x in range(rect.position.x, rect.end.x):
				for z in range(rect.position.y, rect.end.y):
					var position := ParcelTransform.cell(Vector3i(x, aisle.level, z), definition.size, Vector3i.ZERO, turn)
					var cell := map.get_cell(position)
					if cell == null or not cell.walkable or not cell.can_stop:
						return "Occupied export blocks aisle cell %s at rotation %d." % [position, turn]
			var target := ParcelTransform.cell(Vector3i(rect.position.x, aisle.level, rect.position.y), definition.size, Vector3i.ZERO, turn)
			if graph.calculate_3d_path(start, target).is_empty():
				return "No tactical route from entrance to aisle %s at rotation %d." % [rect, turn]
	return ""
