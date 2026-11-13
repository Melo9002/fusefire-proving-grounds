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
	editor.select_parcel(Catalog.INDUSTRIAL_OFFICE_PARKING_RULES)
	editor._top_view()
	await _capture(output.path_join("office-seeded-guides.png"))
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	editor.field_panel.seed_input.value = 2
	editor.field_panel.preview()
	await _capture(output.path_join("office-seed-2-preview.png"))
	editor.select_parcel(Catalog.LOADING_YARD_A)
	await _capture(output.path_join("loading-yard-guides.png"))
	editor.select_parcel(Catalog.LOADING_YARD_PAINTED)
	editor._top_view()
	await _capture(output.path_join("painted-container-guides.png"))
	editor.field_panel.seed_input.value = 0
	editor.field_panel.preview()
	await _capture(output.path_join("painted-container-preview.png"))
	editor.field_panel.reset_preview()
	editor.select_parcel(Catalog.MAINTENANCE_GALLERY_A)
	editor.tactical_toggle.button_pressed = true
	await _capture(output.path_join("parcel-editor-maintenance-contracts.png"))
	editor.select_parcel(Catalog.LOADING_YARD_A)
	editor.population_toggle.button_pressed = false
	editor.tactical_toggle.button_pressed = false
	await _capture(output.path_join("parcel-editor-loading-fixed-assembly.png"))
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor.draft.select("Warehouse")
	editor._refresh_placement_picker()
	editor._update_draft_status()
	await _capture(output.path_join("parcel-editor-move-objects.png"))
	editor._top_view()
	editor._asset_filter.text = "box-large"
	editor._asset_filter.text_changed.emit(editor._asset_filter.text)
	editor._start_library_placement()
	editor._update_library_placement(editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(7, 0, 17))))
	await _capture(output.path_join("fixed-crate-placement.png"))
	editor.thumbnail_toggle.button_pressed = false
	await _capture(output.path_join("objects-thumbnail-collapsed.png"))
	editor.thumbnail_toggle.button_pressed = true
	editor._finish_library_placement(false)
	editor.draft.select("CrateA")
	editor._translate_selected(Vector3.RIGHT)
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	await _capture(output.path_join("registered-preview-draft-safety.png"))
	editor.field_panel.preview_registered()
	await _capture(output.path_join("registered-preview-active.png"))
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor._undo()
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	editor.field_panel.session.add("ground", "containers", Rect2i(2, 21, 3, 5))
	editor.field_panel.refresh()
	await _capture(output.path_join("container-guide-conflict.png"))
	editor.field_panel.locate_fit_conflict(true)
	await _capture(output.path_join("container-conflict-located.png"))
	editor._frame()
	editor.field_panel.session.undo()
	editor.field_panel.session.add("ground", "containers", Rect2i(7, 20, 3, 10))
	editor.field_panel.density.value = 100
	var truck: Node3D = editor.PlacementLibrary.create("car_kit/delivery")
	truck.position = Vector3(8, 0, 22)
	truck.rotation_degrees.y = 90
	editor.draft.add_fixed(truck)
	truck.free()
	editor._apply_draft()
	editor.field_panel.refresh()
	editor.field_panel.preview()
	await _capture(output.path_join("combined-truck-containers.png"))
	editor.tactical_toggle.button_pressed = true
	editor.tactical_scope.select(1)
	editor.tactical_scope.item_selected.emit(1)
	await _capture(output.path_join("selected-truck-tactical-bounds.png"))
	editor.tactical_scope.select(0)
	editor.tactical_scope.item_selected.emit(0)
	await _capture(output.path_join("combined-tactical-bounds.png"))
	editor.tactical_toggle.button_pressed = false
	if not editor.field_panel.export_scene(output.path_join("combined-parcel.tscn")):
		push_error(editor.field_panel.status.text)
		quit(1)
		return
	await _capture(output.path_join("combined-export-status.png"))
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	await _capture(output.path_join("objects-export-footer.png"))
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	var field_scroll := editor.field_panel.handoff_steps.get_parent().get_parent() as ScrollContainer
	field_scroll.ensure_control_visible(editor.field_panel.handoff_next)
	await _capture(output.path_join("export-handoff-checklist.png"))
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor._undo()
	editor.field_panel.session.undo()
	editor.field_panel.refresh()
	editor.set_population_visible(true)
	editor._top_view()
	var container := editor.displayed_parcel.get_node("ContainerA") as Node3D
	var anchor := container.global_position + Vector3.UP * 0.9
	if editor._start_object_drag(editor.camera.unproject_position(anchor)):
		editor._preview_object_drag(editor.camera.unproject_position(anchor + Vector3(4, 0, -3)))
		await _capture(output.path_join("parcel-editor-drag-preview.png"))
		editor._preview_object_drag(editor.camera.unproject_position(anchor + Vector3(-3, 0, 0)))
		await _capture(output.path_join("parcel-editor-invalid-placement.png"))
		editor._finish_object_drag(false)
	editor.select_parcel(Catalog.INDUSTRIAL_OFFICE_PARKING_A)
	if editor.discard_dialog.visible:
		editor.discard_dialog.get_ok_button().pressed.emit()
		await process_frame
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	editor._top_view()
	editor.field_panel.select_tool(1)
	var stroke := InputEventMouseButton.new()
	stroke.button_index = MOUSE_BUTTON_LEFT
	stroke.pressed = true
	stroke.position = editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(15, 0, 22)))
	editor.field_panel.handle_input(stroke)
	await _capture(output.path_join("office-illegal-paint.png"))
	stroke.pressed = false
	editor.field_panel.handle_input(stroke)
	editor.field_panel.session.add("ground", "parking", Rect2i(2, 4, 28, 8))
	editor.field_panel.refresh()
	editor.field_panel.density.value = 100
	editor.field_panel.preview()
	await _capture(output.path_join("parcel-editor-paint-only-parking.png"))
	editor.field_panel.session.add("ground", "protected", Rect2i(4, 5, 5, 6))
	editor.field_panel.refresh()
	editor.field_panel.density.value = 100
	editor.field_panel.preview()
	await process_frame
	await _capture(output.path_join("parcel-editor-parking-fields.png"))
	editor.field_panel.session.erase_at("ground", Vector2i(5, 6))
	editor.field_panel.select_tool(3)
	await _capture(output.path_join("parcel-editor-aisle-direction.png"))
	editor.field_panel.session.add("ground", "parking_row", Rect2i(13, 6, 12, 5), 0)
	editor.field_panel.refresh()
	await process_frame
	await _capture(output.path_join("parcel-editor-empty-row.png"))
	editor.field_panel.preview()
	editor._yaw = deg_to_rad(145.0)
	editor._pitch = deg_to_rad(44.0)
	editor._frame()
	await _capture(output.path_join("parcel-editor-populated-row.png"))
	var scene_path := output.path_join("review-office-parking-rows.tscn")
	if not editor.field_panel.export_scene(scene_path):
		push_error(editor.field_panel.status.text)
		quit(1)
		return
	var baked := load(scene_path).instantiate() as Node3D
	baked.position = editor.displayed_parcel.position
	editor.field_panel.clear_preview()
	editor.displayed_parcel.hide()
	editor.field_panel.overlay.hide()
	editor.add_child(baked)
	await _capture(output.path_join("parcel-editor-exported-row.png"))
	print("Parcel Editor captures saved to " + output)
	quit()

func _capture(path: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var error := root.get_texture().get_image().save_png(path)
	if error != OK:
		push_error("Parcel Editor capture failed: %s" % error_string(error))
		quit(1)
