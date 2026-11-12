extends RefCounted
## Save reviewed painted placements for seeded battle population. The editor owns the
## export, while the registered parcel contract owns compilation and replay.
const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
const Compiler = preload("res://systems/generation/authored_scene_map_compiler.gd")
const Containers = preload("res://tools/parcel_editor/container_field_placements.gd")

static func build(source, draft, vehicles, fixed_draft = null) -> Dictionary:
	if source == null or draft.parcel_id != String(source.parcel_id) or draft.revision != source.revision:
		return {"error": "Draft source parcel revision no longer matches."}
	var source_errors: PackedStringArray = source.validate()
	if not source_errors.is_empty():
		return {"error": "Source parcel contract failed: %s" % "; ".join(source_errors)}
	var scene_root: Node3D = source.instantiate()
	var fixed_changed: bool = fixed_draft != null and fixed_draft.placements != fixed_draft.base_placements
	if fixed_changed:
		if fixed_draft.parcel_id != source.parcel_id or fixed_draft.parcel_revision != source.revision:
			scene_root.free()
			return {"error": "Fixed-object draft source revision no longer matches."}
		var failures: PackedStringArray = fixed_draft.apply(scene_root)
		if not failures.is_empty():
			scene_root.free()
			return {"error": " ".join(failures)}
		var copy: Node3D = fixed_draft.preview_root(scene_root)
		scene_root.free()
		scene_root = copy
		for child in scene_root.get_children():
			if child.has_meta("draft_added"):
				_own_added_nodes(child, scene_root)
				child.remove_meta("draft_added")
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
	var has_parking: bool = draft.fields.any(func(field): return field.preset == "parking")
	var has_containers: bool = draft.fields.any(func(field): return field.preset == "containers")
	if has_parking and has_containers:
		scene_root.free()
		return {"error": "Export one population type at a time. Save the field draft before separating the paint."}
	var obstacles: Array[AABB] = draft.parking_obstacles(source, scene_root)
	var bays: Array[Dictionary] = draft.parking_bays(sockets, obstacles, {}, true)
	if has_parking and bays.is_empty():
		scene_root.free()
		return {"error": "No parking bays fit. Expand the parking paint or adjust the aisle."}
	if has_parking and vehicles.asset_ids().is_empty():
		scene_root.free()
		return {"error": "No calibrated vehicle fits the authored bay dimensions."}
	var rules: Array[Dictionary] = []
	rules.assign(scene_root.get_meta("painted_parking_bays", []))
	var paint: Array = scene_root.get_meta("parking_population_paint", []).duplicate(true)
	for field in draft.fields:
		if field.preset in ["parking", "protected"]:
			paint.append({"surface": field.surface, "preset": field.preset, "rect": Session.rectangle(field)})
	for bay in bays:
		if not bay.reason.is_empty():
			scene_root.free()
			return {"error": "%s: %s. Adjust the draft before exporting." % [bay.id, bay.reason]}
		rules.append({"id": bay.id, "surface": bay.surface, "level": bay.level, "heading": bay.heading, "rect": bay.rect, "aisle": bay.aisle})
	if not bays.is_empty():
		scene_root.set_meta("painted_parking_bays", rules)
		scene_root.set_meta("parking_population_paint", paint)
	var container_slots: Array[Dictionary] = []
	if has_containers:
		var template := Containers.Library.create(Containers.ASSET)
		container_slots = Containers.candidates(draft, source, scene_root, sockets, obstacles, template)
		for candidate in container_slots:
			Containers.add_to_scene(scene_root, template, candidate)
		template.free()
	if bays.is_empty() and container_slots.is_empty() and not fixed_changed:
		scene_root.free()
		return {"error": "No new positions fit. Ground containers need a clear 3 × 5 area away from existing occupants and the entrance."}
	if not container_slots.is_empty():
		var container_paint: Array = scene_root.get_meta("container_population_paint", []).duplicate(true)
		for field in draft.fields:
			if field.surface == "ground" and field.preset in ["containers", "protected"]:
				container_paint.append({"surface": field.surface, "preset": field.preset, "rect": Session.rectangle(field)})
		scene_root.set_meta("container_population_paint", container_paint)
	var signature := [String(source.parcel_id), source.revision, rules, paint, container_slots, scene_root.get_meta("container_population_paint", [])]
	if fixed_changed:
		signature.append(fixed_draft.placements)
	var parcel_id := StringName("%s_rules_%s" % [source.parcel_id, JSON.stringify(signature).sha256_text().substr(0, 16)])
	scene_root.set_meta("parcel_id", parcel_id)
	scene_root.set_meta("revision", 1)
	var packed := PackedScene.new()
	var pack_error := packed.pack(scene_root)
	scene_root.free()
	if pack_error != OK:
		return {"error": "Could not pack the authored scene: %s" % error_string(pack_error)}
	var definition := AuthoredParcelDefinition.new(parcel_id, source.display_name + " — population rules", source.role, 1, source.size, packed)
	var failures := definition.validate()
	if not failures.is_empty():
		return {"error": "Exported parcel contract failed: %s" % "; ".join(failures)}
	var route_error := _check_aisles(definition, rules, not container_slots.is_empty() or fixed_changed)
	if not route_error.is_empty():
		return {"error": route_error}
	return {"definition": definition, "bay_count": bays.size(), "container_count": container_slots.size()}

static func _own_added_nodes(node: Node, root: Node) -> void:
	node.owner = root
	if not node.scene_file_path.is_empty():
		return
	for child in node.get_children():
		_own_added_nodes(child, root)

static func _check_aisles(definition: AuthoredParcelDefinition, bays: Array[Dictionary], check_ground := false) -> String:
	# Compile the fully occupied version. Check the entire aisle and a path
	# from the authored entrance in every supported parcel rotation.
	var aisles := {}
	for bay in bays:
		if bay.has("aisle"):
			aisles["%s/%s" % [bay.level, bay.aisle]] = {"rect": bay.aisle, "level": bay.level}
	var entrance := definition.connection()
	var full_population := []
	for socket in definition.population_sockets():
		# The SUV has the same tactical footprint as the sedan and taxi, and
		# the tallest tactical volume. Reserve it for the worst-case check.
		var asset := "car_kit/suv" if "car_kit/suv" in socket.get("asset_options", []) else String(socket.asset_id)
		full_population.append({"socket_id": socket.socket_id, "asset_id": asset})
	for turn in definition.allowed_rotations():
		var extent := ParcelTransform.rotated_size(definition.size, turn)
		var map := FlatMapGenerator.generate(extent.x, extent.y, 1.0, 0)
		var instance := definition.instantiate()
		definition.apply_population(instance, full_population)
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
		if check_ground:
			var reachable := {}
			for position in graph.get_reachable_cells(start, extent.x * extent.y * 10):
				reachable[position] = true
			for z in extent.y:
				for x in extent.x:
					var position := Vector3i(x, 0, z)
					var cell := map.get_cell(position)
					if cell and cell.walkable and cell.can_stop and position != start and not reachable.has(position):
						return "Occupied export disconnects ground cell %s at rotation %d." % [position, turn]
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
