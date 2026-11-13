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
	var target_container := editor.displayed_parcel.get_node("ContainerB") as Node3D
	editor._translate_selected(target_container.position - container.position)
	check(container.position.is_equal_approx(container_start) and "Overlaps ContainerB" in editor.draft_status.text, "A nudge cannot place the container inside another solid")
	var warehouse := editor.displayed_parcel.get_node("Warehouse") as Node3D
	editor._translate_selected(warehouse.position - container.position)
	check(container.position.is_equal_approx(container_start) and "Overlaps Warehouse" in editor.draft_status.text, "A container cannot be placed inside the warehouse")
	editor._start_object_drag(pick_position)
	var outside: Vector2 = editor.camera.unproject_position(container.global_position + Vector3(-3, 0.9, 0))
	editor._preview_object_drag(outside)
	check(editor._placement_issue == "Outside parcel" and editor._ghost_material.albedo_color.r > 0.9, "A pivot inside the parcel still shows a red ghost for an overhanging footprint")
	editor._finish_object_drag(true)
	check(container.position.is_equal_approx(container_start) and editor.draft.undo_stack.is_empty(), "Releasing an invalid ghost restores its starting pose")
	editor._translate_selected(Vector3(-2.5, 0, 0))
	check(is_equal_approx(container.position.x, 0.5), "The narrow orientation fits next to the parcel edge")
	editor._rotate_selected(1)
	check(is_equal_approx(container.rotation_degrees.y, source_yaw) and "Outside parcel" in editor.draft_status.text, "A quarter-turn is rejected if the rotated footprint would overhang")
	editor._undo()
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
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor.draft.select("CrateA")
	var crate := editor.displayed_parcel.get_node("CrateA") as Node3D
	var original_crate_position := crate.position
	editor._translate_selected(Vector3.RIGHT)
	var moved_crate_position := crate.position
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	var panel = editor.field_panel
	check(moved_crate_position != original_crate_position and not panel.preview_button.disabled and panel.registered_preview_button.visible, "Moved objects support combined Preview and retain the registered comparison")
	panel.registered_preview_button.pressed.emit()
	var registered: Node3D = panel._runtime_preview
	check(is_instance_valid(registered) and (registered.get_node("CrateA") as Node3D).position == original_crate_position and not panel.overlay.visible, "Registered Preview uses a separate source scene and hides draft paint")
	panel.next_seed_button.pressed.emit()
	check(is_instance_valid(panel._runtime_preview) and "Registered preview" in panel.preview_context.text, "Next seed stays in the registered preview while drafts are parked")
	panel.reset_preview()
	check(crate.position == moved_crate_position and panel.session.fields.size() == 1 and editor.draft.dirty and panel.has_unsaved_changes(), "Exiting registered preview preserves both unsaved drafts")
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor._undo()
	check(editor._asset_picker.item_count > 4 and not editor._add_asset_button.disabled, "The fixed asset browser opens with tactical and decorative entries")
	editor._asset_filter.text = "box-large"
	editor._asset_filter.text_changed.emit(editor._asset_filter.text)
	check(editor._asset_picker.item_count == 1, "The fixed asset browser filters the calibrated library")
	check(editor.asset_preview.asset_id == "factory_kit/box-large" and is_instance_valid(editor.asset_preview.model), "Filtering displays the actual selected asset in a separate preview viewport")
	editor._start_library_placement()
	var blocked_cursor: Vector2 = editor.camera.unproject_position(warehouse.global_position)
	editor._update_library_placement(blocked_cursor)
	check(editor._placement_issue.contains("Warehouse") and editor._ghost_material.albedo_color.r > 0.9, "A new tactical asset shows a red ghost over the warehouse")
	var valid_cursor: Vector2 = editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(7, 0, 17)))
	editor._update_library_placement(valid_cursor)
	check(editor._placement_issue.is_empty() and editor._ghost_material.albedo_color.b > 0.9, "A supported ground placement shows a blue ghost")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = valid_cursor
	editor._unhandled_input(press)
	var new_path: String = editor.draft.selected_path
	var added := editor.displayed_parcel.get_node_or_null(NodePath(new_path)) as Node3D
	check(added != null and added.has_node("TacticalVolume") and not added.has_meta("population_socket_id"), "Fixed placement carries an authored volume without a population rule")
	editor._undo()
	check(editor.displayed_parcel.get_node_or_null(NodePath(new_path)) == null, "Undo removes a new fixed object")
	editor._redo()
	check(editor.displayed_parcel.has_node(NodePath(new_path)), "Redo reconstructs a new fixed object")
	editor._remove_selected()
	check(not editor.displayed_parcel.has_node(NodePath(new_path)), "Remove deletes the new object from the draft")
	editor._undo()
	check(editor.draft.save_to(test_draft_path), "Added assets save with the visual draft")
	editor._remove_selected()
	editor._apply_loaded_draft(test_draft_path)
	check(editor.displayed_parcel.has_node(NodePath(new_path)) and not editor.draft.dirty, "Opening a saved draft reconstructs its manually placed object")
	DirAccess.remove_absolute(test_draft_path)
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
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
