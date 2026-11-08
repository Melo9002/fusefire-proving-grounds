extends SceneTree

const EditorScene = preload("res://tools/parcel_editor/parcel_editor.tscn")
const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const Definition = preload("res://systems/generation/authored_parcel_definition.gd")
const DraftSession = preload("res://tools/parcel_editor/parcel_draft_session.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var editor: Node3D = EditorScene.instantiate()
	root.add_child(editor)
	await process_frame
	check(editor.parcel_picker.item_count == Catalog.all().size(), "Parcel Editor lists every registered parcel")
	check(editor.task_tabs.current_tab == ParcelEditor.Task.INSPECT and not editor.metadata_label.visible, "Editor opens on compact inspection with technical details collapsed")
	check(editor.select_parcel(Catalog.MAINTENANCE_GALLERY_A), "Parcel Editor opens the maintenance gallery by stable ID")
	check(editor.displayed_parcel != null and editor.displayed_parcel_id == Catalog.MAINTENANCE_GALLERY_A, "Selected registered scene is instantiated")
	check(editor.validation_label.text.begins_with("VALID"), "Registered parcel validation is visible")
	check(editor.tactical_overlay.get_child_count() >= 4, "Maintenance gallery exposes solid, deck, and access contracts independently of its meshes")
	check(editor.select_parcel(Catalog.LOADING_YARD_A), "Parcel Editor opens a populated loading parcel")
	var population_nodes: Array = editor.displayed_parcel.find_children("*", "Node3D", true, false).filter(func(node): return node.has_meta("population_socket_id"))
	check(not population_nodes.is_empty(), "Loading parcel exposes authored population nodes")
	editor.set_population_visible(false)
	check(population_nodes.all(func(node): return not (node as Node3D).visible), "Population toggle can isolate the fixed parcel assembly")
	var draft = DraftSession.new()
	var test_definition = Definition.new(&"parcel_editor_test", "Test draft", &"test", 1, Vector2i(16, 32), null)
	draft.begin(test_definition, editor.displayed_parcel)
	check(not draft.placements.is_empty(), "Draft starts from stable imported-asset scene paths")
	var selected: Dictionary = draft.placement()
	var selected_node := editor.displayed_parcel.get_node(NodePath(String(selected.path))) as Node3D
	var original_position := selected_node.position
	check(draft.translate_selected(Vector3(0.5, 0, -0.5)), "Selected visual placement accepts a snapped edit")
	check(draft.apply(editor.displayed_parcel).is_empty() and selected_node.position.is_equal_approx(original_position + Vector3(0.5, 0, -0.5)), "Draft transform applies to the preview scene")
	check(draft.undo() and draft.apply(editor.displayed_parcel).is_empty() and selected_node.position.is_equal_approx(original_position), "Undo restores the authored visual transform")
	check(draft.redo() and draft.apply(editor.displayed_parcel).is_empty() and selected_node.position.is_equal_approx(original_position + Vector3(0.5, 0, -0.5)), "Redo reapplies the visual transform")
	var test_draft_path := "res://.godot/parcel_editor_test.draft.json"
	check(draft.save_to(test_draft_path), "Visual draft saves outside registered runtime content")
	var loaded = DraftSession.new()
	check(loaded.load_from(test_draft_path, test_definition, editor.displayed_parcel), "Saved draft reloads against its exact parcel revision")
	var loaded_selected: Dictionary = loaded.placement(String(selected.path))
	check(String(loaded_selected.get("asset_id", "")) == String(selected.asset_id) and Vector3(float(loaded_selected.position[0]), float(loaded_selected.position[1]), float(loaded_selected.position[2])).is_equal_approx(original_position + Vector3(0.5, 0, -0.5)), "Draft save/load preserves stable identity and transform")
	var stale_definition = Definition.new(&"parcel_editor_test", "Test draft", &"test", 2, Vector2i(16, 32), null)
	check(not loaded.load_from(test_draft_path, stale_definition, editor.displayed_parcel) and loaded.last_error.contains("STALE_PARCEL_REVISION"), "A changed source parcel revision invalidates its visual draft")
	if FileAccess.file_exists(test_draft_path):
		DirAccess.remove_absolute(test_draft_path)
	editor.set_population_visible(true)
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	check(is_instance_valid(editor._selection_marker), "Move task shows the selected object's bounds and axes")
	editor._translate_selected(Vector3.RIGHT * 0.5)
	check(editor.draft.dirty and "visual moves" in editor.draft_badge.text, "Visual edits update the scoped unsaved indicator")
	editor._undo()
	check(not editor.draft.dirty, "Undoing to the source transforms clears the visual dirty state")
	editor._top_view()
	var container := editor.displayed_parcel.get_node("ContainerA") as Node3D
	var container_start := container.position
	var source_yaw := container.rotation_degrees.y
	var pick_position: Vector2 = editor.camera.unproject_position(container.global_position + Vector3.UP * 0.9)
	var drop_position: Vector2 = editor.camera.unproject_position(container.global_position + Vector3.UP * 0.9 + Vector3(2.2, 0, -1.3))
	check(editor._start_object_drag(pick_position) and editor.draft.selected_path == "ContainerA", "Viewport picking selects the real imported container")
	editor._preview_object_drag(drop_position)
	check(container.position.is_equal_approx(container_start + Vector3(2.0, 0, -1.5)) and not editor.draft.dirty, "The live drag follows the ground grid without committing a draft")
	var rotate := InputEventKey.new()
	rotate.keycode = KEY_R
	rotate.pressed = true
	editor._input(rotate)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = drop_position
	editor._input(release)
	check(editor.draft.undo_stack.size() == 1 and is_equal_approx(container.rotation_degrees.y, source_yaw + 90.0), "Dropping and rotating commit together as one undo step")
	editor._undo()
	check(container.position.is_equal_approx(container_start) and is_equal_approx(container.rotation_degrees.y, source_yaw), "Undo restores both pose components")
	editor._start_object_drag(pick_position)
	editor._preview_object_drag(drop_position)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	editor._input(escape)
	check(container.position.is_equal_approx(container_start) and not editor.draft.dirty and editor.draft.undo_stack.is_empty(), "Escape restores a live pose without adding history")
	editor._save_draft_as()
	check(editor._draft_file_dialog.visible and editor._draft_file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE, "Save As opens a named destination picker")
	editor._draft_file_dialog.hide()
	editor._draft_file_dialog.file_selected.emit(test_draft_path)
	check(FileAccess.file_exists(test_draft_path), "The Save As callback writes the chosen file")
	var replacement := {"confirmed": false}
	editor.confirm_replace_draft(test_draft_path, func(): replacement.confirmed = true)
	check(editor.discard_dialog.visible and not replacement.confirmed, "Quick save pauses before replacing an existing draft")
	editor.discard_dialog.get_cancel_button().pressed.emit()
	await process_frame
	check(not replacement.confirmed and FileAccess.file_exists(test_draft_path), "Canceling replacement keeps the existing draft")
	DirAccess.remove_absolute(test_draft_path)
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	check(not is_instance_valid(editor._selection_marker), "The visual selection marker stays out of population editing")
	check(editor.field_panel.session.add("ground", "protected", Rect2i(1, 1, 2, 2)), "Field fixture adds an unsaved protection area")
	editor.field_panel.refresh()
	editor.select_parcel(Catalog.MAINTENANCE_GALLERY_A)
	check(editor.discard_dialog.visible and editor.displayed_parcel_id == Catalog.LOADING_YARD_A and "population fields" in editor.discard_dialog.dialog_text, "A parcel switch warns about unsaved population fields")
	editor.discard_dialog.get_cancel_button().pressed.emit()
	await process_frame
	check(editor.displayed_parcel_id == Catalog.LOADING_YARD_A and editor.field_panel.session.fields.size() == 1, "Cancel keeps the current parcel and unsaved fields")
	editor.select_parcel(Catalog.MAINTENANCE_GALLERY_A)
	editor.discard_dialog.get_ok_button().pressed.emit()
	await process_frame
	check(editor.displayed_parcel_id == Catalog.MAINTENANCE_GALLERY_A and editor.field_panel.session.fields.is_empty() and not editor.field_panel.has_unsaved_changes(), "Confirmed switch starts a clean draft for the new parcel")
	editor.free()
	var menu: Control = load("res://ui/match_setup.tscn").instantiate()
	root.add_child(menu)
	await process_frame
	check(menu.find_child("ParcelEditorButton", true, false) != null, "Match Setup exposes the Parcel Editor without a hidden debug flag")
	menu.free()
	print("Parcel Editor: %d failure(s)" % failures)
	quit(1 if failures else 0)
