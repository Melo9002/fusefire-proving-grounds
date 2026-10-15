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
	for id in ["city_kit_industrial/building-a", "city_kit_roads/road-straight", "factory_kit/structure-window", "modular_space_kit/corridor"]:
		lab.select_asset(id)
		await process_frame
		await RenderingServer.frame_post_draw
		assert(root.get_texture().get_image().save_png(args[0].path_join(id.replace("/", "-") + ".png")) == OK)
	print("MIRA ready bounds: ", lab.Placement.mesh_bounds(lab.comparison))
	print("Asset lab captured 9 views")
	quit()
