extends SceneTree
## Read-only rendered review. Run with -- <output-directory>; no live editor is used.
var failures := 0
var records: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		push_error("Use a graphics run: --script res://tools/environment_authoring/current_surroundings_capture.gd -- artifacts/surroundings-review")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	for id in BattlefieldCatalog.PLAYABLE:
		for map_seed in [16, 17]:
			var config := BattleConfiguration.new()
			config.generated_map = true
			config.select_battlefield(id)
			config.battle_seed = map_seed
			config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2)
			var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
			level.configure_battle(config)
			root.add_child(level)
			if not level.battle_initialization_succeeded:
				failures += 1
				level.queue_free()
				await process_frame
				continue
			var rig := level.get_node("CameraRig") as TacticalCamera
			rig.set_process(false)
			rig._cancel_selection_focus()
			await _capture(level, rig, args[0], id, map_seed, "entry")
			level.get_node("Visualizers/GridVisualizer").hide()
			level.get_node("Visualizers/GridCursor").hide()
			var views := [
				["overview", Vector3(22, 36, 42), Vector3.ZERO, 46.0],
				["reverse", Vector3(-28, 32, -36), Vector3.ZERO, 46.0],
				["low", Vector3(0, 4, 32), Vector3(0, 2, -8), 46.0],
				["wide", Vector3(38, 48, 58), Vector3.ZERO, 65.0],
			]
			if id == BattlefieldCatalog.SERVICE_DEPOT:
				views.append_array([
					["low_east", Vector3(-32, 4, 0), Vector3(8, 2, 0), 46.0],
					# x=32 sits inside a neighboring workshop; keep this horizon
					# review between that building and the tactical boundary.
					["low_west", Vector3(25, 4, 0), Vector3(-8, 2, 0), 46.0],
					["low_south", Vector3(0, 4, -32), Vector3(0, 2, 8), 46.0],
					["high", Vector3(0, 55, 4), Vector3.ZERO, 46.0],
					["high_wide", Vector3(0, 115, 5), Vector3.ZERO, 86.0],
				])
			for view in views:
				rig.camera.global_position = view[1]
				rig.camera.look_at(view[2])
				rig.camera.fov = view[3]
				# Match the existing fade inspection, without panning or changing battle state.
				rig._update_camera_occlusion(0.016)
				await _capture(level, rig, args[0], id, map_seed, view[0])
			level.queue_free()
			await process_frame
			await process_frame
	var file := FileAccess.open(args[0].path_join("views.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(records, "\t"))
	else: failures += 1
	print("Surroundings capture: %d views, %d failure(s)" % [records.size(), failures])
	quit(1 if failures else 0)

func _capture(level: BattleLevel, rig: TacticalCamera, directory: String, id: StringName, map_seed: int, view: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var path := directory.path_join("%s-%d-%s.png" % [id, map_seed, view])
	if root.get_texture().get_image().save_png(path) != OK: failures += 1
	records.append({"site": id, "seed": map_seed, "plot": level.active_generated_map.content_manifest.plot_id, "view": view,
		"camera_transform": var_to_str(rig.camera.global_transform), "fov": rig.camera.fov, "path": path})
