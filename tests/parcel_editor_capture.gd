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
	editor.task_tabs.current_tab = ParcelEditor.Task.MOVE_OBJECTS
	editor.draft.select("Warehouse")
	editor._refresh_placement_picker()
	editor._update_draft_status()
	await _capture(output.path_join("parcel-editor-move-objects.png"))
	editor.select_parcel(Catalog.INDUSTRIAL_OFFICE_PARKING_A)
	editor.task_tabs.current_tab = ParcelEditor.Task.POPULATION_FIELDS
	editor._top_view()
	editor.field_panel.session.add("ground", "parking", Rect2i(2, 4, 28, 8))
	editor.field_panel.session.add("ground", "protected", Rect2i(4, 5, 5, 6))
	editor.field_panel.refresh()
	editor.field_panel.density.value = 100
	editor.field_panel.preview()
	await process_frame
	await _capture(output.path_join("parcel-editor-parking-fields.png"))
	editor.field_panel.session.erase_at("ground", Vector2i(5, 6))
	editor.field_panel.session.add("ground", "parking_row", Rect2i(13, 6, 12, 5), 0)
	editor.field_panel.select_tool(3)
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
