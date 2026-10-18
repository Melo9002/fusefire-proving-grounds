class_name MapEditorLayoutStore
extends RefCounted

const SCHEMA_VERSION := 1
const DEFAULT_PATH := "res://tools/map_editor/layouts/custom_layout.json"
const STARTER_PATH := "res://tools/map_editor/layouts/starter_layout.json"

static func encode(layout: EnvironmentModuleLayout, map_size: Vector2i) -> String:
	var placements: Array[Dictionary] = []
	for placement in layout.placements:
		placements.append({
			"component_id": String(placement.component_id),
			"origin": [placement.origin.x, placement.origin.y],
			"rotation": placement.rotation,
			"variation": placement.variation,
			"elevation": placement.elevation,
		})
	return JSON.stringify({
		"schema_version": SCHEMA_VERSION,
		"layout_id": String(layout.layout_id),
		"map_size": [map_size.x, map_size.y],
		"placements": placements,
	}, "\t", false) + "\n"

static func decode(text: String, catalog: Dictionary) -> Dictionary:
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary:
		return _failure("Layout JSON must contain an object.")
	if int(parsed.get("schema_version", -1)) != SCHEMA_VERSION:
		return _failure("Unsupported layout schema version: %s" % parsed.get("schema_version", "missing"))
	var encoded_size = parsed.get("map_size", [])
	if not encoded_size is Array or encoded_size.size() != 2:
		return _failure("map_size must contain width and depth.")
	var map_size := Vector2i(int(encoded_size[0]), int(encoded_size[1]))
	if map_size.x < 4 or map_size.y < 4:
		return _failure("Map dimensions must both be at least four cells.")
	var layout := EnvironmentModuleLayout.new(StringName(parsed.get("layout_id", "custom_layout")), 0)
	var encoded_placements = parsed.get("placements", [])
	if not encoded_placements is Array:
		return _failure("placements must be an array.")
	for index in encoded_placements.size():
		var encoded = encoded_placements[index]
		if not encoded is Dictionary:
			return _failure("Placement %d must be an object." % index)
		var component_id := StringName(encoded.get("component_id", ""))
		var definition: EnvironmentModuleDefinition = catalog.get(component_id)
		if definition == null:
			return _failure("Placement %d references unknown component '%s'." % [index, component_id])
		var encoded_origin = encoded.get("origin", [])
		if not encoded_origin is Array or encoded_origin.size() != 2:
			return _failure("Placement %d has an invalid origin." % index)
		var placement := EnvironmentModulePlacement.new(
			component_id,
			Vector2i(int(encoded_origin[0]), int(encoded_origin[1])),
			int(encoded.get("rotation", 0)),
			int(encoded.get("variation", 0)),
			int(encoded.get("elevation", 0))
		)
		if not layout.try_add(definition, placement, map_size):
			return _failure("Placement %d is invalid: %s" % [index, layout.errors.back()])
	return {"ok": true, "error": "", "layout": layout, "map_size": map_size}

static func save(layout: EnvironmentModuleLayout, map_size: Vector2i, path := DEFAULT_PATH) -> String:
	var absolute := ProjectSettings.globalize_path(path)
	var directory := absolute.get_base_dir()
	var directory_error := DirAccess.make_dir_recursive_absolute(directory)
	if directory_error != OK:
		return "Could not create layout directory: %s" % error_string(directory_error)
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return "Could not open layout for writing: %s" % error_string(FileAccess.get_open_error())
	file.store_string(encode(layout, map_size))
	file.close()
	return ""

static func load(catalog: Dictionary, path := DEFAULT_PATH) -> Dictionary:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return _failure("No saved layout exists at %s." % path)
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		return _failure("Could not open layout: %s" % error_string(FileAccess.get_open_error()))
	var text := file.get_as_text()
	file.close()
	return decode(text, catalog)

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message, "layout": null, "map_size": Vector2i.ZERO}
