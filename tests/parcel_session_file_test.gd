extends SceneTree
const Files = preload("res://tools/parcel_editor/parcel_session_file.gd")
const Objects = preload("res://tools/parcel_editor/parcel_draft_session.gd")
const Fields = preload("res://tools/parcel_editor/population_field_draft.gd")
const Catalog = preload("res://systems/generation2/authored_parcel_catalog.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var definition = Catalog.get_definition(Catalog.LOADING_YARD_A)
	var root_node: Node3D = definition.instantiate()
	var objects := Objects.new()
	objects.begin(definition, root_node)
	var piece := Objects.Library.create("factory_kit/box-small")
	piece.position = Vector3(8, 0, 22)
	objects.add_fixed(piece)
	piece.free()
	var fields := Fields.new()
	fields.begin(definition, root_node)
	fields.add("ground", "containers", Rect2i(7, 25, 3, 5))
	fields.preview_seed = 18
	fields.occupancy = 42
	var destination := "res://.godot/whole_parcel_test.json"
	check(Files.save_to(destination, objects, fields).is_empty(), "One save stores both draft payloads")
	check(not objects.dirty and not fields.is_dirty(), "Both drafts become saved only after the file succeeds")
	var loaded := Files.open_file(destination)
	check(not loaded.has("error"), "Reopen the complete parcel: %s" % loaded.get("error", ""))
	if not loaded.has("error"):
		check(loaded.objects.placements == objects.placements and loaded.population.fields == fields.fields, "Both edits survive the same file round trip")
		check(loaded.population.preview_seed == 18 and loaded.population.occupancy == 42, "Seed and occupancy are part of the session")
		check(loaded.objects.active_path.is_empty() and loaded.population.active_path.is_empty(), "Legacy save commands cannot overwrite the complete session file")
	objects.translate_selected(Vector3.RIGHT)
	check(Files.save_to(destination, objects, fields).is_empty(), "A subsequent save atomically replaces the existing complete file")
	var saved := FileAccess.get_file_as_string(destination)
	var record: Dictionary = JSON.parse_string(saved)
	record.population.revision += 1
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(record))
	file.close()
	check(Files.open_file(destination).get("error", "").contains("Incompatible"), "A stale field payload rejects the complete open, not half a session")
	objects.translate_selected(Vector3.RIGHT)
	fields.add("ground", "protected", Rect2i(1, 1, 1, 1))
	var blocked := "res://.godot/session_save_directory"
	DirAccess.make_dir_recursive_absolute(blocked)
	check(not Files.save_to(blocked, objects, fields).is_empty() and objects.dirty and fields.is_dirty(), "A failed replacement leaves both drafts unsaved")
	DirAccess.remove_absolute(blocked)
	DirAccess.remove_absolute(destination)
	root_node.free()
	print("Parcel session file: %d failure(s)" % failures)
	quit(1 if failures else 0)
