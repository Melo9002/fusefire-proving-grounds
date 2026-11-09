class_name ParcelDraftSession
extends RefCounted
## Small, editor-only transform draft for visual nodes already authored in a
## registered parcel. Drafts never modify the source scene or tactical metadata.

const Library = preload("res://tools/parcel_editor/parcel_placement_library.gd")
const SCHEMA_VERSION := 2
const DRAFT_DIRECTORY := "user://parcel_drafts"

var parcel_id: StringName = &""
var parcel_revision := 0
var parcel_size := Vector2i.ZERO
var placements: Array[Dictionary] = []
var base_placements: Array[Dictionary] = []
var selected_path := ""
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var last_error := ""
var dirty: bool:
	get: return placements != _saved_placements
var _saved_placements: Array[Dictionary] = []

func begin(definition, root: Node3D) -> void:
	parcel_id = definition.parcel_id
	parcel_revision = definition.revision
	parcel_size = definition.size
	placements.clear()
	_collect(root, root)
	placements.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.path) < String(b.path))
	base_placements = placements.duplicate(true)
	selected_path = String(placements[0].path) if not placements.is_empty() else ""
	undo_stack.clear()
	redo_stack.clear()
	last_error = ""
	_saved_placements = base_placements.duplicate(true)

func _collect(root: Node3D, node: Node) -> void:
	if node is Node3D and node.has_meta("asset_id"):
		var spatial := node as Node3D
		placements.append({
			"path": String(root.get_path_to(node)),
			"asset_id": String(node.get_meta("asset_id", "")),
			"position": _vector3_record(spatial.position),
			"rotation_degrees": _vector3_record(spatial.rotation_degrees),
			"scale": _vector3_record(spatial.scale),
		})
	for child in node.get_children():
		_collect(root, child)

func placement(path: String = selected_path) -> Dictionary:
	for record: Dictionary in placements:
		if String(record.path) == path:
			return record
	return {}

func select(path: String) -> bool:
	var record := placement(path)
	if record.is_empty() or record.get("removed", false):
		return false
	selected_path = path
	return true

func add_fixed(node: Node3D) -> void:
	undo_stack.append(_snapshot())
	redo_stack.clear()
	var index := 1
	while not placement("DraftAsset%d" % index).is_empty():
		index += 1
	selected_path = "DraftAsset%d" % index
	placements.append({"path": selected_path, "asset_id": String(node.get_meta("asset_id")),
		"position": _vector3_record(node.position), "rotation_degrees": _vector3_record(node.rotation_degrees),
		"scale": _vector3_record(node.scale), "added": true})

func remove_fixed(root: Node3D) -> bool:
	var index := _placement_index(selected_path)
	var node := root.get_node_or_null(NodePath(selected_path)) if index >= 0 else null
	if node == null or node.has_meta("population_socket_id") or node.get_parent() != root:
		return false
	if not node.find_children("*", "Node3D", true, false).filter(func(child): return child.has_meta("asset_id")).is_empty():
		return false
	undo_stack.append(_snapshot())
	redo_stack.clear()
	if placements[index].get("added", false):
		placements.remove_at(index)
	else:
		placements[index]["removed"] = true
	selected_path = ""
	return true

func translate_selected(delta: Vector3) -> bool:
	return _edit_selected(func(record: Dictionary): record.position = _vector3_record(_record_vector3(record.position) + delta))

func place_selected(position: Vector3, yaw: float) -> bool:
	return _edit_selected(func(record: Dictionary):
		record.position = _vector3_record(position)
		record.rotation_degrees[1] = yaw)

func rotate_selected_quarter(turns: int) -> bool:
	return _edit_selected(func(record: Dictionary):
		var rotation := _record_vector3(record.rotation_degrees)
		rotation.y = snappedf(rotation.y + turns * 90.0, 90.0)
		record.rotation_degrees = _vector3_record(rotation)
	)

func reset_selected(_root: Node3D) -> bool:
	var original := _placement_in(base_placements, selected_path)
	if original.is_empty():
		last_error = "MISSING_SOURCE_NODE"
		return false
	return _edit_selected(func(record: Dictionary):
		record.position = original.position.duplicate()
		record.rotation_degrees = original.rotation_degrees.duplicate()
		record.scale = original.scale.duplicate()
	)

func _edit_selected(editor: Callable) -> bool:
	if selected_path.is_empty():
		last_error = "NO_SELECTION"
		return false
	var index := _placement_index(selected_path)
	if index < 0:
		last_error = "MISSING_PLACEMENT"
		return false
	var record: Dictionary = placements[index].duplicate(true)
	editor.call(record)
	if record == placements[index]:
		return false
	undo_stack.append(_snapshot())
	redo_stack.clear()
	placements[index] = record
	last_error = ""
	return true

func undo() -> bool:
	if undo_stack.is_empty():
		return false
	redo_stack.append(_snapshot())
	_restore_snapshot(undo_stack.pop_back())
	return true

func redo() -> bool:
	if redo_stack.is_empty():
		return false
	undo_stack.append(_snapshot())
	_restore_snapshot(redo_stack.pop_back())
	return true

func apply(root: Node3D) -> PackedStringArray:
	var failures := PackedStringArray()
	for child in root.get_children():
		if child.has_meta("draft_added") and (placement(String(child.name)).get("asset_id") != child.get_meta("asset_id")):
			child.free()
	for original in base_placements:
		var original_node := root.get_node_or_null(NodePath(String(original.path))) as Node3D
		if original_node and original_node.has_meta("draft_removed"):
			original_node.show()
			original_node.remove_meta("draft_removed")
	for record: Dictionary in placements:
		var node := root.get_node_or_null(NodePath(String(record.path))) as Node3D
		if node == null and record.get("added", false):
			node = Library.create(record.asset_id)
			if node:
				node.name = record.path
				node.set_meta("draft_added", true)
				root.add_child(node)
		if node == null:
			failures.append("MISSING_SOURCE_NODE: %s" % record.path)
			continue
		if String(node.get_meta("asset_id", "")) != String(record.asset_id):
			failures.append("ASSET_ID_MISMATCH: %s" % record.path)
			continue
		node.position = _record_vector3(record.position)
		node.rotation_degrees = _record_vector3(record.rotation_degrees)
		node.scale = _record_vector3(record.scale)
		if record.get("removed", false):
			node.hide()
			node.set_meta("draft_removed", true)
	return failures

func save() -> bool:
	return save_to(draft_path())

func save_to(path: String) -> bool:
	var directory := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		var error := DirAccess.make_dir_recursive_absolute(directory)
		if error != OK:
			last_error = "CREATE_DRAFT_DIRECTORY_FAILED: %s" % error_string(error)
			return false
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_error = "OPEN_DRAFT_FAILED: %s" % error_string(FileAccess.get_open_error())
		return false
	file.store_string(JSON.stringify(to_record(), "\t"))
	file.close()
	_saved_placements = placements.duplicate(true)
	last_error = ""
	return true

func load_for(definition, root: Node3D) -> bool:
	return load_from(_draft_path_for(definition.parcel_id), definition, root)

func load_from(path: String, definition, root: Node3D) -> bool:
	if not FileAccess.file_exists(path):
		last_error = "DRAFT_NOT_FOUND"
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		last_error = "MALFORMED_DRAFT"
		return false
	var failures := validate_record(parsed, definition, root)
	if not failures.is_empty():
		last_error = "; ".join(failures)
		return false
	parcel_id = StringName(parsed.base_parcel_id)
	parcel_revision = int(parsed.parcel_revision)
	parcel_size = Vector2i(int(parsed.parcel_size[0]), int(parsed.parcel_size[1]))
	placements.assign(parsed.placements.map(func(value): return (value as Dictionary).duplicate(true)))
	if base_placements.is_empty():
		_collect_into(root, root, base_placements)
		base_placements.sort_custom(func(a: Dictionary, b: Dictionary): return String(a.path) < String(b.path))
	var visible_records := placements.filter(func(item): return not item.get("removed", false))
	selected_path = String(visible_records[0].path) if not visible_records.is_empty() else ""
	undo_stack.clear()
	redo_stack.clear()
	_saved_placements = placements.duplicate(true)
	last_error = ""
	return true

func to_record() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"base_parcel_id": String(parcel_id),
		"parcel_revision": parcel_revision,
		"parcel_size": [parcel_size.x, parcel_size.y],
		"placements": placements.duplicate(true),
	}

func validate_record(record: Dictionary, definition, root: Node3D) -> PackedStringArray:
	var failures := PackedStringArray()
	var schema := int(record.get("schema_version", 0))
	if schema not in [1, SCHEMA_VERSION]:
		failures.append("UNSUPPORTED_DRAFT_VERSION")
	if StringName(record.get("base_parcel_id", &"")) != definition.parcel_id:
		failures.append("PARCEL_ID_MISMATCH")
	if int(record.get("parcel_revision", 0)) != definition.revision:
		failures.append("STALE_PARCEL_REVISION")
	var size = record.get("parcel_size", [])
	if not size is Array or size.size() != 2 or Vector2i(int(size[0]), int(size[1])) != definition.size:
		failures.append("PARCEL_SIZE_MISMATCH")
	var records = record.get("placements", null)
	if not records is Array:
		failures.append("MALFORMED_PLACEMENTS")
		return failures
	var seen := {}
	var library := Library.entries() if schema == SCHEMA_VERSION else {}
	for value in records:
		if not value is Dictionary:
			failures.append("MALFORMED_PLACEMENT")
			continue
		var path := String(value.get("path", ""))
		if path.is_empty() or seen.has(path):
			failures.append("INVALID_PLACEMENT_PATH")
			continue
		seen[path] = true
		var node := root.get_node_or_null(NodePath(path))
		if value.get("added", false):
			if schema != SCHEMA_VERSION or not path.begins_with("DraftAsset") or not path.trim_prefix("DraftAsset").is_valid_int() or not library.has(value.get("asset_id")) or value.get("removed", false) or (node != null and not node.has_meta("draft_added")):
				failures.append("INVALID_DRAFT_ASSET: %s" % path)
		elif node == null or node.has_meta("draft_added"):
			failures.append("MISSING_SOURCE_NODE: %s" % path)
		elif String(node.get_meta("asset_id", "")) != String(value.get("asset_id", "")):
			failures.append("ASSET_ID_MISMATCH: %s" % path)
		elif value.get("removed", false) and (schema != SCHEMA_VERSION or node.get_parent() != root or node.has_meta("population_socket_id")):
			failures.append("INVALID_DRAFT_REMOVAL: %s" % path)
		for field in ["position", "rotation_degrees", "scale"]:
			var vector = value.get(field, null)
			if not vector is Array or vector.size() != 3 or not vector.all(func(component): return (component is float or component is int) and is_finite(float(component))):
				failures.append("MALFORMED_TRANSFORM: %s.%s" % [path, field])
	return failures

func draft_path() -> String:
	return _draft_path_for(parcel_id)

static func _draft_path_for(id: StringName) -> String:
	return "%s/%s.draft.json" % [DRAFT_DIRECTORY, String(id)]

func _placement_index(path: String) -> int:
	for index in placements.size():
		if String(placements[index].path) == path:
			return index
	return -1

func _placement_in(records: Array[Dictionary], path: String) -> Dictionary:
	for record: Dictionary in records:
		if String(record.path) == path:
			return record
	return {}

func _collect_into(root: Node3D, node: Node, target: Array[Dictionary]) -> void:
	if node is Node3D and node.has_meta("asset_id"):
		var spatial := node as Node3D
		target.append({
			"path": String(root.get_path_to(node)),
			"asset_id": String(node.get_meta("asset_id", "")),
			"position": _vector3_record(spatial.position),
			"rotation_degrees": _vector3_record(spatial.rotation_degrees),
			"scale": _vector3_record(spatial.scale),
		})
	for child in node.get_children():
		_collect_into(root, child, target)

func _snapshot() -> Dictionary:
	return {"placements": placements.duplicate(true), "selected_path": selected_path}

func _restore_snapshot(snapshot: Dictionary) -> void:
	placements.assign(snapshot.placements.duplicate(true))
	selected_path = String(snapshot.selected_path)

static func _vector3_record(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

static func _record_vector3(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))
