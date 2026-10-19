extends SceneTree

const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	if DisplayServer.get_name() == "headless":
		print("Debug Draw 3D capture requires a graphics run")
		quit()
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Supply an output PNG path after --")
		quit(1)
		return
	var editor = load("res://tools/map_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	var diagnostic_index := 0
	for index in editor.displayed_data.environment_modules.size():
		var placement: EnvironmentModulePlacement = editor.displayed_data.environment_modules[index]
		var definition: EnvironmentModuleDefinition = editor.editor_catalog.get(placement.component_id)
		if definition != null and not definition.clearance_cells.is_empty() and definition.visual_envelope.size != Vector3.ZERO and not definition.connections.is_empty():
			diagnostic_index = index
			break
	editor._select_placement_index(diagnostic_index)
	editor._set_spatial_contracts_visible(true)
	if is_instance_valid(editor.inspection_module):
		editor.orbit.frame(AssetPlacement.mesh_bounds(editor.inspection_module).grow(3.0))
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var output: String = args[0]
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := root.get_texture().get_image().save_png(output)
	if error != OK:
		push_error("Debug Draw 3D capture failed: %s" % error_string(error))
	quit(0 if error == OK else 1)
