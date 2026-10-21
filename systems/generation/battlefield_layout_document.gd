class_name BattlefieldLayoutDocument
extends RefCounted
## Versioned construction intent shared by authored, generated, and edited maps.
## MapData remains the compiled tactical authority; this record never infers
## traversal, cover, occupancy, or LOS from imported geometry.

const AssetCatalog = preload("res://tools/asset_lab/asset_catalog.gd")
const SemanticCatalog = preload("res://tools/asset_lab/semantic_asset_catalog.gd")

const SCHEMA_VERSION := 1
const GRID_CONVENTION := "fusefire_grid_xz_y_up_cell_1"
const ORIGINS := ["authored", "generated", "edited"]
const ENVIRONMENTS := ["industrial_district", "commercial_street", "mixed_service", "industrial_service_pad"]
const PRESENTATION_MODES := ["asset_first", "legacy"]
const PARCEL_GRAMMAR_REVISION := "coherent_parcel_grammar_v1"

static var _asset_ids_by_path: Dictionary = {}

var document_id := ""
var environment_id := ""
var provenance: Dictionary = {}
var spatial_layout: Dictionary = {}
var relationships: Array[Dictionary] = []
var dependencies: Array[Dictionary] = []
var mission_context: Dictionary = {}
var presentation: Dictionary = {}

static func from_generated(data: MapData, id := "") -> BattlefieldLayoutDocument:
	var result := BattlefieldLayoutDocument.new()
	var plan: EnvironmentLayoutPlan = data.environment_layout_plan
	result.document_id = id if not id.is_empty() else "generated_%s_%d" % [String(plan.environment_id) if plan else "unknown", data.environment_module_seed]
	result.environment_id = String(plan.environment_id) if plan else ""
	result.provenance = {
		"origin": "generated",
		"generator_id": "coherent_environment_assembler",
		"has_generation_seed": true,
		"generation_seed": data.environment_module_seed,
		"generation_config": {
			"topology": String(plan.topology) if plan else "",
			"macro_size": plan.macro_size if plan else 0,
			"plan_signature": plan.signature() if plan else "",
		},
		"algorithm_revisions": {"layout_document": SCHEMA_VERSION, "parcel_grammar": PARCEL_GRAMMAR_REVISION},
	}
	result._capture_spatial_layout(data.environment_modules, data.map_size)
	result._capture_plan_relationships(plan)
	result._capture_dependencies()
	result._capture_mission(data, "generated_repaired")
	result.presentation = {"road_presentation_mode": "asset_first"}
	return result

static func from_authored(layout: EnvironmentModuleLayout, map_size: Vector2i, environment: StringName, id := "", data: MapData = null) -> BattlefieldLayoutDocument:
	var result := BattlefieldLayoutDocument.new()
	result.document_id = id if not id.is_empty() else String(layout.layout_id)
	result.environment_id = String(environment)
	result.provenance = {
		"origin": "authored",
		"generator_id": "",
		"has_generation_seed": false,
		"generation_seed": 0,
		"generation_config": {},
		"algorithm_revisions": {"layout_document": SCHEMA_VERSION},
	}
	result._capture_spatial_layout(layout.placements, map_size)
	if layout.layout_id == &"certified_equipment_parcel":
		result.relationships.append({"relationship_id": "authored_equipment_parcel", "kind": "assembly_template", "subject_ref": "document:%s" % result.document_id, "object_ref": "assembly:%s" % IndustrialEquipmentParcelDefinition.PARCEL_ID, "required": true})
	result._capture_dependencies()
	if data == null:
		result.mission_context = {"status": "not_represented", "zone_source": "not_available", "zones": []}
	else:
		result._capture_mission(data, "authored")
	result.presentation = {"road_presentation_mode": "asset_first"}
	return result

static func from_dictionary(value: Dictionary) -> BattlefieldLayoutDocument:
	var result := BattlefieldLayoutDocument.new()
	result.document_id = str(value.get("document_id", ""))
	result.environment_id = str(value.get("environment_id", ""))
	result.provenance = value.get("provenance", {}).duplicate(true) if value.get("provenance", {}) is Dictionary else {}
	result.spatial_layout = value.get("spatial_layout", {}).duplicate(true) if value.get("spatial_layout", {}) is Dictionary else {}
	result.relationships.assign(value.get("relationships", []) if value.get("relationships", []) is Array else [])
	result.dependencies.assign(value.get("dependencies", []) if value.get("dependencies", []) is Array else [])
	result.mission_context = value.get("mission_context", {}).duplicate(true) if value.get("mission_context", {}) is Dictionary else {}
	result.presentation = value.get("presentation", {}).duplicate(true) if value.get("presentation", {}) is Dictionary else {}
	# Preserve an unsupported version so validation can report it.
	result.spatial_layout["_document_schema_version"] = int(value.get("schema_version", -1))
	return result

func to_dictionary() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"document_id": document_id,
		"environment_id": environment_id,
		"provenance": provenance.duplicate(true),
		"spatial_layout": _public_spatial_layout(),
		"relationships": relationships.duplicate(true),
		"dependencies": dependencies.duplicate(true),
		"mission_context": mission_context.duplicate(true),
		"presentation": presentation.duplicate(true),
	}

func to_json() -> String:
	return JSON.stringify(to_dictionary(), "\t", false) + "\n"

func signature() -> String:
	return to_json().sha256_text()

func to_module_layout(catalog := {}) -> EnvironmentModuleLayout:
	if catalog.is_empty(): catalog = IndustrialModuleCatalog.create()
	var layout := EnvironmentModuleLayout.new(StringName(document_id), int(provenance.get("generation_seed", 0)))
	var map_size := _map_size()
	for record in spatial_layout.get("placements", []):
		if not record is Dictionary: continue
		var component_id := StringName(record.get("component_id", ""))
		var definition: EnvironmentModuleDefinition = catalog.get(component_id)
		var origin = record.get("origin", [])
		if definition == null or not origin is Array or origin.size() != 2: continue
		layout.try_add(definition, EnvironmentModulePlacement.new(component_id, Vector2i(int(origin[0]), int(origin[1])), int(record.get("rotation", 0)), int(record.get("variation", 0)), int(record.get("elevation", 0))), map_size)
	return layout

func validate(catalog := {}) -> Array[Dictionary]:
	if catalog.is_empty(): catalog = IndustrialModuleCatalog.create()
	var failures: Array[Dictionary] = []
	var encoded_version := int(spatial_layout.get("_document_schema_version", SCHEMA_VERSION))
	if encoded_version != SCHEMA_VERSION: _fail(failures, "UNSUPPORTED_SCHEMA_VERSION", "schema_version", "version %d is not supported" % encoded_version)
	if document_id.is_empty(): _fail(failures, "MISSING_IDENTITY", "document_id", "document identity is required")
	if environment_id.is_empty(): _fail(failures, "MISSING_ENVIRONMENT_ID", "environment_id", "environment identity is required")
	elif environment_id not in ENVIRONMENTS: _fail(failures, "UNSUPPORTED_ENVIRONMENT", "environment_id", "environment '%s' is not supported" % environment_id)
	_validate_provenance(failures)
	var map_size := _map_size()
	if map_size.x < 4 or map_size.y < 4: _fail(failures, "INVALID_MAP_DIMENSIONS", "spatial_layout.map_size", "width and depth must both be at least four")
	if spatial_layout.get("grid_convention", "") != GRID_CONVENTION: _fail(failures, "UNSUPPORTED_GRID_CONVENTION", "spatial_layout.grid_convention", "only %s is supported" % GRID_CONVENTION)
	if not is_equal_approx(float(spatial_layout.get("cell_size", 0.0)), 1.0): _fail(failures, "UNSUPPORTED_GRID_SCALE", "spatial_layout.cell_size", "Task 4.1 supports the established one-unit grid")
	_validate_placements(failures, catalog, map_size)
	_validate_relationships(failures)
	_validate_dependencies(failures)
	_validate_mission(failures, map_size)
	if presentation.get("road_presentation_mode", "") not in PRESENTATION_MODES: _fail(failures, "UNSUPPORTED_PRESENTATION", "presentation.road_presentation_mode", "presentation mode is missing or unsupported")
	return failures

func _capture_spatial_layout(source_placements: Array, map_size: Vector2i) -> void:
	var encoded: Array[Dictionary] = []
	var catalog := IndustrialModuleCatalog.create()
	for index in source_placements.size():
		var placement: EnvironmentModulePlacement = source_placements[index]
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		var record := {
			"placement_id": "placement_%04d" % index,
			"component_id": String(placement.component_id),
			"origin": [placement.origin.x, placement.origin.y],
			"rotation": placement.rotation,
			"variation": placement.variation,
			"elevation": placement.elevation,
			"assembly_ref": String(definition.structural_assembly_id) if definition and not definition.structural_assembly_id.is_empty() else "",
			"asset_refs": _resolved_assets(definition, placement.variation) if definition else [],
		}
		encoded.append(record)
		if not record.assembly_ref.is_empty():
			relationships.append({"relationship_id": "assembly_%04d" % index, "kind": "assembly_instance", "subject_ref": record.placement_id, "object_ref": "assembly:%s" % record.assembly_ref, "required": true})
	spatial_layout = {"map_size": [map_size.x, map_size.y], "grid_convention": GRID_CONVENTION, "cell_size": 1.0, "placements": encoded}

func _capture_plan_relationships(plan: EnvironmentLayoutPlan) -> void:
	if plan == null: return
	var parcels: Array = plan.parcels.duplicate()
	parcels.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	for parcel in parcels:
		var bounds: Rect2i = parcel.get("bounds", Rect2i())
		var template := String(parcel.get("template", "empty"))
		relationships.append({
			"relationship_id": "parcel_%s" % String(parcel.get("id", "")),
			"kind": "parcel_template",
			"subject_ref": "document:%s" % document_id,
			"object_ref": "template:%s" % template,
			"required": true,
			"properties": {"parcel_id": String(parcel.get("id", "")), "bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y], "rotation": int(parcel.get("rotation", 0))},
		})

func _capture_dependencies() -> void:
	var by_key: Dictionary = {}
	for record in spatial_layout.get("placements", []):
		for asset_id in record.get("asset_refs", []):
			var key := "asset:%s" % asset_id
			if not by_key.has(key):
				by_key[key] = {"kind": "asset", "id": asset_id, "geometry_sha256": EnvironmentAssemblyContract.current_geometry_sha256(asset_id), "calibration_signature": EnvironmentAssemblyContract.current_calibration_signature(asset_id), "required_by": []}
			by_key[key].required_by.append(record.placement_id)
		var assembly_id := String(record.get("assembly_ref", ""))
		if not assembly_id.is_empty():
			var assembly_key := "assembly:%s" % assembly_id
			if not by_key.has(assembly_key): by_key[assembly_key] = _assembly_dependency(assembly_id)
			by_key[assembly_key].required_by.append(record.placement_id)
	for relationship in relationships:
		if str(relationship.get("object_ref", "")).begins_with("assembly:"):
			var assembly_id := str(relationship.object_ref).trim_prefix("assembly:")
			var key := "assembly:%s" % assembly_id
			if not by_key.has(key): by_key[key] = _assembly_dependency(assembly_id)
			by_key[key].required_by.append(relationship.relationship_id)
		if relationship.kind != "parcel_template": continue
		var template_id := String(relationship.object_ref).trim_prefix("template:")
		var key := "template:%s" % template_id
		if not by_key.has(key): by_key[key] = {"kind": "template", "id": template_id, "revision": PARCEL_GRAMMAR_REVISION, "required_by": []}
		by_key[key].required_by.append(relationship.relationship_id)
	var keys := by_key.keys()
	keys.sort()
	for key in keys:
		var dependency: Dictionary = by_key[key]
		dependency.required_by.sort()
		dependencies.append(dependency)

func _capture_mission(data: MapData, source: String) -> void:
	var encoded: Array[Dictionary] = []
	var ids := data.zones.keys()
	ids.sort_custom(func(a, b): return String(a) < String(b))
	for zone_id in ids:
		var zone: MapZoneData = data.zones[zone_id]
		var cells: Array = []
		var ordered := zone.cells.duplicate()
		ordered.sort_custom(func(a, b): return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z))))
		for cell in ordered: cells.append([cell.x, cell.y, cell.z])
		encoded.append({"zone_id": String(zone.zone_id), "kind": zone.kind, "faction": zone.faction, "cells": cells})
	mission_context = {"status": "preserved", "zone_source": source, "zones": encoded, "objective_definitions": "not_represented_by_current_editor"}

func _validate_provenance(failures: Array[Dictionary]) -> void:
	var origin := str(provenance.get("origin", ""))
	if origin not in ORIGINS: _fail(failures, "INVALID_PROVENANCE", "provenance.origin", "origin must be authored, generated, or edited")
	if origin == "generated":
		if str(provenance.get("generator_id", "")).is_empty(): _fail(failures, "MISSING_GENERATOR", "provenance.generator_id", "generated documents require a generator identity")
		if not bool(provenance.get("has_generation_seed", false)): _fail(failures, "MISSING_GENERATION_SEED", "provenance.generation_seed", "generated documents require their original seed")
		if not provenance.get("generation_config", {}) is Dictionary or provenance.get("generation_config", {}).is_empty(): _fail(failures, "MISSING_GENERATION_CONFIG", "provenance.generation_config", "generated documents require their generation configuration")
	elif origin == "authored" and (bool(provenance.get("has_generation_seed", false)) or not str(provenance.get("generator_id", "")).is_empty()):
		_fail(failures, "INCONSISTENT_PROVENANCE", "provenance", "authored documents cannot claim generated provenance")

func _validate_placements(failures: Array[Dictionary], catalog: Dictionary, map_size: Vector2i) -> void:
	var encoded = spatial_layout.get("placements", null)
	if not encoded is Array:
		_fail(failures, "MALFORMED_PLACEMENTS", "spatial_layout.placements", "placements must be an array")
		return
	var seen: Dictionary = {}
	var layout := EnvironmentModuleLayout.new(StringName(document_id), int(provenance.get("generation_seed", 0)))
	for index in encoded.size():
		var record = encoded[index]
		var field := "spatial_layout.placements[%d]" % index
		if not record is Dictionary:
			_fail(failures, "MALFORMED_PLACEMENT", field, "placement must be an object")
			continue
		var placement_id := str(record.get("placement_id", ""))
		if placement_id.is_empty() or seen.has(placement_id): _fail(failures, "INVALID_PLACEMENT_ID", field + ".placement_id", "placement identity is missing or duplicated", placement_id)
		seen[placement_id] = true
		var component_id := StringName(record.get("component_id", ""))
		var definition: EnvironmentModuleDefinition = catalog.get(component_id)
		if definition == null:
			_fail(failures, "MISSING_PLACEMENT_REFERENCE", field + ".component_id", "component '%s' does not exist" % component_id, placement_id)
			continue
		var origin = record.get("origin", [])
		if not origin is Array or origin.size() != 2:
			_fail(failures, "MALFORMED_PLACEMENT", field + ".origin", "origin must contain x and z", placement_id)
			continue
		var rotation := int(record.get("rotation", -1))
		if rotation not in definition.allowed_rotations:
			_fail(failures, "UNSUPPORTED_ROTATION", field + ".rotation", "rotation %d is not supported by %s" % [rotation, component_id], placement_id)
			continue
		var placement := EnvironmentModulePlacement.new(component_id, Vector2i(int(origin[0]), int(origin[1])), rotation, int(record.get("variation", 0)), int(record.get("elevation", 0)))
		if not layout.try_add(definition, placement, map_size): _fail(failures, "INVALID_PLACEMENT", field, layout.errors.back(), placement_id)

func _validate_relationships(failures: Array[Dictionary]) -> void:
	var references: Dictionary = {"document:%s" % document_id: true}
	for assembly_id in InitialEnvironmentAssemblyLibrary.records().keys(): references["assembly:%s" % String(assembly_id)] = true
	for placement in spatial_layout.get("placements", []):
		if placement is Dictionary:
			references[str(placement.get("placement_id", ""))] = true
			var assembly_ref := str(placement.get("assembly_ref", ""))
			if not assembly_ref.is_empty(): references["assembly:%s" % assembly_ref] = true
	for relationship in relationships:
		if not relationship is Dictionary:
			_fail(failures, "MALFORMED_RELATIONSHIP", "relationships", "relationship must be an object")
			continue
		var relation_id := str(relationship.get("relationship_id", ""))
		var subject := str(relationship.get("subject_ref", ""))
		var object := str(relationship.get("object_ref", ""))
		if relation_id.is_empty(): _fail(failures, "MISSING_RELATIONSHIP_ID", "relationships", "relationship identity is required")
		if not references.has(subject): _fail(failures, "MISSING_RELATIONSHIP_REFERENCE", "relationships.%s.subject_ref" % relation_id, "subject '%s' does not exist" % subject, relation_id)
		if object.begins_with("template:"):
			if object.trim_prefix("template:").is_empty(): _fail(failures, "MISSING_RELATIONSHIP_REFERENCE", "relationships.%s.object_ref" % relation_id, "template reference is empty", relation_id)
		elif not references.has(object): _fail(failures, "MISSING_RELATIONSHIP_REFERENCE", "relationships.%s.object_ref" % relation_id, "object '%s' does not exist" % object, relation_id)

func _validate_dependencies(failures: Array[Dictionary]) -> void:
	var by_key: Dictionary = {}
	for dependency in dependencies:
		if not dependency is Dictionary: continue
		by_key["%s:%s" % [dependency.get("kind", ""), dependency.get("id", "")]] = dependency
	for record in spatial_layout.get("placements", []):
		if not record is Dictionary: continue
		for asset_id in record.get("asset_refs", []):
			var key := "asset:%s" % asset_id
			if not by_key.has(key):
				_fail(failures, "MISSING_DEPENDENCY", "dependencies", "%s required by %s is absent" % [key, record.get("placement_id", "")], key)
				continue
			var dependency: Dictionary = by_key[key]
			if dependency.get("geometry_sha256", "") != EnvironmentAssemblyContract.current_geometry_sha256(asset_id): _fail(failures, "STALE_GEOMETRY_DEPENDENCY", "dependencies.%s.geometry_sha256" % key, "%s geometry revision changed" % asset_id, key)
			if dependency.get("calibration_signature", "") != EnvironmentAssemblyContract.current_calibration_signature(asset_id): _fail(failures, "STALE_CALIBRATION_DEPENDENCY", "dependencies.%s.calibration_signature" % key, "%s calibration revision changed" % asset_id, key)
		var assembly_id := str(record.get("assembly_ref", ""))
		if not assembly_id.is_empty() and not by_key.has("assembly:%s" % assembly_id): _fail(failures, "MISSING_DEPENDENCY", "dependencies", "assembly:%s is absent" % assembly_id, assembly_id)
	for relationship in relationships:
		if not relationship is Dictionary: continue
		var key := str(relationship.get("object_ref", ""))
		if relationship.get("kind", "") == "parcel_template" and not by_key.has(key): _fail(failures, "MISSING_DEPENDENCY", "dependencies", "%s is absent" % key, key)
		if key.begins_with("assembly:") and not by_key.has(key): _fail(failures, "MISSING_DEPENDENCY", "dependencies", "%s is absent" % key, key)
	for key in by_key:
		var dependency: Dictionary = by_key[key]
		if dependency.get("kind", "") == "assembly":
			var current := _assembly_dependency(str(dependency.get("id", "")))
			if dependency.get("certification_signature", "") != current.get("certification_signature", "missing"): _fail(failures, "STALE_ASSEMBLY_DEPENDENCY", "dependencies.%s.certification_signature" % key, "%s certification dependency changed" % key, key)
		elif dependency.get("kind", "") == "template" and dependency.get("revision", "") != PARCEL_GRAMMAR_REVISION:
			_fail(failures, "STALE_TEMPLATE_DEPENDENCY", "dependencies.%s.revision" % key, "%s template grammar revision changed" % key, key)

func _validate_mission(failures: Array[Dictionary], map_size: Vector2i) -> void:
	var status := str(mission_context.get("status", ""))
	if status not in ["preserved", "not_represented"]: _fail(failures, "INVALID_MISSION_CONTEXT", "mission_context.status", "mission context status is unsupported")
	if status == "not_represented": return
	var seen: Dictionary = {}
	for zone in mission_context.get("zones", []):
		if not zone is Dictionary:
			_fail(failures, "MALFORMED_ZONE", "mission_context.zones", "zone must be an object")
			continue
		var zone_id := str(zone.get("zone_id", ""))
		if zone_id.is_empty() or seen.has(zone_id): _fail(failures, "INVALID_ZONE_ID", "mission_context.zones", "zone identity is missing or duplicated", zone_id)
		seen[zone_id] = true
		for cell in zone.get("cells", []):
			if not cell is Array or cell.size() != 3:
				_fail(failures, "MALFORMED_ZONE_CELL", "mission_context.zones.%s.cells" % zone_id, "zone cell must contain x, y, z", zone_id)
				continue
			if int(cell[0]) < 0 or int(cell[2]) < 0 or int(cell[0]) >= map_size.x or int(cell[2]) >= map_size.y: _fail(failures, "ZONE_CELL_OUT_OF_BOUNDS", "mission_context.zones.%s.cells" % zone_id, "cell %s is outside the map" % [cell], zone_id)

func _map_size() -> Vector2i:
	var encoded = spatial_layout.get("map_size", [])
	return Vector2i(int(encoded[0]), int(encoded[1])) if encoded is Array and encoded.size() == 2 else Vector2i.ZERO

func _public_spatial_layout() -> Dictionary:
	var result := spatial_layout.duplicate(true)
	result.erase("_document_schema_version")
	return result

static func _resolved_assets(definition: EnvironmentModuleDefinition, variation: int) -> Array[String]:
	var result: Array[String] = []
	for visual in definition.visuals:
		if visual.get("kind", "asset") == "socket_assembly":
			for component in visual.get("components", []): _append_unique(result, str(component.get("asset_id", "")))
			continue
		var candidates: Array = visual.get("asset_ids", [])
		if not candidates.is_empty():
			var approved := SemanticCatalog.generation_candidates(candidates)
			if not approved.is_empty(): _append_unique(result, str(approved[variation % approved.size()]))
			continue
		var paths: Array = visual.get("asset_variants", [])
		var path := str(visual.get("asset_path", ""))
		if not paths.is_empty(): path = str(paths[variation % paths.size()])
		_append_unique(result, _asset_id_for_path(path))
	return result

static func _asset_id_for_path(path: String) -> String:
	if path.is_empty(): return ""
	if _asset_ids_by_path.is_empty():
		for asset_id in AssetCatalog.all_ids(): _asset_ids_by_path[AssetCatalog.path_for(asset_id)] = asset_id
	return str(_asset_ids_by_path.get(path, ""))

static func _append_unique(values: Array[String], value: String) -> void:
	if not value.is_empty() and value not in values: values.append(value)

static func _assembly_dependency(assembly_id: String) -> Dictionary:
	var records := InitialEnvironmentAssemblyLibrary.records()
	if not records.has(StringName(assembly_id)):
		return {"kind": "assembly", "id": assembly_id, "certification_signature": "missing", "required_by": []}
	var contract: EnvironmentAssemblyContract = records[StringName(assembly_id)].contract
	var parts: Array[String] = [String(contract.assembly_id), str(contract.role), str(contract.completeness), str(contract.certification_state)]
	for component in contract.components:
		parts.append("%s:%s:%s" % [component.get("asset_id", ""), component.get("geometry_sha256", ""), component.get("calibration_signature", "")])
	parts.sort()
	return {"kind": "assembly", "id": assembly_id, "certification_signature": "|".join(parts).sha256_text(), "required_by": []}

static func _fail(target: Array[Dictionary], code: String, field: String, message: String, reference := "") -> void:
	target.append({"code": code, "field": field, "reference": reference, "message": message})
