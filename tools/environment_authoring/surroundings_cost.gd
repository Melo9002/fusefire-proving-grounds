extends SceneTree
## Explicit graphics benchmark, never part of ordinary regression timing gates.
## -- <output-directory>. Keep the window visible and other GPU work idle.
const BattleScene = preload("res://levels/prototype_map/prototype_map.tscn")
const Fingerprint = preload("res://systems/replay/battle_state_fingerprint.gd")
const WARMUP := 120
const SAMPLES := 600
const REPEATS := 3
var records: Array = []
var loads: Array = []
var failures := 0
var output := ""

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or DisplayServer.get_name() == "headless":
		push_error("Requires a graphics run: --script res://tools/environment_authoring/surroundings_cost.gd -- artifacts/surroundings-cost")
		quit(1)
		return
	output = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	root.size = Vector2i(1600, 900)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	var metadata := {"engine": Engine.get_version_info(), "os": OS.get_name(), "cpu": OS.get_processor_name(),
		"memory": OS.get_memory_info(), "gpu": RenderingServer.get_video_adapter_name(),
		"gpu_vendor": RenderingServer.get_video_adapter_vendor(), "graphics_api": RenderingServer.get_video_adapter_api_version(),
		"renderer": ProjectSettings.get_setting("rendering/renderer/rendering_method", "gl_compatibility"),
		"resolution": [1600, 900], "vsync": DisplayServer.window_get_vsync_mode(), "max_fps": Engine.max_fps,
		"warmup_frames_per_block": WARMUP, "sample_frames_per_block": SAMPLES, "repeats": REPEATS,
		"notes": "Debug executable, same battle with Peripheral/Distant visibility toggled; full content stays allocated. Initial resource load occurs before script start due to preloads. No cold-disk or exported-build claim."}
	for map_seed in [16, 17]:
		await _case(map_seed)
	var report := {"setup": metadata, "loading": loads, "frames": records, "failures": failures}
	var file := FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	if file: file.store_string(JSON.stringify(report, "\t"))
	else: failures += 1
	print("Surroundings cost: %d blocks, %d failure(s); %s" % [records.size(), failures, output])
	quit(1 if failures else 0)

func _case(map_seed: int) -> void:
	var started := Time.get_ticks_usec()
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.SERVICE_DEPOT)
	config.battle_seed = map_seed
	config.content_manifest = {"population_enabled": true}
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 2)
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	var stages: Array = []
	level.battle_initialization_progress.connect(func(stage: String, _progress: float): stages.append({"stage": stage, "elapsed_ms": (Time.get_ticks_usec() - started) / 1000.0}))
	root.add_child(level)
	while not level.battle_initialization_succeeded and level.battle_initialization_errors.is_empty(): await process_frame
	if not level.battle_initialization_succeeded:
		failures += 1
		level.free()
		return
	var ready_ms := (Time.get_ticks_usec() - started) / 1000.0
	await RenderingServer.frame_post_draw
	var first_draw_ms := (Time.get_ticks_usec() - started) / 1000.0
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	# Benchmark static idle scenes; no input/edge scrolling or AI actions.
	level.process_mode = Node.PROCESS_MODE_DISABLED
	var plot := level.get_node("GeneratedTerrain").get_child(0)
	var areas := [plot.get_node("Peripheral"), plot.get_node("Distant")]
	var initial_state := Fingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager)
	var load_record := {"seed": map_seed, "ready_ms": ready_ms, "first_draw_ms": first_draw_ms, "stages": stages,
		"scenery_geometry": _geometry(areas), "scenery_construction": _construction(map_seed), "generation_ms": []}
	# Generation has no scenery toggle: scenery is presentation, not tactical data.
	for repeat in REPEATS:
		var tick := Time.get_ticks_usec()
		var data := BattlefieldCatalog.generate(BattlefieldCatalog.SERVICE_DEPOT, Vector2i.ZERO, map_seed, 1.0, {"population_enabled": true})
		load_record.generation_ms.append((Time.get_ticks_usec() - tick) / 1000.0)
		if not data.generation_errors.is_empty(): failures += 1
	loads.append(load_record)
	var views := [
		["normal", Vector3(22, 36, 42), Vector3.ZERO, 46.0],
		["low", Vector3(0, 4, 32), Vector3(0, 2, -8), 46.0],
		["high_wide", Vector3(0, 115, 5), Vector3.ZERO, 86.0]]
	for view in views:
		rig.camera.global_position = view[1]
		rig.camera.look_at(view[2])
		rig.camera.fov = view[3]
		for repeat in REPEATS:
			# Reverse order each repeat to reduce one-sided warmup/drift bias.
			for enabled in ([false, true] if repeat % 2 == 0 else [true, false]):
				for area: Node3D in areas: area.visible = enabled
				await _measure(map_seed, view[0], repeat, enabled)
				if repeat == 0:
					var name := "%d-%s-%s.png" % [map_seed, view[0], "on" if enabled else "off"]
					if root.get_texture().get_image().save_png(output.path_join(name)) != OK: failures += 1
	if Fingerprint.capture(level.turn_manager, level.battle_controller.grid_manager, level.objective_manager) != initial_state: failures += 1
	level.free()
	await process_frame

func _measure(map_seed: int, view: String, repeat: int, enabled: bool) -> void:
	for frame in WARMUP: await RenderingServer.frame_post_draw
	var rows := []
	var last := Time.get_ticks_usec()
	for frame in SAMPLES:
		await RenderingServer.frame_post_draw
		var now := Time.get_ticks_usec()
		rows.append({"frame_ms": (now - last) / 1000.0,
			"render_cpu_ms": RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
			"render_gpu_ms": RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
			"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
			"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
			"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
			"video_memory_bytes": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)})
		last = now
	var record := {"seed": map_seed, "view": view, "repeat": repeat, "scenery_enabled": enabled,
		"window_focused": DisplayServer.window_is_focused(), "samples": rows}
	records.append(record)
	print("[Cost] seed %d %s repeat %d scenery %s" % [map_seed, view, repeat, enabled])

func _geometry(areas: Array) -> Dictionary:
	var meshes := 0
	var triangles := 0
	for area: Node in areas:
		for mesh: MeshInstance3D in area.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null: continue
			meshes += 1
			for index in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(index)
				var indices: int = arrays[Mesh.ARRAY_INDEX].size() if arrays[Mesh.ARRAY_INDEX] != null else 0
				triangles += int((indices if indices > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3.0)
	return {"meshes": meshes, "triangles": triangles}

func _construction(map_seed: int) -> Array:
	# Isolated warm-cache plot instantiation, not a second generator or a runtime flag.
	# Pack equivalent plot copies with/without scenery to measure its construction cost.
	var results := []
	for enabled in [false, true]:
		var definition: Dictionary = Generation2.DepotPlots.choose(map_seed)
		var copy := (definition.scene as PackedScene).instantiate()
		# Only measure plot scenery, not the populated Tactical subtree.
		for child in copy.get_node("Tactical").get_children(): child.free()
		if not enabled:
			copy.get_node("Peripheral").free()
			copy.get_node("Distant").free()
		var packed := PackedScene.new()
		if packed.pack(copy) != OK: failures += 1
		copy.free()
		for repeat in 5:
			var tick := Time.get_ticks_usec()
			var instance := packed.instantiate()
			var elapsed := (Time.get_ticks_usec() - tick) / 1000.0
			results.append({"scenery_enabled": enabled, "ms": elapsed})
			instance.free()
	return results
