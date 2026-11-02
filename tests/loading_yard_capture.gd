extends SceneTree
## Manual rendered inspection: run without --headless and pass an output directory after --.

const Catalog = preload("res://systems/generation/battlefield_catalog.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(Catalog.LOADING_YARD)
	config.map_size = Vector2i(40, 48)
	config.battle_seed = 17
	var battle := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	battle.configure_battle(config)
	root.add_child(battle)
	await process_frame
	await process_frame
	if not battle.battle_initialization_succeeded:
		quit(1)
		return
	var rig := battle.get_node("CameraRig") as TacticalCamera
	rig._cancel_selection_focus()
	rig.set_process(false)
	battle.get_node("Visualizers/BattleUI").hide()
	battle.get_node("Visualizers/GridVisualizer").hide()
	battle.get_node("Systems/MouseRaycaster/FloorSelectionHint").hide()
	var camera := Camera3D.new()
	battle.add_child(camera)
	camera.current = true
	camera.fov = 45
	for view in [
		["overhead", Vector3(0.01, 48, 0.01), Vector3.ZERO],
		["oblique", Vector3(28, 24, 30), Vector3(0, 1, 0)],
		["service", Vector3(0, 8, 28), Vector3(0, 1, 6)],
	]:
		camera.position = view[1]
		camera.look_at(view[2])
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("loading-yard-%s.png" % view[0]))
		if error != OK:
			push_error("Capture failed: %s" % error)
			quit(1)
			return
	print("Loading Yard captures saved to " + output)
	quit()
