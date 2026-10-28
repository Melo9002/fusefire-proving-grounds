extends SceneTree
## Manual evidence for Task 4.4. The captured scene is rebuilt from a saved
## generated-to-edited document through the real Map Editor load path.

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output directory are required.")
		quit(1)
		return
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output)
	var persistence_path := output.path_join("task-4.4-temporary-layout.json")
	var editor = load("res://tools/map_editor.tscn").instantiate()
	editor.custom_layout_path = persistence_path
	root.add_child(editor)
	await process_frame
	editor.layout_preset = &"industrial_district"
	editor.generation_seed = 2208
	editor._rebuild()
	await process_frame
	editor._compose_current_layout()
	await process_frame
	if not _block_one_deployment(editor):
		push_error("Could not create the representative edited deployment fixture.")
		quit(1)
		return
	editor._rebuild()
	await process_frame
	editor._save_custom_layout()
	editor._clear_custom_layout()
	await process_frame
	editor._load_custom_layout(true)
	await process_frame
	if not editor.custom_build_errors.is_empty():
		push_error("Reloaded capture document is invalid: %s" % editor.custom_build_errors[0])
		quit(1)
		return
	editor._set_plan_overlay_visible(false)
	editor._set_spatial_contracts_visible(false)
	for view in [
		["overhead", 0.0, 1.50, &""],
		["oblique", 0.72, 0.62, &""],
		["frontage", 0.35, 0.18, &"industrial_shell_e"],
	]:
		if view[3] == &"":
			editor._frame_camera()
		else:
			editor._focus_component(view[3], "reloaded edited building frontage")
		editor._set_camera_view(view[1], view[2])
		await process_frame
		await RenderingServer.frame_post_draw
		var error := root.get_texture().get_image().save_png(output.path_join("layout-lifecycle-%s.png" % view[0]))
		if error != OK:
			push_error("Lifecycle capture failed: %s" % error_string(error))
			quit(1)
			return
	DirAccess.remove_absolute(persistence_path)
	print("Battlefield layout lifecycle captures saved to " + output)
	quit(0)

func _block_one_deployment(editor) -> bool:
	for zone in editor.displayed_data.get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT):
		for spawn in zone.cells:
			var candidate := EnvironmentModuleLayout.new(editor.custom_layout.layout_id, editor.custom_layout.generation_seed)
			for placement: EnvironmentModulePlacement in editor.custom_layout.placements:
				var copy := placement.copy()
				if not candidate.try_add(editor.editor_catalog[copy.component_id], copy, editor.preview_map_size):
					return false
			var barrier := EnvironmentModulePlacement.new(&"construction_barrier_vault", Vector2i(spawn.x, spawn.z))
			if candidate.try_add(editor.editor_catalog.construction_barrier_vault, barrier, editor.preview_map_size):
				editor._accept_custom_layout(candidate)
				return true
	return false
