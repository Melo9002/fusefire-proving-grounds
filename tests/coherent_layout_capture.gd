extends SceneTree

# Manual rendered inspection. Run without --headless and provide an output
# directory after --. This is evidence for human review, not a pixel test.
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
	for sample in [
		[&"industrial_district", 2208],
		[&"commercial_street", 7319],
		[&"mixed_service", 11027],
	]:
		editor.layout_preset = sample[0]
		editor.generation_seed = sample[1]
		for index in editor.preset_picker.item_count:
			if editor.preset_picker.get_item_metadata(index) == sample[0]:
				editor.preset_picker.select(index)
				break
		editor._rebuild()
		editor._frame_camera()
		editor._set_camera_view(0.72, 0.62)
		await process_frame
		await RenderingServer.frame_post_draw
		var filename := "%s-%d.png" % [sample[0], sample[1]]
		var error := root.get_texture().get_image().save_png(output.path_join(filename))
		if error != OK:
			push_error("Capture failed: %s" % error)
			quit(1)
			return
	print("Coherent layout captures saved to " + output)
	quit()
