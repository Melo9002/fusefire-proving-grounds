extends SceneTree
## Explicit Task 5.4 render matrix. Normal views hide overlays; diagnostic
## overheads show parcels (amber), roads (cyan), selected frontages (green),
## functional access reservations (magenta), and mission reservations (yellow).

const CAPTURE_SIZE := Vector2i(1600, 900)

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	root.content_scale_size = CAPTURE_SIZE
	var editor = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	await _capture_case(editor, output, &"industrial_district", 17, [
		["overhead", &"", 0.0, 1.50, false],
		["loading", &"industrial_loading_canopy", 0.52, 0.18, false],
		["diagnostic", &"", 0.0, 1.50, true],
	])
	await _capture_case(editor, output, &"commercial_street", 7319, [
		["overhead", &"", 0.0, 1.50, false],
		["frontage", &"__first_shell", 0.35, 0.14, false],
		["diagnostic", &"__first_shell", 0.30, 0.48, true],
	])
	await _capture_case(editor, output, &"mixed_service", 11027, [
		["overhead", &"", 0.0, 1.50, false],
		["service", &"factory_pipe_receiver_unit", 0.70, 0.20, false],
		["diagnostic", &"factory_pipe_receiver_unit", 0.55, 0.50, true],
	])
	print("Bounded parcel retry captures saved to " + output)
	quit()

func _capture_case(editor: Node, output: String, environment_id: StringName, map_seed: int, views: Array) -> void:
	editor.layout_preset = environment_id
	editor.generation_seed = map_seed
	for index in editor.preset_picker.item_count:
		if editor.preset_picker.get_item_metadata(index) == environment_id:
			editor.preset_picker.select(index)
			break
	editor._rebuild()
	for view in views:
		var diagnostic: bool = view[4]
		editor._set_plan_overlay_visible(diagnostic)
		editor._set_spatial_contracts_visible(false)
		if view[1] == &"": editor._frame_camera()
		elif view[1] == &"__first_shell":
			if not _focus_first_shell(editor): editor._frame_camera()
		elif not editor._focus_component(view[1], "%s %s" % [environment_id, view[0]]): editor._frame_camera()
		editor._set_camera_view(float(view[2]), float(view[3]))
		await process_frame
		await RenderingServer.frame_post_draw
		var filename := "%s-%d-%s.png" % [environment_id, map_seed, view[0]]
		var error := root.get_texture().get_image().save_png(output.path_join(filename))
		if error != OK:
			push_error("Bounded-search capture failed: %s" % error)
			quit(1)

func _focus_first_shell(editor: Node) -> bool:
	for placement: EnvironmentModulePlacement in editor.displayed_data.environment_modules:
		if String(placement.component_id).begins_with("industrial_shell_"):
			return editor._focus_component(placement.component_id, "accepted bounded-search building frontage")
	return false
