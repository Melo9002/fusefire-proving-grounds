extends SceneTree
## Explicit-only visual evidence for the compact Parcel Editor inspection shell.

const EditorScene = preload("res://tools/parcel_editor/parcel_editor.tscn")
const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")

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
	var editor: Node3D = EditorScene.instantiate()
	root.add_child(editor)
	await process_frame
	editor.select_parcel(Catalog.MAINTENANCE_GALLERY_A)
	editor.tactical_toggle.button_pressed = true
	await _capture(output.path_join("parcel-editor-maintenance-contracts.png"))
	editor.select_parcel(Catalog.LOADING_YARD_A)
	editor.population_toggle.button_pressed = false
	editor.tactical_toggle.button_pressed = false
	await _capture(output.path_join("parcel-editor-loading-fixed-assembly.png"))
	print("Parcel Editor captures saved to " + output)
	quit()

func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Parcel Editor capture failed: %s" % error_string(error))
		quit(1)
