extends SceneTree
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var editor := load("res://tools/parcel_editor/parcel_editor.tscn").instantiate() as ParcelEditor
	root.add_child(editor)
	await process_frame
	editor.select_parcel(AuthoredParcelCatalog.LOADING_YARD_A)
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor._top_view()
	var hidden := editor.displayed_parcel.get_node("ContainerB") as Node3D
	check(not hidden.is_visible_in_tree(), "Population models are hidden while editing guides")
	editor._start_fixed_placement("car_kit/ambulance")
	var screen := editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(12, 0, 25)))
	editor._update_library_placement(screen)
	check(editor._placement_issue.begins_with("Reserved container position") and not editor._placement_issue.contains("ContainerB"), "The red ghost explains a hidden reservation without an internal node name")
	check(is_instance_valid(editor._reservation_marker) and editor._reservation_marker.find_children("*", "Label3D", true, false)[0].text.replace("\n", " ") == "Reserved container position", "The conflicting reservation has a visible, labeled footprint")
	var args := OS.get_cmdline_user_args()
	if args.size() == 2 and args[0] == "capture" and DisplayServer.get_name() != "headless":
		DirAccess.make_dir_recursive_absolute(args[1])
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(args[1].path_join("reserved-container.png")) == OK, "Capture the real placement feedback")
	screen = editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(6, 0, 20)))
	editor._update_library_placement(screen)
	check(editor._placement_issue.is_empty() and not is_instance_valid(editor._reservation_marker), "Legal placement clears the previous reservation highlight")
	editor._update_library_placement(editor.camera.unproject_position(hidden.global_position))
	editor._finish_library_placement(false)
	check(not is_instance_valid(editor._reservation_marker) and not editor.draft.dirty, "Cancel clears the highlight without changing the draft")
	check(not editor.field_panel.preview_button.visible and editor.field_panel.registered_preview_button.text == "Compare original", "Preview has one primary location and the original comparison has a distinct label")
	check(editor.field_panel.find_children("*", "Label", true, false).any(func(label): return label.text == "Seed is saved with this parcel."), "Seed persistence is explained beside the setting")
	editor.select_parcel(AuthoredParcelCatalog.FLEET_APRON)
	editor._start_fixed_placement("car_kit/ambulance")
	editor._update_library_placement(editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(3, 0, 15))))
	check(editor._placement_issue.begins_with("Reserved vehicle position") and is_instance_valid(editor._reservation_marker), "Painted bays reserve future vehicles even without hidden vehicle nodes")
	editor._update_library_placement(editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(7.5, 0, 25))))
	check(editor._placement_issue.is_empty(), "The fleet's central aisle remains available for legal placement")
	editor._finish_library_placement(false)
	editor.free()
	print("Parcel reservation UX: %d failure(s)" % failures)
	quit(1 if failures else 0)
