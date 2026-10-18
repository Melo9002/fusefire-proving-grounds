extends SceneTree
## Explicit rendered QA for authored structural assemblies.  This is excluded
## from automated tiers because visual correctness requires a real renderer and
## human inspection.

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
	var editor = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.layout_preset = &"building_gallery"
	editor.generation_seed = 2202
	for index in editor.preset_picker.item_count:
		if editor.preset_picker.get_item_metadata(index) == &"building_gallery":
			editor.preset_picker.select(index)
			break
	editor._rebuild()
	editor._set_plan_overlay_visible(false)
	for component_id in [&"complete_service_building", &"industrial_loading_canopy", &"industrial_building_shell"]:
		if not editor._focus_component(component_id, String(component_id).replace("_", " ")):
			push_error("Gallery component is missing: %s" % component_id)
			quit(1)
			return
		for view in [
			["front", 0.0, 0.18],
			["side", PI * 0.5, 0.18],
			["back", PI, 0.18],
			["overhead", 0.0, 1.50],
		]:
			editor._set_camera_view(view[1], view[2])
			await process_frame
			await RenderingServer.frame_post_draw
			var filename := "%s-%s.png" % [component_id, view[0]]
			var error := root.get_texture().get_image().save_png(output.path_join(filename))
			if error != OK:
				push_error("Capture failed: %s" % error)
				quit(1)
				return
		if component_id == &"complete_service_building":
			for diagnostic in [
				[editor.ASSEMBLY_VIEW_SHELL, "shell"],
				[editor.ASSEMBLY_VIEW_DECORATION, "decoration"],
			]:
				editor._set_assembly_view(diagnostic[0])
				editor._set_camera_view(0.0, 0.18)
				await process_frame
				await RenderingServer.frame_post_draw
				var diagnostic_name := "%s-%s.png" % [component_id, diagnostic[1]]
				var diagnostic_error := root.get_texture().get_image().save_png(output.path_join(diagnostic_name))
				if diagnostic_error != OK:
					push_error("Capture failed: %s" % diagnostic_error)
					quit(1)
					return
			editor._set_assembly_view(editor.ASSEMBLY_VIEW_COMPLETE)
	print("Structural building captures saved to " + output)
	quit()
