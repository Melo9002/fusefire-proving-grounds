extends SceneTree
## Rendered evidence for Task 13 (explicit-only: needs a GPU): the three-family demonstration, stepped by hand at fixed times so each frame is reproducible.
##   godot --path . --script res://tests/motion_families_capture.gd -- <output-folder> [<width> <height>]
const SCENE := "res://research/motion_families_demo/motion_families_demo.tscn"
const TIMES := [1.5, 4.5, 7.0, 9.8, 12.2]

func _initialize() -> void:
	_run.call_deferred()

func _f(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_dir := args[0] if args.size() > 0 else "res://docs/claude/images/task13"
	if args.size() > 2:
		root.size = Vector2i(int(args[1]), int(args[2]))
	var demo: Node3D = (load(SCENE) as PackedScene).instantiate()
	demo.manual = true
	root.add_child(demo)
	await _f(20)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var index := 1
	for target in TIMES:
		while demo.time < target:
			demo.step(1.0 / 30.0)
			await process_frame
		await _f(3)
		var path := "%s/%02d-t%04.1f.png" % [out_dir, index, target]
		root.get_texture().get_image().save_png(path)
		print("saved ", path)
		index += 1
	quit()
