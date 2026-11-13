extends SceneTree
## Rendered inspection for the battle-preparation transition.

const LoadingScreen = preload("res://ui/battle_loading_screen.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty() or DisplayServer.get_name() == "headless":
		push_error("A rendered window and output path are required.")
		quit(1)
		return
	var screen := LoadingScreen.new()
	root.add_child(screen)
	screen.set_stage("Constructing tactical battlefield…", 0.28)
	await process_frame
	await RenderingServer.frame_post_draw
	var output := args[0]
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := root.get_texture().get_image().save_png(output)
	if error != OK:
		push_error("Loading-screen capture failed: %s" % error)
		quit(1)
		return
	print("Battle loading screen saved to " + output)
	quit()
