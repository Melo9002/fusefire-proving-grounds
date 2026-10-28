class_name ChunkSourceStore
extends RefCounted
const DEFAULT_DIRECTORY := "res://tools/map_editor/chunks/drafts"
const Source = preload("res://systems/generation/environment_chunk_source.gd")
const JsonStore = preload("res://systems/generation/generation_json_store.gd")

static func encode(source: EnvironmentChunkSource) -> String:
	return JSON.stringify(source.to_dictionary(), "\t", false) + "\n"

static func decode(text: String) -> Dictionary:
	var parsed := JsonStore.parse(text)
	if not parsed.ok: return _failure(parsed.code, parsed.error)
	var errors := Source.source_errors(parsed.value)
	if not errors.is_empty(): return _failure(errors[0].code, errors[0].message, errors)
	var source := Source.new()
	source.data = parsed.value.duplicate(true)
	return {"ok": true, "source": source, "state": "draft", "diagnostics": [], "error": ""}

static func path_for(directory: String, draft_name: String) -> String:
	# A named draft is one file within the selected directory, never a path.
	if draft_name.is_empty() or draft_name != draft_name.strip_edges() or not draft_name.is_valid_filename() or draft_name in [".", ".."] or draft_name.ends_with("."): return ""
	var stem := draft_name.get_basename() if draft_name.ends_with(".json") else draft_name
	if stem.to_upper() in ["CON", "PRN", "AUX", "NUL", "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9", "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"]: return ""
	return directory.path_join(stem + ".json")

static func save_named(source: EnvironmentChunkSource, directory: String, draft_name: String) -> Dictionary:
	var path := path_for(directory, draft_name)
	if path.is_empty(): return _failure("INVALID_DRAFT_NAME", "Choose a single valid filename")
	var errors := Source.source_errors(source.to_dictionary())
	if not errors.is_empty(): return _failure(errors[0].code, errors[0].message, errors)
	var error := JsonStore.write(path, encode(source))
	if not error.is_empty(): return _failure("WRITE_FAILED", error)
	return {"ok": true, "path": path, "state": "draft", "error": ""}

static func load_named(directory: String, draft_name: String) -> Dictionary:
	var path := path_for(directory, draft_name)
	if path.is_empty(): return _failure("INVALID_DRAFT_NAME", "Choose a single valid filename")
	var read := JsonStore.read(path)
	if not read.ok: return _failure(read.code, read.error)
	var result := decode(read.text)
	result["path"] = path
	return result

## Explicit conversion, never called by normal decode/load; caller saves a new
## named file only after inspecting diagnostics. Input files are never written.
static func import_legacy(text: String, chunk_id: String, label: String) -> Dictionary:
	var parsed := JsonStore.parse(text)
	if not parsed.ok: return _failure(parsed.code, parsed.error)
	var value: Dictionary = parsed.value
	var old_placements := false
	var diagnostics: Array[String] = []
	if value.get("format", "") == "fusefire_battlefield_layout":
		if not Source._integer(value.get("schema_version")) or value.schema_version != 2: return _failure("UNSUPPORTED_LEGACY_VERSION", "Unsupported map-store version")
		if not value.get("layout_document") is Dictionary: return _failure("MALFORMED_LEGACY_SOURCE", "Missing layout_document")
		value = value.layout_document
	if not Source._integer(value.get("schema_version")) or value.schema_version != 1: return _failure("UNSUPPORTED_LEGACY_VERSION", "Only explicit schema-1 layout/document import is supported")
	var spatial: Dictionary
	if value.has("map_size") and value.has("placements"):
		spatial = value
		old_placements = true
		diagnostics.append("Legacy dependency history is absent; existing IDs retained and missing IDs assigned deterministically. Dependencies remain unpinned.")
	elif value.get("spatial_layout") is Dictionary:
		spatial = value.spatial_layout
	else: return _failure("MALFORMED_LEGACY_SOURCE", "No recognized local placement source")
	if not Source._vector(spatial.get("map_size"), 2) or not spatial.get("placements") is Array: return _failure("MALFORMED_LEGACY_SOURCE", "Invalid map size or placements")
	if spatial.has("next_placement_id") and not Source._integer(spatial.next_placement_id): return _failure("MALFORMED_LEGACY_SOURCE", "Invalid placement counter")
	var source := Source.new(chunk_id, label)
	source.data.bounds = spatial.map_size.duplicate()
	source.data.rotations = [0]
	var placements: Array = []
	var occupied_ids := {}
	for record in spatial.placements:
		if record is Dictionary and record.get("placement_id") is String and not record.placement_id.is_empty(): occupied_ids[record.placement_id] = true
	for record in spatial.placements:
		if not record is Dictionary: return _failure("MALFORMED_LEGACY_SOURCE", "Invalid placement")
		var encoded := {}
		for key in ["placement_id", "component_id", "origin", "rotation", "variation", "elevation"]:
			if record.has(key): encoded[key] = record[key]
			elif old_placements:
				if key in ["placement_id", "component_id"]: encoded[key] = ""
				elif key == "origin": encoded[key] = []
				else: encoded[key] = 0
		if old_placements and encoded.get("placement_id", "") == "":
			var legacy_id := "legacy_%04d" % placements.size()
			while occupied_ids.has(legacy_id): legacy_id += "_import"
			encoded.placement_id = legacy_id
			occupied_ids[legacy_id] = true
		source.data.instances.append(encoded)
		# Validate before numeric conversion; no truncation/normalization of bad transforms.
		var placement_errors := Source.source_errors(source.data)
		if not placement_errors.is_empty(): return _failure("MALFORMED_LEGACY_SOURCE", placement_errors[0].message, placement_errors)
		placements.append(EnvironmentModulePlacement.from_record(encoded))
		source.data.height = maxi(int(source.data.height), int(encoded.elevation) + 1)
		source.data.tactical.components.append(encoded.placement_id)
	source.data.next_placement_id = EnvironmentModulePlacement.ensure_identities(placements, int(spatial.get("next_placement_id", 1)))
	if not old_placements:
		if not value.get("dependencies", []) is Array: return _failure("MALFORMED_LEGACY_SOURCE", "Invalid dependency list")
		source.data.dependencies = value.get("dependencies", []).duplicate(true)
		diagnostics.append("Existing dependency pins retained without refresh; stale references remain draft diagnostics.")
	diagnostics.append("World mission/deployment binding, parcel ownership and battlefield relationships were not imported. Ports and clearances require local authoring.")
	diagnostics.append("Map origin retained as chunk-local zero; height is a provisional minimum. Review allocation and vertical bounds. Only rotation 0 is enabled.")
	diagnostics.append("Imported as a draft only: no technical certification, visual approval or generator registration granted.")
	source.data.provenance = {"origin": "legacy_import", "source_sha256": text.sha256_text(), "diagnostics": diagnostics.duplicate()}
	var errors := Source.source_errors(source.data)
	if not errors.is_empty(): return _failure("MALFORMED_LEGACY_SOURCE", errors[0].message, errors)
	return {"ok": true, "source": source, "state": "draft", "diagnostics": diagnostics, "error": ""}

static func _failure(code: String, message: String, diagnostics: Array = []) -> Dictionary:
	return {"ok": false, "source": null, "code": code, "error": message, "diagnostics": diagnostics}
