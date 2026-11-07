extends SceneTree
const Session = preload("res://tools/parcel_editor/population_field_draft.gd")
const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const Resolver = preload("res://systems/generation/refinery_plot_resolver.gd")
const Recording = preload("res://systems/replay/battle_replay_recording.gd")
const Compiler = preload("res://systems/generation/authored_scene_map_compiler.gd")
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
	var obstacles: Array[AABB] = definition.fixed_population_obstacles(scene_root)
	check(draft.preview(sockets, 17, 100, obstacles).size() == 3, "Existing authored bays clear the real building volume")
	var intruding: Dictionary = sockets[0].duplicate(true)
	intruding.local_bounds = AABB(Vector3(5, 0, 17), Vector3(2, 2, 4))
	intruding.local_position = Vector3(6, 0, 19)
	var broad := Session.new()
	broad.begin(definition, scene_root)
	broad.add("ground", "parking", Rect2i(0, 0, 32, 32))
	check(broad.preview([intruding], 17, 100, obstacles).is_empty() and broad.conflict_count == 1, "A permitted car inside the actual building volume rejects")
	var duplicate: Dictionary = sockets[0].duplicate(true)
	duplicate.socket_id = &"duplicate_bay"
	check(draft.preview([sockets[0], duplicate], 17, 100).size() == 1, "Overlapping occupant candidates cannot both be accepted")
	var union := Session.new()
	union.begin(definition, scene_root)
	union.add("ground", "parking", Rect2i(2, 4, 28, 4))
	union.add("ground", "parking", Rect2i(2, 8, 28, 4))
	check(union.preview(sockets, 17, 100).size() == 3, "Adjacent painted fields combine into one usable permission area")
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
	_check_parking_rows(definition, scene_root, sockets, obstacles, destination)
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
	var motion := InputEventMouseMotion.new()
	motion.position = finish
	panel.handle_input(motion)
	check(panel.overlay.get_child_count() > 0 and panel.session.fields.is_empty(), "Live drag is visible before release without committing history")
	panel.handle_input(event)
	check(panel.session.fields.size() == 1 and Session.rectangle(panel.session.fields[0]) == Rect2i(2, 4, 28, 8), "Camera ray projects mouse drag into exact selected-floor cells")
	panel.density.value = 100
	panel.preview()
	check(panel.status.text.begins_with("3 authored sockets"), "Editor preview uses authored parking sockets")
	panel.reset_preview()
	var vertices: int = panel.overlay.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	panel.session.add("ground", "parking", Rect2i(2, 4, 28, 8))
	panel.refresh()
	check(panel.overlay.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size() == vertices, "Overlapping rectangles render each cell once instead of stacking opacity")
	panel.tool_picker.select(0)
	editor._orbiting = true
	editor._pitch = deg_to_rad(34)
	motion.relative = Vector2(0, 10)
	editor._unhandled_input(motion)
	check(editor._pitch > deg_to_rad(34), "Editor vertical orbit matches the requested inverted battle-camera control")
	editor._orbiting = false
	editor._top_view()
	panel.tool_picker.select(3)
	panel.tool_picker.item_selected.emit(3)
	event.pressed = true
	event.position = editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(13, 0, 10)))
	panel.handle_input(event)
	motion.position = editor.camera.unproject_position(editor.displayed_parcel.to_global(Vector3(24, 0, 10)))
	panel.handle_input(motion)
	check(panel.status.text.contains("4 bays fit") and panel.session.fields.size() == 2, "Live row fit is visible before release")
	event.pressed = false
	event.position = motion.position
	panel.handle_input(event)
	check(panel.session.fields.size() == 3 and panel.session.fields[-1].preset == Session.PARKING_ROW, "Mouse release commits the row draft")
	panel.preview()
	check(panel.status.text.contains("3 authored sockets + 4 row bays occupied"), "100% preview fills four new bays alongside the original three")
	if is_instance_valid(panel._row_preview):
		check(panel._row_preview.get_child_count() == 4, "New bays display four calibrated vehicle scene instances")
		var poses: Array = panel._row_preview.get_children().map(func(node): return [node.position, node.rotation.y, node.get_meta("asset_id")])
		panel.preview()
		check(panel._row_preview.get_children().map(func(node): return [node.position, node.rotation.y, node.get_meta("asset_id")]) == poses, "Same preview seed reproduces model and pose")
	panel.density.value = 0
	panel.preview()
	check(not is_instance_valid(panel._row_preview), "0% occupancy keeps empty outlines without vehicles")
	_check_export(editor)
	editor.free()
	print("Population fields: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_parking_rows(definition, scene_root: Node3D, sockets: Array[Dictionary], obstacles: Array[AABB], destination: String) -> void:
	var rows := Session.new()
	rows.begin(definition, scene_root)
	rows.add("ground", "parking", Rect2i(2, 4, 28, 8))
	var rect := Session.parking_row_rect(Vector2i(13, 10), Vector2i(24, 10), 0)
	check(rect == Rect2i(13, 6, 12, 5), "Aisle-facing drag lays out whole bays behind its edge")
	check(Session.parking_row_rect(Vector2i(24, 10), Vector2i(13, 10), 0) == rect, "Dragging the row backwards preserves bay positions")
	check(Session.parking_row_rect(Vector2i(8, 4), Vector2i(8, 15), 1) == Rect2i(8, 4, 5, 12), "Quarter turn swaps bay dimensions and faces the opposite axis")
	check(rows.add("ground", Session.PARKING_ROW, rect, 0), "Parking row saves a cardinal heading")
	var bays := rows.parking_bays(sockets, obstacles)
	check(bays.size() == 4 and bays.all(func(bay): return bay.reason.is_empty()), "Office gap fits four bays and their aisle")
	check(bays[0].aisle == Rect2i(13, 11, 12, 4), "Aisle stays on the selected side of the row")
	var blocked_aisle := obstacles.duplicate()
	blocked_aisle.append(AABB(Vector3(17, 0, 12), Vector3.ONE))
	check(rows.parking_bays(sockets, blocked_aisle).all(func(bay): return bay.reason.contains("aisle blocked")), "Fixed object inside aisle rejects the row")
	rows.add("ground", "protected", Rect2i(13, 8, 1, 1))
	check(not rows.parking_bays(sockets, obstacles)[0].reason.is_empty(), "Protected cells reject overlapping bay")
	rows.undo()
	check(rows.parking_bays(sockets, obstacles) == bays, "Undo restores the validated bay plan")
	check(rows.save_to(destination), "Parking row draft saves")
	var reloaded := Session.new()
	reloaded.begin(definition, scene_root)
	check(reloaded.load_from(destination) and reloaded.parking_bays(sockets, obstacles) == bays, "JSON reload preserves row direction and exact bay plan")

func _check_export(editor) -> void:
	var panel = editor.field_panel
	var path := "res://.godot/parking_row_export_test.tscn"
	editor._translate_selected(Vector3(0.5, 0, 0))
	check(not panel.export_scene(path) and panel.status.text.contains("source transforms"), "Export rejects an edited visual draft")
	editor._undo()
	panel.session.revision += 1
	check(not panel.export_scene(path) and panel.status.text.contains("revision"), "Export rejects a stale source revision")
	panel.session.revision -= 1
	panel.session.add("ground", "protected", Rect2i(14, 8, 1, 1))
	check(not panel.export_scene(path), "Scene export rejects an unresolved protected bay")
	panel.session.undo()
	panel.session.add("ground", "protected", Rect2i(5, 6, 1, 1))
	check(not panel.export_scene(path) and panel.status.text.contains("original socket"), "Export rejects protected paint crossing an original socket it preserves")
	panel.session.undo()
	var saved: bool = panel.export_scene(path)
	check(saved, "Editor exports its fully validated parking scene: %s" % panel.status.text)
	if not saved: return
	var scene := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	check(scene != null, "Export can be reopened as an ordinary Godot scene")
	if scene == null: return
	var scene_root := scene.instantiate() as Node3D
	var exported := AuthoredParcelDefinition.new(scene_root.get_meta("parcel_id"), "Export", Catalog.URBAN_FRONTAGE, 1, Vector2i(32, 32), scene)
	check(exported.validate().is_empty(), "Reopened scene satisfies existing authored parcel contracts")
	check(exported.parcel_id != editor.displayed_parcel_id and exported.population_sockets().size() == 7, "Export has a separate stable ID and all seven authored sockets even at 0% editor preview")
	var car := scene_root.get_node_or_null("Car_row_bay_ground_13_6") as Node3D
	check(car != null and car.get_node_or_null("Visual") != null and car.get_node_or_null("TacticalVolume") != null, "Export preserves the calibrated imported scene and tactical volume")
	scene_root.free()
	var resolved := Resolver._resolve_population(exported, 18, {}, true, "export-test")
	check(not resolved.has("error") and resolved.choices.any(func(choice): return String(choice.socket_id).begins_with("row_bay_")), "Existing runtime population resolver accepts exported bays")
	var recording := Recording.new()
	recording.configuration = {"content_manifest": {"plot_id": &"export_test", "plot_revision": 1, "map_size": Vector2i(32, 32), "placements": [{"slot_id": &"office", "parcel_id": exported.parcel_id, "parcel_revision": 1, "origin": Vector3i.ZERO, "rotation": 0, "population": resolved.choices}]}}
	var round_trip := Recording.from_dictionary(JSON.parse_string(JSON.stringify(recording.to_dictionary())))
	var exact: Array = round_trip.configuration.content_manifest.placements[0].population
	check(exact == resolved.choices, "Replay JSON preserves exported socket identity and heading")
	var occupied := exported.instantiate()
	var empty := exported.instantiate()
	exported.apply_population(occupied, exact)
	exported.apply_population(empty, [])
	var pose := ParcelTransform.scene_transform(Vector2i(32, 32), Vector3i.ZERO, 0, Vector2i(32, 32))
	occupied.transform = pose
	empty.transform = pose
	var full_map := FlatMapGenerator.generate(32, 32, 1.0, 18)
	var empty_map := FlatMapGenerator.generate(32, 32, 1.0, 18)
	Compiler.compile(occupied, full_map, 1.0)
	Compiler.compile(empty, empty_map, 1.0)
	check(exported.population_sockets(empty).is_empty(), "Population-off removes every exported vehicle")
	var affected := 0
	for position in full_map.cells:
		if not full_map.get_cell(position).can_stop and empty_map.get_cell(position).can_stop: affected += 1
	check(affected > 0 and not empty_map.get_cell(Vector3i(16, 0, 22)).can_stop, "Occupied vehicles affect MapData while population-off retains the fixed building")
	occupied.free()
	empty.free()
	DirAccess.remove_absolute(path)
