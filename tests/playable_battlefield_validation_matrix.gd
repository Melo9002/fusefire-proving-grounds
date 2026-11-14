extends SceneTree
## Explicit bounded integration/visual audit, not exhaustive mission certification.
const Catalog = preload("res://systems/generation/battlefield_catalog.gd")
var failures := 0
var results: Array[Dictionary] = []
func _initialize() -> void:
	_run.call_deferred()
func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var capture := OS.get_cmdline_user_args().has("capture")
	if capture and DisplayServer.get_name() == "headless":
		push_error("Captures require a renderer")
		quit(1)
		return
	for id in Catalog.PLAYABLE:
		for map_seed in [16, 17]:
			var populations: Array = [false, true] if Catalog.uses_population(id) else [false]
			for population in populations:
				var config := BattleConfiguration.new()
				config.generated_map = true
				config.select_battlefield(id)
				config.battle_seed = map_seed
				config.player_count = 2
				config.enemy_count = 2
				config.content_manifest = {"population_enabled": population}
				config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2, false)
				var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
				level.configure_battle(config)
				var start := Time.get_ticks_msec()
				root.add_child(level)
				await process_frame
				await process_frame
				var context := "%s seed %d population %s" % [id, map_seed, population]
				check(level.battle_initialization_succeeded, context + " initializes: " + str(level.battle_initialization_errors))
				var entry := {"battlefield": String(id), "seed": map_seed, "population": population, "initialization_ms": Time.get_ticks_msec() - start, "initialized": level.battle_initialization_succeeded}
				if level.battle_initialization_succeeded:
					level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
					var battle := level.battle_controller
					battle.set_process(false)
					var data := battle.grid_manager.map_data
					check(battle.last_map_validation.is_valid(), context + " passes authoritative tactical validation")
					check(level.turn_manager.player_units.size() == 2 and level.turn_manager.enemy_units.size() == 2, context + " deploys both squads")
					for unit in level.turn_manager.player_units + level.turn_manager.enemy_units:
						var cell := data.get_cell(battle.grid_manager.get_unit_grid(unit))
						check(cell != null and cell.walkable and cell.can_stop, context + " deployment is legal for " + String(unit.name))
					var restored := Catalog.generate(id, data.map_size, map_seed, 1, data.content_manifest)
					check(restored.generation_errors.is_empty() and _geometry(restored) == _geometry(data), context + " reconstructs accepted tactical geometry")
					check(StringName(level._replay_configuration.battlefield_id) == id, context + " records correct replay identity")
					entry["compiler_revision"] = data.content_manifest.get("compiler_revision", 0)
					entry["cells"] = data.cells.size()
					entry["quality_score"] = battle.last_map_quality.overall_score if battle.last_map_quality else -1
					if capture and map_seed == 17 and (population or not Catalog.uses_population(id)):
						await _capture(level, String(id))
				results.append(entry)
				print("Map matrix: ", context, " initialized=", entry.initialized, " ", entry.initialization_ms, " ms")
				level.queue_free()
				await process_frame
	var file := FileAccess.open("res://artifacts/playable-map-validation.json", FileAccess.WRITE)
	check(file != null, "Validation report destination is writable")
	if file: file.store_string(JSON.stringify({"cases": results, "failures": failures}, "\t"))
	print("Playable map matrix: %d case(s), %d failure(s)" % [results.size(), failures])
	quit(1 if failures else 0)

func _geometry(data: MapData) -> String:
	var cells: Array = data.cells.keys()
	cells.sort_custom(func(a: Vector3i, b: Vector3i): return [a.x, a.y, a.z] < [b.x, b.y, b.z])
	var lines := PackedStringArray()
	for key: Vector3i in cells:
		var cell := data.get_cell(key)
		lines.append(str([key, cell.world_position, cell.walkable, cell.can_stop, cell.cover_type, cell.cover_height, cell.blocks_line_of_sight, cell.movement_cost, cell.authored_shot_bounds, cell.authored_shot_parts]))
	return "\n".join(lines).sha256_text()

func _capture(level: BattleLevel, id: String) -> void:
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	var size := level.battle_controller.grid_manager.map_data.map_size
	var span := float(maxi(size.x, size.y))
	for overhead in [false, true]:
		rig.camera.global_position = Vector3(span * 0.55, span * 0.85, span * 0.65) if not overhead else Vector3(0.01, span * 1.25, 0.01)
		rig.camera.look_at(Vector3.ZERO)
		rig.camera.fov = 55
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png("res://artifacts/map-%s-%s.png" % [id, "overhead" if overhead else "oblique"]) == OK, "Capture saved for " + id)
