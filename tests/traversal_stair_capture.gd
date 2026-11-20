extends SceneTree
## Rendered evidence for stair foot placement and corridor-aware path presentation (explicit-only: needs a GPU, not part of the standard tiers): the production rig on the
## workbench's stair (side view, planned and actual foot markers) and the PathRefiner's layouts seen from above, in one contact sheet.
## godot --path . --script res://tests/traversal_stair_capture.gd -- <output.png>

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_path := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://stairs.png"
	var bench = load("res://art/characters/mira_0/demo/mira_0_pose_workbench.tscn").instantiate()
	root.add_child(bench)
	for i in 30: await process_frame
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 45.0
	bench.stair_diagnostics = true
	var tiles: Array[Image] = []
	# Row 1: ascending the 0.5 m range stairs; row 2: descending them (side view).
	for ascending in [true, false]:
		bench.start_stair_demo(0.5, 0.5, 6, ascending, 1.4, 0.0 if ascending else 3.0)
		camera.global_position = Vector3(3.4, 1.4, 0.4)
		camera.look_at(Vector3(0, 0.9, 0.4), Vector3.UP)
		var positions := [0.1, 0.6, 1.1, 1.6, 2.1, 2.6] if ascending else [2.9, 2.4, 1.9, 1.4, 0.9, 0.4]
		for s in positions:
			bench.set_stair_demo_s(s)
			for i in 6: await process_frame
			tiles.append(root.get_texture().get_image())
	bench.end_stair_demo()
	# Row 3: the path layouts from above.
	camera.global_position = Vector3(0.5, 9.0, 0.6)
	camera.look_at(Vector3(0.0, 0.0, 0.5), Vector3.BACK)
	for kind in ["open", "wall", "corner", "column", "narrow", "too_narrow"]:
		bench.show_path_demo(kind)
		for i in 4: await process_frame
		tiles.append(root.get_texture().get_image())
	var width := 480
	var height := 270
	var sheet := Image.create(width * 6, height * 3, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		var tile := tiles[i]
		tile.resize(width, height)
		sheet.blit_rect(tile, Rect2i(0, 0, width, height), Vector2i((i % 6) * width, (i / 6) * height))
	sheet.save_png(out_path)
	print("tiles %d -> %s" % [tiles.size(), out_path])
	quit(0)
