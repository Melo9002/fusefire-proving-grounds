extends SceneTree

# Manual rendered inspection: run without --headless, pass an output directory after --.
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
	config.industrial_warehouse = true
	config.map_size = Vector2i(40, 30)
	config.battle_seed = 940059876
	var battle := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	battle.configure_battle(config)
	root.add_child(battle)
	await process_frame
	await process_frame
	var rig := battle.get_node("CameraRig") as TacticalCamera
	rig._cancel_selection_focus()
	rig.set_process(false)
	battle.get_node("Visualizers/BattleUI").hide()
	battle.get_node("Visualizers/GridVisualizer").hide()
	var floor_ui := battle.get_node("Systems/MouseRaycaster/FloorSelectionHint") as CanvasLayer
	floor_ui.hide()
	# Capture-only scale reference, not a registered combatant or replay action.
	var reference := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as Node3D
	battle.add_child(reference)
	reference.position = Vector3(-1, 0, 4)
	var camera := Camera3D.new()
	battle.add_child(camera)
	camera.current = true
	camera.fov = 45
	for view in [
		["overview", Vector3(28, 34, 36), Vector3(0, 0, 0)],
		["loading", Vector3(12, 15, 25), Vector3(1, 0, 4)],
		["interior", Vector3(-15, 17, 13), Vector3(0, 0, -4)],
		["scale", Vector3(5, 5, 12), Vector3(-1, 1, 4)],
		["interface", Vector3(-15, 17, 13), Vector3(0, 0, -4)],
	]:
		floor_ui.visible = view[0] == "interface"
		if view[0] == "interface":
			battle.get_node("Systems/MouseRaycaster")._inspect_level(0.0)
		camera.position = view[1]
		camera.look_at(view[2])
		var focuses: Array[Vector3] = [view[2]]
		for roof in get_nodes_in_group("tactical_roof_cutaways"):
			if view[0] in ["overview", "loading"]:
				roof.restore_view()
			else:
				roof.update_view(camera.global_position, focuses)
		for visual in get_nodes_in_group("tactical_visual_occluders"):
			if view[0] in ["overview", "loading"]:
				visual.restore_view()
			else:
				visual.update_view(camera.global_position, focuses)
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join(view[0] + ".png"))
		if error != OK:
			push_error("Capture failed: %s" % error)
			quit(1)
			return
	print("Industrial captures saved to " + output)
	quit()

