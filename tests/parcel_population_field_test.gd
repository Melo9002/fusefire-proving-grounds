extends SceneTree
const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var definition = Catalog.get_definition(Catalog.INDUSTRIAL_OFFICE_PARKING_A)
	var scene_root: Node3D = definition.instantiate()
	var draft := Session.new()
	draft.begin(definition, scene_root)
	check(draft.add("ground", "parking", Rect2i(2, 4, 28, 8)), "Parking field adds inside selected surface")
	var sockets: Array[Dictionary] = definition.population_sockets(scene_root)
	check(draft.preview(sockets, 17, 100).size() == 3, "Full parking field accepts the three actual vehicle sockets")
	check(draft.preview(sockets, 17, 0).is_empty(), "Zero occupancy previews no movable occupants")
	check(draft.preview(sockets, 17, 65) == draft.preview(sockets, 17, 65), "Seeded field preview repeats")
	check(draft.add("ground", "protected", Rect2i(5, 6, 1, 1)), "Protected field intersects the car footprint without covering its anchor")
	check(draft.preview(sockets, 17, 100).size() == 2, "Protected field takes priority over permitted parking")
	check(draft.undo() and draft.preview(sockets, 17, 100).size() == 3, "Undo restores permission")
	check(draft.redo() and draft.preview(sockets, 17, 100).size() == 2, "Redo restores exclusion")
	var destination := "res://.godot/population_field_test.json"
	check(draft.save_to(destination), "Field draft saves")
	var loaded := Session.new()
	loaded.begin(definition, scene_root)
	check(loaded.load_from(destination), "Actual JSON field draft reloads: %s" % loaded.last_error)
	check(loaded.preview(sockets, 17, 100) == draft.preview(sockets, 17, 100), "Saved fields preserve preview")
	loaded.revision += 1
	var before := loaded.fields.duplicate(true)
	check(not loaded.load_from(destination) and loaded.fields == before, "Stale load preserves in-memory fields")
	check(not draft.add("missing", "parking", Rect2i(1, 1, 2, 2)), "Unknown surface rejects")
	check(not draft.add("ground", "parking", Rect2i(-1, 1, 2, 2)), "Out-of-surface field rejects")
	check(draft.erase_at("ground", Vector2i(5, 6)) and draft.fields.size() == 1, "Erase removes topmost matching field")
	var upstairs: Dictionary = sockets[0].duplicate(true)
	upstairs.socket_id = &"upper_car"
	upstairs.surface_id = &"upper"
	check(draft.preview([upstairs], 17, 100).is_empty(), "Ground field cannot populate a different floor at identical X/Z")
	var snapshot := draft.fields.duplicate(true)
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string("{bad json")
	file.close()
	check(not draft.load_from(destination) and draft.fields == snapshot, "Corrupt draft cannot replace valid field state")
	DirAccess.remove_absolute(destination)
	scene_root.free()
	var editor = load("res://tools/parcel_editor/parcel_editor.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	editor.select_parcel(Catalog.INDUSTRIAL_OFFICE_PARKING_A)
	editor._top_view()
	var panel = editor.field_panel
	panel.tool_picker.select(1)
	var start: Vector2 = editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(2, 0, 4)))
	var finish: Vector2 = editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(29, 0, 11)))
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = start
	check(panel.handle_input(event), "Draw tool handles actual screen-space press")
	event.pressed = false
	event.position = finish
	panel.handle_input(event)
	check(panel.session.fields.size() == 1 and Session.rectangle(panel.session.fields[0]) == Rect2i(2, 4, 28, 8), "Camera ray projects mouse drag into exact selected-floor cells")
	panel.density.value = 100
	panel.preview()
	check(panel.status.text.begins_with("3 authored sockets"), "Editor preview uses authored parking sockets")
	panel.reset_preview()
	editor.free()
	print("Population fields: %d failure(s)" % failures)
	quit(1 if failures else 0)
