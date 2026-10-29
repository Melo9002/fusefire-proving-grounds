class_name MapEditorLayoutStore
extends RefCounted
## Versioned persistence boundary for BattlefieldLayoutDocument.
## Persistence schema 2 wraps the independently versioned construction
## document. Schema 1 is accepted only through an explicit legacy identity.

const SCHEMA_VERSION := 2
const LEGACY_SCHEMA_VERSION := 1
const FORMAT_ID := "fusefire_battlefield_layout"
const DEFAULT_PATH := "res://tools/map_editor/layouts/custom_layout.json"
const STARTER_PATH := "res://tools/map_editor/layouts/starter_layout.json"

static func encode(document: BattlefieldLayoutDocument) -> String:
	return JSON.stringify({
		"schema_version": SCHEMA_VERSION,
		"format": FORMAT_ID,
		"layout_document": document.to_dictionary(),
	}, "\t", false) + "\n"

static func decode(text: String, catalog: Dictionary, legacy_environment_id: StringName = &"", context: EnvironmentResolutionContext = null) -> Dictionary:
	var decoded := GenerationJsonStore.parse(text)
	if not decoded.ok: return _failure(decoded.code, decoded.error)
	var parsed: Dictionary = decoded.value
	var version := int(parsed.get("schema_version", -1))
	if version == LEGACY_SCHEMA_VERSION and parsed.has("map_size") and parsed.has("placements"):
		return _decode_legacy(parsed, catalog, legacy_environment_id)
	if version != SCHEMA_VERSION:
		return _failure("UNSUPPORTED_PERSISTENCE_VERSION", "Unsupported layout persistence schema version: %s" % parsed.get("schema_version", "missing"))
	if parsed.get("format", "") != FORMAT_ID:
		return _failure("UNSUPPORTED_FORMAT", "Layout persistence format is missing or unsupported.")
	var encoded_document = parsed.get("layout_document", null)
	if not encoded_document is Dictionary:
		return _failure("MISSING_LAYOUT_DOCUMENT", "layout_document must contain the unified battlefield document.")
	if context == null: context = EnvironmentResolutionContext.new(catalog)
	var document := BattlefieldLayoutDocument.from_dictionary(encoded_document)
	var failures := document.validate(context.catalog, context)
	if not failures.is_empty():
		return _document_failure(failures)
	var layout := document.to_module_layout(context.catalog)
	if not layout.errors.is_empty():
		return _failure("RECONSTRUCTION_FAILED", "Document placements could not be reconstructed: %s" % layout.errors[0])
	return _success(document, layout, document.map_size(), false, _optional_dependency_warnings(document))

static func save(document: BattlefieldLayoutDocument, path := DEFAULT_PATH, context: EnvironmentResolutionContext = null) -> String:
	var failures := document.validate({}, context)
	if not failures.is_empty():
		return "Cannot save invalid layout document: %s" % _failure_text(failures[0])
	return GenerationJsonStore.write(path, encode(document))

static func load(catalog: Dictionary, path := DEFAULT_PATH, legacy_environment_id: StringName = &"", context: EnvironmentResolutionContext = null) -> Dictionary:
	var result := GenerationJsonStore.read(path)
	if not result.ok: return _failure(result.code, result.error)
	return decode(result.text, catalog, legacy_environment_id, context)

static func _decode_legacy(parsed: Dictionary, catalog: Dictionary, legacy_environment_id: StringName) -> Dictionary:
	var layout_result := _decode_legacy_layout(parsed, catalog)
	if not layout_result.ok:
		return layout_result
	if legacy_environment_id == &"":
		var missing_identity := _failure("LEGACY_ENVIRONMENT_REQUIRED", "Schema-1 layout has no environment identity. Load it with an explicit legacy compatibility identity.")
		missing_identity["legacy_available"] = true
		missing_identity["legacy_layout"] = layout_result.layout
		missing_identity["map_size"] = layout_result.map_size
		return missing_identity
	var document := BattlefieldLayoutDocument.from_authored(
		layout_result.layout,
		layout_result.map_size,
		legacy_environment_id,
		"legacy_%s" % String(layout_result.layout.layout_id)
	)
	document.provenance["legacy_persistence_schema"] = LEGACY_SCHEMA_VERSION
	document.provenance["identity_status"] = "explicit_legacy_compatibility"
	document.presentation["road_presentation_mode"] = "legacy"
	var failures := document.validate(catalog)
	if not failures.is_empty():
		return _document_failure(failures)
	return _success(document, layout_result.layout, layout_result.map_size, true, [
		"Schema-1 layout loaded in explicit legacy compatibility mode; its original environment identity, provenance, relationships, dependencies, and mission zones were not stored.",
	])

static func _decode_legacy_layout(parsed: Dictionary, catalog: Dictionary) -> Dictionary:
	var encoded_size = parsed.get("map_size", [])
	if not encoded_size is Array or encoded_size.size() != 2:
		return _failure("MALFORMED_LEGACY_LAYOUT", "map_size must contain width and depth.")
	var map_size := Vector2i(int(encoded_size[0]), int(encoded_size[1]))
	if map_size.x < 4 or map_size.y < 4:
		return _failure("INVALID_MAP_DIMENSIONS", "Map dimensions must both be at least four cells.")
	var layout := EnvironmentModuleLayout.new(StringName(parsed.get("layout_id", "legacy_layout")), 0)
	var encoded_placements = parsed.get("placements", [])
	if not encoded_placements is Array:
		return _failure("MALFORMED_LEGACY_LAYOUT", "placements must be an array.")
	for index in encoded_placements.size():
		var encoded = encoded_placements[index]
		if not encoded is Dictionary:
			return _failure("MALFORMED_LEGACY_PLACEMENT", "Placement %d must be an object." % index)
		var component_id := StringName(encoded.get("component_id", ""))
		var definition: EnvironmentModuleDefinition = catalog.get(component_id)
		if definition == null:
			return _failure("MISSING_PLACEMENT_REFERENCE", "Placement %d references unknown component '%s'." % [index, component_id])
		var encoded_origin = encoded.get("origin", [])
		if not encoded_origin is Array or encoded_origin.size() != 2:
			return _failure("MALFORMED_LEGACY_PLACEMENT", "Placement %d has an invalid origin." % index)
		var placement := EnvironmentModulePlacement.new(
			component_id,
			Vector2i(int(encoded_origin[0]), int(encoded_origin[1])),
			int(encoded.get("rotation", 0)),
			int(encoded.get("variation", 0)),
			int(encoded.get("elevation", 0))
		)
		if not layout.try_add(definition, placement, map_size):
			return _failure("INVALID_LEGACY_PLACEMENT", "Placement %d is invalid: %s" % [index, layout.errors.back()])
	return {"ok": true, "layout": layout, "map_size": map_size}

static func _optional_dependency_warnings(document: BattlefieldLayoutDocument) -> Array[String]:
	var warnings: Array[String] = []
	for dependency in document.dependencies:
		if not dependency is Dictionary or bool(dependency.get("required", true)):
			continue
		if dependency.get("kind", "") == "asset" and EnvironmentAssemblyContract.current_geometry_sha256(str(dependency.get("id", ""))).is_empty():
			warnings.append("Optional asset '%s' is unavailable; required construction remains intact." % dependency.get("id", ""))
	return warnings

static func _success(document: BattlefieldLayoutDocument, layout: EnvironmentModuleLayout, map_size: Vector2i, legacy: bool, warnings: Array[String]) -> Dictionary:
	return {
		"ok": true,
		"code": "",
		"error": "",
		"document": document,
		"layout": layout,
		"map_size": map_size,
		"legacy": legacy,
		"warnings": warnings,
	}

static func _document_failure(failures: Array[Dictionary]) -> Dictionary:
	var first: Dictionary = failures[0]
	var result := _failure(str(first.get("code", "INVALID_LAYOUT_DOCUMENT")), _failure_text(first))
	result["failures"] = failures
	return result

static func _failure_text(failure: Dictionary) -> String:
	var source_reference := str(failure.get("reference", ""))
	return "%s%s: %s" % [failure.get("field", "document"), " [%s]" % source_reference if not source_reference.is_empty() else "", failure.get("message", "invalid")]

static func _failure(code: String, message: String) -> Dictionary:
	return {
		"ok": false,
		"code": code,
		"error": message,
		"document": null,
		"layout": null,
		"map_size": Vector2i.ZERO,
		"legacy": false,
		"warnings": [],
		"failures": [],
	}
