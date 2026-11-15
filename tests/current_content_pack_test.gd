extends SceneTree
const Vehicles = preload("res://systems/generation2/parking_vehicle_templates.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var vehicles := Vehicles.new()
	check(vehicles.asset_ids() == PackedStringArray(["car_kit/sedan", "car_kit/suv", "car_kit/taxi"]), "Historical bays keep their original ordered vehicle set")
	check(vehicles.asset_ids(Vehicles.MIXED) == PackedStringArray(["car_kit/sedan", "car_kit/suv", "car_kit/taxi", "car_kit/ambulance", "car_kit/van"]), "New bays offer both new calibrated service vehicles")
	var historical = AuthoredParcelCatalog.get_definition(AuthoredParcelCatalog.INDUSTRIAL_OFFICE_PARKING_RULES)
	check(historical.population_regions().all(func(region): return not region.allowed_asset_ids.has("car_kit/ambulance") and not region.allowed_asset_ids.has("car_kit/van")), "Historical bay records do not silently widen their allowed asset set")
	check(vehicles.asset_ids("unknown").is_empty(), "Unknown vehicle sets cannot silently select another set")
	for id in [AuthoredParcelCatalog.CONTAINER_STAGING, AuthoredParcelCatalog.FLEET_APRON, AuthoredParcelCatalog.FLEET_COURT]:
		var parcel = AuthoredParcelCatalog.get_definition(id)
		check(parcel != null and parcel.validate().is_empty(), "New parcel is an inspectable valid scene: " + String(id))
		if parcel == null: continue
		var root_node: Node3D = parcel.instantiate()
		var fields := PopulationFieldDraft.new()
		fields.begin(parcel, root_node)
		var source_sockets: Array[Dictionary] = parcel.population_sockets(root_node)
		var obstacles: Array[AABB] = fields.parking_obstacles(parcel, root_node)
		# Placement obstacles also contain the reserved aisles themselves.
		# Aisle clearance must compare against physical fixed geometry only.
		var fixed_solids: Array[AABB] = parcel.fixed_population_obstacles(root_node)
		for aisle in fields.registered_aisles(root_node):
			check(not fixed_solids.any(func(other): return aisle.grow(-0.001).intersects(other)), "Authored parking aisles stay clear of fixed objects: " + String(id))
		for socket in source_sockets:
			for turn in socket.allowed_yaw_turns:
				var bounds := PopulationFieldDraft.socket_bounds_at_turn(socket, turn)
				check(not obstacles.any(func(other): return bounds.grow(-0.001).intersects(other)), "Every potential occupant clears fixed geometry: %s/%s" % [id, socket.socket_id])
		root_node.free()
	var seen_assets := {}
	for id in [BattlefieldCatalog.FREIGHT_YARD, BattlefieldCatalog.FLEET_STATION]:
		var sites := {}
		var arrangements := {}
		var generation_ms: Array[float] = []
		for map_seed in range(16):
			var began := Time.get_ticks_usec()
			var data := BattlefieldCatalog.generate(id, Vector2i.ONE, map_seed, 1)
			generation_ms.append((Time.get_ticks_usec() - began) / 1000.0)
			check(data.generation_errors.is_empty(), "%s seed %d resolves: %s" % [id, map_seed, str(data.generation_errors)])
			if not data.generation_errors.is_empty(): continue
			check(data.map_size == Vector2i(40, 40), "The selected site owns its footprint")
			var graph := Pathfinder.new()
			MapGraphBuilder.build(data, graph)
			check(MapValidator.validate(data, graph, {TacticalUnit.Faction.PLAYER: 5, TacticalUnit.Faction.ENEMY: 5, TacticalUnit.Faction.ALLY: 5}).is_valid(), "%s seed %d supports connected 5/5/5 deployments" % [id, map_seed])
			var again := BattlefieldCatalog.generate(id, Vector2i.ZERO, 999, 1, data.content_manifest)
			check(again.generation_errors.is_empty() and again.content_manifest == data.content_manifest, "Recorded choices reconstruct without depending on the caller's new seed")
			var empty := BattlefieldCatalog.generate(id, Vector2i.ZERO, map_seed, 1, {"population_enabled": false})
			check(empty.generation_errors.is_empty() and empty.content_manifest.placements.all(func(placement): return placement.population.is_empty()), "Population-off keeps the authored site and empty areas")
			sites[data.content_manifest.plot_id] = true
			arrangements[str(data.content_manifest.placements)] = true
			for placement in data.content_manifest.placements:
				for choice in placement.population: seen_assets[choice.asset_id] = true
		print("[ContentTiming] %s average %.1f ms, max %.1f ms" % [id, generation_ms.reduce(func(total, value): return total + value, 0.0) / generation_ms.size(), generation_ms.max()])
		check(sites.size() == 2 and arrangements.size() > 2, "Both layouts and varied occupants are reachable for " + String(id))
	check(seen_assets.has("car_kit/ambulance") and seen_assets.has("car_kit/van"), "Known seed sweep actually spawns both new vehicle types")
	vehicles = null
	await _render_checks()
	print("Current content pack: 32 map seeds, %d failure(s)" % failures)
	quit(1 if failures else 0)

func _render_checks() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(args[1])
	for id in [BattlefieldCatalog.FREIGHT_YARD, BattlefieldCatalog.FLEET_STATION]:
		for map_seed in [16, 17]:
			var config := BattleConfiguration.new()
			config.generated_map = true
			config.battle_seed = map_seed
			config.select_battlefield(id)
			config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2)
			var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
			level.configure_battle(config)
			root.add_child(level)
			check(level.battle_initialization_succeeded, "Rendered site starts a real validated battle")
			var rig := level.get_node("CameraRig") as TacticalCamera
			rig.set_process(false)
			rig._cancel_selection_focus()
			rig.camera.global_position = Vector3(22, 36, 42) if map_seed == 16 else Vector3(-28, 39, 28)
			rig.camera.look_at(Vector3.ZERO)
			rig.camera.fov = 46
			level.get_node("Visualizers/GridVisualizer").hide()
			level.get_node("Visualizers/GridCursor").hide()
			await _image(args[1].path_join("%s-%d.png" % [id, map_seed]))
			level.queue_free()
			await process_frame
	var editor := load("res://tools/parcel_editor/parcel_editor.tscn").instantiate() as ParcelEditor
	root.add_child(editor)
	await process_frame
	for id in [AuthoredParcelCatalog.CONTAINER_STAGING, AuthoredParcelCatalog.FLEET_APRON, AuthoredParcelCatalog.FLEET_COURT]:
		editor.select_parcel(id)
		await _image(args[1].path_join(String(id) + "-guides.png"))
		editor.field_panel.preview()
		check(is_instance_valid(editor.field_panel._runtime_preview), "New content supports the existing editor Preview")
		await _image(args[1].path_join(String(id) + "-preview.png"))
	editor.free()

func _image(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(path) == OK, "Capture " + path.get_file())
