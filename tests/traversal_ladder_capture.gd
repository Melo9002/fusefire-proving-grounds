extends SceneTree
## Rendered evidence for the ladder pose (explicit-only: needs a GPU, not part of the standard tiers): the production rig through a climb in the workbench, side and 3/4
## views, written to one contact sheet.
## godot --path . --script res://tests/traversal_ladder_capture.gd -- <output.png>

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var out_path := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://ladder.png"
	var bench = load("res://art/characters/mira_0/demo/mira_0_pose_workbench.tscn").instantiate()
	root.add_child(bench)
	for i in 30: await process_frame
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	camera.fov = 45.0
	bench.traversal_diagnostics = true
	var views := [[Vector3(3.2, 1.2, 0.0), Vector3(0, 0.95, 0.1)], [Vector3(2.2, 1.5, 2.6), Vector3(0, 0.95, 0.1)]]
	var heights := [0.0, 0.3, 0.8, 1.45, 2.1, 2.9, 3.4, 3.8]
	var tiles: Array[Image] = []
	bench.start_ladder_demo(4.0, 1, 0.0, 0.0)
	for view in views:
		camera.global_position = view[0]
		camera.look_at(view[1], Vector3.UP)
		for h in heights:
			bench.ladder_demo.playing = false
			bench.set_ladder_height(h)
			for i in 8: await process_frame
			tiles.append(root.get_texture().get_image())
	var width := 480
	var height := 270
	var sheet := Image.create(width * heights.size() / 2, height * 4, false, Image.FORMAT_RGB8)
	for i in tiles.size():
		var tile := tiles[i]
		tile.resize(width, height)
		sheet.blit_rect(tile, Rect2i(0, 0, width, height), Vector2i((i % 4) * width, (i / 4) * height))
	sheet.save_png(out_path)
	print("tiles %d -> %s" % [tiles.size(), out_path])
	quit(0)
