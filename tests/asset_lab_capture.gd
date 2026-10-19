extends SceneTree
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var lab = load("res://tools/asset_lab/asset_lab.tscn").instantiate()
	root.add_child(lab)
	await process_frame
	if DisplayServer.get_name() == "headless":
		print("Asset lab scene loaded")
		quit()
		return
	var args = OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("Supply an output directory after --")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	for index in range(5):
		lab.mode.select(index)
		lab.rebuild(true)
		await process_frame
		await RenderingServer.frame_post_draw
		var error = root.get_texture().get_image().save_png(args[0].path_join("assembly-%d.png" % index))
		assert(error == OK)
	var inspected := [
		"city_kit_industrial/building-c",
		"city_kit_industrial/chimney-large",
		"city_kit_industrial/shipping-container-a",
		"city_kit_industrial/water-tower",
		"city_kit_roads/construction-fence",
		"city_kit_roads/dumpster",
		"city_kit_roads/electricity-pole",
		"city_kit_roads/light-curved",
		"city_kit_roads/road-straight",
		"factory_kit/structure-window",
		"modular_space_kit/corridor",
	]
	for id in inspected:
		lab.select_asset(id)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(args[0].path_join(id.replace("/", "-") + ".png")) == OK)
	lab.select_asset("factory_kit/structure-corner-inner")
	lab._select_option_value(lab.semantic_front, "+z")
	lab._select_option_value(lab.semantic_secondary_front, "+x")
	lab.rebuild(true)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(args[0].path_join("factory-corner-two-working-faces.png")) == OK)
	lab.select_asset("factory_kit/structure-corner-outer")
	lab._select_option_value(lab.semantic_front, "-z")
	lab._select_option_value(lab.semantic_secondary_front, "-x")
	lab.rebuild(true)
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(args[0].path_join("factory-outer-corner-two-working-faces.png")) == OK)
	print("MIRA ready bounds: ", lab.Placement.mesh_bounds(lab.comparison))
	print("Asset lab captured %d views" % (7 + inspected.size()))
	quit()
