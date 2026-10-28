class_name EnvironmentChunkSource
extends RefCounted
## Mutable local authoring source. Saving is not validation/publication approval.
const VERSION := 1
const FORMAT := "fusefire_chunk_source"
const KEYS := ["format", "schema_version", "chunk_id", "name", "bounds", "height", "rotations", "next_placement_id", "instances", "ports", "clearances", "tactical", "dependencies", "provenance"]
var data: Dictionary

func _init(id := "untitled", label := "Untitled") -> void:
	data = {"format": FORMAT, "schema_version": VERSION, "chunk_id": id, "name": label, "bounds": [1, 1], "height": 1, "rotations": [0, 1, 2, 3], "next_placement_id": 1, "instances": [], "ports": [], "clearances": [], "tactical": {"components": [], "surfaces": [], "effects": [], "links": []}, "dependencies": [], "provenance": {"origin": "authored"}}

func to_dictionary() -> Dictionary: return data.duplicate(true)
func copy() -> EnvironmentChunkSource:
	var result := EnvironmentChunkSource.new()
	result.data = to_dictionary()
	return result

func add_instance(placement: EnvironmentModulePlacement, contributes_tactically := true) -> String:
	var instances: Array = []
	for record in data.instances: instances.append(EnvironmentModulePlacement.from_record(record))
	var added := placement.copy()
	# Adding an existing object describes a copy, not a second owner of its ID.
	added.placement_id = ""
	instances.append(added)
	data.next_placement_id = EnvironmentModulePlacement.ensure_identities(instances, int(data.next_placement_id))
	data.instances.append(added.to_record())
	if contributes_tactically: data.tactical.components.append(added.placement_id)
	return added.placement_id

static func source_errors(value: Dictionary) -> Array[Dictionary]:
	var errors: Array[Dictionary] = []
	if not _json_value(value):
		_error(errors, "NON_JSON_SOURCE", "source", "Source must contain only finite JSON values and string keys")
		return errors
	for key in KEYS:
		if not value.has(key): _error(errors, "MISSING_FIELD", key, "Required source field is missing")
	for key in value:
		if key not in KEYS: _error(errors, "UNSUPPORTED_FIELD", str(key), "Not a chunk source field (mission/publication state belongs elsewhere)")
	if not errors.is_empty(): return errors
	if value.format != FORMAT: _error(errors, "UNSUPPORTED_FORMAT", "format", "Expected chunk source format")
	if not _integer(value.schema_version) or value.schema_version != VERSION: _error(errors, "UNSUPPORTED_SOURCE_VERSION", "schema_version", "Unsupported chunk source version")
	for key in ["chunk_id", "name"]:
		if not value[key] is String or str(value[key]).strip_edges().is_empty(): _error(errors, "INVALID_IDENTITY", key, "Expected nonempty text")
	if not _vector(value.bounds, 2) or (value.bounds is Array and value.bounds.size() == 2 and (float(value.bounds[0]) <= 0 or float(value.bounds[1]) <= 0)): _error(errors, "INVALID_BOUNDS", "bounds", "Expected positive integer width/depth")
	if not _integer(value.height) or float(value.height) <= 0: _error(errors, "INVALID_HEIGHT", "height", "Expected positive integer vertical extent")
	if not _integer(value.next_placement_id) or float(value.next_placement_id) < 0: _error(errors, "INVALID_COUNTER", "next_placement_id", "Expected nonnegative integer counter")
	for key in ["rotations", "instances", "ports", "clearances", "dependencies"]:
		if not value[key] is Array: _error(errors, "INVALID_ARRAY", key, "Expected array")
	if not value.tactical is Dictionary or not value.provenance is Dictionary: _error(errors, "INVALID_OBJECT", "source", "Tactical and provenance fields must be objects")
	if not errors.is_empty(): return errors
	for rotation in value.rotations:
		if not _integer(rotation) or int(rotation) not in [0, 1, 2, 3]: _error(errors, "INVALID_ROTATION", "rotations", "Expected quarter turns 0..3")
	var ids := {}
	for item in value.instances:
		if not _fields(item, {"placement_id": TYPE_STRING, "component_id": TYPE_STRING, "origin": TYPE_ARRAY, "rotation": TYPE_NIL, "variation": TYPE_NIL, "elevation": TYPE_NIL}, errors, "instances"): continue
		_identity(item.placement_id, ids, errors, "instances")
		if not _vector(item.origin, 2): _error(errors, "INVALID_TRANSFORM", "instances.origin", "Expected two integer coordinates")
		for key in ["rotation", "variation", "elevation"]:
			if not _integer(item[key]) or float(item[key]) < 0: _error(errors, "INVALID_TRANSFORM", "instances." + key, "Expected nonnegative integer")
		if not _integer(item.rotation) or int(item.rotation) not in [0, 1, 2, 3]: _error(errors, "INVALID_ROTATION", "instances.rotation", "Expected quarter turns 0..3")
	var port_ids := {}
	for port in value.ports:
		if not _fields(port, {"id": TYPE_STRING, "role": TYPE_STRING, "profile": TYPE_STRING, "cells": TYPE_ARRAY, "normal": TYPE_ARRAY, "elevation": TYPE_NIL, "minimum_width": TYPE_NIL, "connection": TYPE_STRING}, errors, "ports"): continue
		_identity(port.id, port_ids, errors, "ports")
		if not _vector(port.normal, 2) or (absi(int(port.normal[0])) + absi(int(port.normal[1]))) != 1: _error(errors, "INVALID_PORT_NORMAL", "ports.normal", "Expected cardinal outward normal")
		if not _integer(port.elevation) or float(port.elevation) < 0 or not _integer(port.minimum_width) or float(port.minimum_width) < 1: _error(errors, "INVALID_PORT_EXTENT", "ports", "Expected nonnegative elevation and positive width")
		if port.connection not in ["required", "optional", "terminated"]: _error(errors, "INVALID_PORT_CONNECTION", "ports.connection", "Expected required, optional or terminated")
		for cell in port.cells:
			if not _vector(cell, 2): _error(errors, "INVALID_CELL", "ports.cells", "Expected integer X/Z cells")
	var clearance_ids := {}
	for region in value.clearances:
		if not _fields(region, {"id": TYPE_STRING, "cells": TYPE_ARRAY, "height": TYPE_NIL, "scope": TYPE_STRING}, errors, "clearances"): continue
		_identity(region.id, clearance_ids, errors, "clearances")
		if not _number(region.height) or float(region.height) <= 0 or region.scope not in ["floor", "whole_column"]: _error(errors, "INVALID_CLEARANCE", "clearances", "Invalid clearance height/scope")
		for cell in region.cells:
			if not _vector(cell, 3): _error(errors, "INVALID_CELL", "clearances.cells", "Expected integer X/Y/Z cells")
	var tactical_fields := {"components": TYPE_ARRAY, "surfaces": TYPE_ARRAY, "effects": TYPE_ARRAY, "links": TYPE_ARRAY}
	if value.tactical.has("visual_only"): tactical_fields["visual_only"] = TYPE_ARRAY
	if _fields(value.tactical, tactical_fields, errors, "tactical"):
		for id in value.tactical.get("visual_only", []):
			if not id is String: _error(errors, "INVALID_REFERENCE", "tactical.visual_only", "Expected placement ID")
		for id in value.tactical.components:
			if not id is String: _error(errors, "INVALID_REFERENCE", "tactical.components", "Expected placement ID")
		for kind in ["surfaces", "effects"]:
			for contribution in value.tactical[kind]:
				var fields := {"cell": TYPE_ARRAY, "values": TYPE_DICTIONARY}
				if kind == "effects": fields["layer"] = TYPE_NIL
				if not _fields(contribution, fields, errors, "tactical." + kind): continue
				if not _vector(contribution.cell, 3): _error(errors, "INVALID_CELL", "tactical." + kind, "Expected integer X/Y/Z cell")
				if kind == "effects" and (not _integer(contribution.layer) or int(contribution.layer) not in [0, 1, 2]): _error(errors, "INVALID_LAYER", "tactical.effects", "Expected ground/occupant/overhead layer")
				for key in contribution.values:
					var field_value = contribution.values[key]
					if key not in EnvironmentModuleMapWriter.FIELDS: _error(errors, "UNKNOWN_EFFECT", "tactical." + kind, str(key))
					elif key in ["walkable", "can_stop", "blocks_los"]:
						if not field_value is bool: _error(errors, "INVALID_EFFECT", str(key), "Expected boolean")
					elif not _number(field_value): _error(errors, "INVALID_EFFECT", str(key), "Expected finite number")
					elif key == "cover_type" and (not _integer(field_value) or int(field_value) not in [0, 1, 2]): _error(errors, "INVALID_EFFECT", str(key), "Expected cover enum 0..2")
					elif key == "movement_cost" and (not _integer(field_value) or float(field_value) < 1): _error(errors, "INVALID_EFFECT", str(key), "Expected positive integer cost")
					elif key == "cover_height" and float(field_value) < 0: _error(errors, "INVALID_EFFECT", str(key), "Expected nonnegative height")
		for link in value.tactical.links:
			if not _fields(link, {"from": TYPE_ARRAY, "to": TYPE_ARRAY, "kind": TYPE_NIL, "bidirectional": TYPE_BOOL}, errors, "tactical.links"): continue
			if not _vector(link.from, 3) or not _vector(link.to, 3) or not _integer(link.kind) or int(link.kind) not in GeneratedTraversalData.Kind.values(): _error(errors, "INVALID_LINK", "tactical.links", "Expected integer endpoints and traversal kind")
	var dependencies := {}
	for dependency in value.dependencies:
		if not dependency is Dictionary or not dependency.get("kind") is String or not dependency.get("id") is String:
			_error(errors, "INVALID_DEPENDENCY", "dependencies", "Expected kind/id text")
			continue
		_identity(dependency.kind + ":" + dependency.id, dependencies, errors, "dependencies")
		for key in ["revision", "geometry_sha256", "calibration_signature", "semantic_signature", "certification_signature", "legacy_signature"]:
			if dependency.has(key) and not dependency[key] is String: _error(errors, "INVALID_DEPENDENCY", "dependencies." + key, "Revision pins must be strings")
		if dependency.has("required_by"):
			if not dependency.required_by is Array: _error(errors, "INVALID_DEPENDENCY", "dependencies.required_by", "Expected reference array")
			else:
				for id in dependency.required_by:
					if not id is String: _error(errors, "INVALID_DEPENDENCY", "dependencies.required_by", "Expected string reference")
	return errors

## This is draft diagnostics, not publication certification or a playable map.
## Full local tactical/port compilation and publication are separate later gates.
func draft_diagnostics(context: EnvironmentResolutionContext = null) -> Array[Dictionary]:
	var errors := source_errors(data)
	if not errors.is_empty(): return errors
	if context == null: context = EnvironmentResolutionContext.new()
	if data.instances.is_empty(): _error(errors, "EMPTY_CHUNK", "instances", "Draft has no instances")
	if data.rotations.is_empty(): _error(errors, "NO_SUPPORTED_ROTATION", "rotations", "Choose at least one supported rotation")
	var layout := EnvironmentModuleLayout.new(StringName(data.chunk_id))
	var ids := {}
	for record in data.instances:
		ids[record.placement_id] = true
		var placement := EnvironmentModulePlacement.from_record(record)
		var definition: EnvironmentModuleDefinition = context.catalog.get(placement.component_id)
		if definition == null:
			if str(record.component_id).begins_with("asset:") and record.placement_id in data.tactical.get("visual_only", []):
				pass # Explicit declaration; substantive role/geometry checks belong to publication.
			elif str(record.component_id).begins_with("asset:"):
				_error(errors, "UNRESOLVED_VISUAL_TACTICAL_ROLE", record.placement_id, "Raw asset draft: explicit tactical behavior and dependency review required before publication")
			else: _error(errors, "UNRESOLVED_COMPONENT", record.placement_id, record.component_id)
			continue
		if not layout.try_add(definition, placement, Vector2i(int(data.bounds[0]), int(data.bounds[1]))): _error(errors, "INVALID_PLACEMENT", record.placement_id, layout.errors.back())
		var geometry := EnvironmentModuleLayout.Spatial.record(definition, placement)
		if maxf(geometry.occupied_span.y, geometry.visual.end.y) > float(data.height): _error(errors, "VERTICAL_BOUND_EXCEEDED", record.placement_id, "Content exceeds source height")
	for id in data.tactical.components:
		if not ids.has(id): _error(errors, "MISSING_TACTICAL_INSTANCE", "tactical.components", id)
	for port in data.ports:
		if port.cells.is_empty() or port.profile.is_empty() or port.role.is_empty(): _error(errors, "INCOMPLETE_PORT", port.id, "Port needs cells, role and compatibility profile")
		for cell in port.cells:
			var normal := Vector2i(int(port.normal[0]), int(port.normal[1]))
			var at := Vector2i(int(cell[0]), int(cell[1]))
			var size := Vector2i(int(data.bounds[0]), int(data.bounds[1]))
			if at.x < 0 or at.y < 0 or at.x >= size.x or at.y >= size.y or (normal.x < 0 and at.x != 0) or (normal.x > 0 and at.x != size.x - 1) or (normal.y < 0 and at.y != 0) or (normal.y > 0 and at.y != size.y - 1): _error(errors, "PORT_NOT_ON_BOUNDARY", port.id, "Port must face outward on its declared boundary")
	# Reuse dependency enforcement without binding missions or claiming a playable map.
	var dependency_view := BattlefieldLayoutDocument.from_authored(layout, Vector2i(int(data.bounds[0]), int(data.bounds[1])), &"legacy_compatibility", str(data.chunk_id), null, context)
	dependency_view.dependencies.assign(data.dependencies.duplicate(true))
	dependency_view._validate_dependencies(errors, context)
	return errors

static func _json_value(value) -> bool:
	if value == null or value is String or value is bool: return true
	if value is int or value is float: return _number(value)
	if value is Array:
		for item in value:
			if not _json_value(item): return false
		return true
	if value is Dictionary:
		for key in value:
			if not key is String or not _json_value(value[key]): return false
		return true
	return false

static func _integer(value) -> bool: return _number(value) and float(value) == floor(float(value))
static func _number(value) -> bool: return (value is int or value is float) and is_finite(float(value))
static func _vector(value, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number in value:
		if not _integer(number): return false
	return true
static func _fields(value, fields: Dictionary, errors: Array[Dictionary], path: String) -> bool:
	if not value is Dictionary:
		_error(errors, "INVALID_RECORD", path, "Expected object")
		return false
	var valid := true
	for key in fields:
		if not value.has(key) or (fields[key] != TYPE_NIL and typeof(value[key]) != fields[key]):
			_error(errors, "INVALID_FIELD", path + "." + key, "Missing field or incorrect type")
			valid = false
	for key in value:
		if not fields.has(key):
			_error(errors, "UNSUPPORTED_FIELD", path + "." + str(key), "Unknown record field")
			valid = false
	return valid
static func _identity(id: String, seen: Dictionary, errors: Array[Dictionary], path: String) -> void:
	if id.is_empty() or seen.has(id): _error(errors, "INVALID_IDENTITY", path, "Empty or duplicate local identity")
	seen[id] = true
static func _error(errors: Array[Dictionary], code: String, field: String, message: String) -> void:
	errors.append({"code": code, "field": field, "message": message})
