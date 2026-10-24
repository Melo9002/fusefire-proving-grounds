class_name BattlefieldLayoutDocument
extends RefCounted
## Versioned construction intent shared by authored, generated, and edited maps.
## MapData remains the compiled tactical authority; this record never infers
## traversal, cover, occupancy, or LOS from imported geometry.

const AssetCatalog = preload("res://tools/asset_lab/asset_catalog.gd")
const SemanticCatalog = preload("res://tools/asset_lab/semantic_asset_catalog.gd")
const ParcelContract = preload("res://systems/generation/environment_parcel_spatial_contract.gd")
const ReservationLedger = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")
const RelationshipValidator = preload("res://systems/generation/environment_parcel_relationship_validator.gd")

const SCHEMA_VERSION := 1
const GRID_CONVENTION := "fusefire_grid_xz_y_up_cell_1"
const ORIGINS := ["authored", "generated", "edited"]
const ENVIRONMENTS := ["industrial_district", "commercial_street", "mixed_service", "industrial_service_pad", "legacy_compatibility"]
const PRESENTATION_MODES := ["asset_first", "legacy"]
const PARCEL_GRAMMAR_REVISION := "coherent_parcel_grammar_v4_bounded_search"

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
			"candidate_search": plan.search_budget.duplicate(true) if plan else {},
			"generation_summary": plan.generation_summary() if plan else {},
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

func map_size() -> Vector2i:
	return _map_size()

func editable_copy() -> BattlefieldLayoutDocument:
	var result := BattlefieldLayoutDocument.from_dictionary(to_dictionary())
	var source_origin := str(result.provenance.get("source_origin", result.provenance.get("origin", "authored")))
	result.provenance["source_origin"] = source_origin
	result.provenance["origin"] = "edited"
	result.provenance["edit_state"] = "unchanged_copy"
	return result

func apply_edited_layout(layout: EnvironmentModuleLayout) -> void:
	var old_records: Array = spatial_layout.get("placements", []).duplicate(true)
	var old_parcels: Array = spatial_layout.get("parcels", []).duplicate(true)
	var old_reservations: Array = spatial_layout.get("reservations", []).duplicate(true)
	var old_relationships := relationships.duplicate(true)
	var id_by_signature: Dictionary = {}
	var maximum_id := -1
	for record in old_records:
		if not record is Dictionary: continue
		var key := _encoded_placement_signature(record)
		if not id_by_signature.has(key): id_by_signature[key] = []
		id_by_signature[key].append(record.get("placement_id", ""))
		var suffix := str(record.get("placement_id", "")).trim_prefix("placement_")
		if suffix.is_valid_int(): maximum_id = maxi(maximum_id, int(suffix))
	relationships.clear()
	_capture_spatial_layout(layout.placements, _map_size())
	var changed: bool = old_records.size() != spatial_layout.placements.size()
	for record in spatial_layout.placements:
		var signature := _encoded_placement_signature(record)
		var available: Array = id_by_signature.get(signature, [])
		if not available.is_empty():
			record.placement_id = available.pop_front()
		else:
			maximum_id += 1
			record.placement_id = "placement_%04d" % maximum_id
			changed = true
	spatial_layout["parcels"] = old_parcels
	spatial_layout["reservations"] = old_reservations
	if changed:
		for parcel in spatial_layout.parcels:
			if parcel is Dictionary: parcel["validation_state"] = "requires_revalidation"
		for reservation in spatial_layout.reservations:
			if reservation is Dictionary: reservation["validation_state"] = "requires_revalidation"
	# Rebuild assembly relationships after stable IDs have been restored.
	relationships.clear()
	for record in spatial_layout.placements:
		if not str(record.assembly_ref).is_empty(): relationships.append({"relationship_id": "assembly_%s" % record.placement_id, "kind": "assembly_instance", "subject_ref": record.placement_id, "object_ref": "assembly:%s" % record.assembly_ref, "required": true})
	for relationship in old_relationships:
		if relationship.get("kind", "") == "assembly_instance": continue
		var retained: Dictionary = relationship.duplicate(true)
		if changed: retained["validation_state"] = "requires_revalidation"
		relationships.append(retained)
	dependencies.clear()
	_capture_dependencies()
	provenance["source_origin"] = str(provenance.get("source_origin", provenance.get("origin", "authored")))
	provenance["origin"] = "edited"
	provenance["edit_state"] = "modified" if changed else "unchanged_copy"
	mission_context["validation_state"] = "requires_revalidation" if changed else mission_context.get("validation_state", "validated")

func replace_mission_from_map(data: MapData, source := "document_revalidated") -> void:
	_capture_mission(data, source)
	mission_context["validation_state"] = "validated"
	for reservation in spatial_layout.get("reservations", []):
		if reservation is Dictionary: reservation["validation_state"] = "validated"

func mark_functional_relationships_validated() -> void:
	for parcel in spatial_layout.get("parcels", []):
		if parcel is Dictionary: parcel["validation_state"] = "validated"
	for relationship in relationships:
		if relationship is Dictionary and relationship.get("kind", "") in ParcelContract.FUNCTIONAL_RELATIONSHIPS + ["parcel_template"]:
			relationship["validation_state"] = "validated"

func restore_mission_to_map(data: MapData) -> void:
	if mission_context.get("status", "") != "preserved": return
	data.zones.clear()
	for record in mission_context.get("zones", []):
		if not record is Dictionary: continue
		var cells: Array[Vector3i] = []
		for encoded in record.get("cells", []):
			if encoded is Array and encoded.size() == 3: cells.append(Vector3i(int(encoded[0]), int(encoded[1]), int(encoded[2])))
		data.set_zone(MapZoneData.new(StringName(record.get("zone_id", "")), int(record.get("kind", MapZoneData.Kind.DEPLOYMENT)), cells, int(record.get("faction", -1))))

func to_environment_layout_plan() -> EnvironmentLayoutPlan:
	var plan := EnvironmentLayoutPlan.new(StringName(environment_id), int(provenance.get("generation_seed", 0)))
	plan.topology = StringName(provenance.get("generation_config", {}).get("topology", "edited"))
	plan.macro_size = int(provenance.get("generation_config", {}).get("macro_size", 10))
	plan.search_budget = provenance.get("generation_config", {}).get("candidate_search", {}).duplicate(true)
	if spatial_layout.get("parcels", []) is Array and not spatial_layout.get("parcels", []).is_empty():
		for record in spatial_layout.parcels:
			if not record is Dictionary: continue
			var bounds = record.get("bounds", [])
			if not bounds is Array or bounds.size() != 4: continue
			plan.parcels.append({
				"id": StringName(record.get("parcel_id", "")),
				"bounds": Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3])),
				"template": StringName(record.get("template_id", "empty")),
				"rotation": int(record.get("rotation", 0)),
				"selected_frontage_id": str(record.get("selected_frontage_id", "")),
				"placement_offset": int(record.get("placement_offset", 0)),
				"frontage_spans": record.get("frontage_spans", []).duplicate(true),
				"road_edges": ParcelContract.directions_for_spans(record.get("frontage_spans", [])),
				"occupants": record.get("occupants", []).duplicate(true),
				"relationship_validation": record.get("validation_state", "validated"),
			})
	else:
		for relationship in relationships:
			if relationship.get("kind", "") != "parcel_template": continue
			var properties: Dictionary = relationship.get("properties", {})
			var bounds = properties.get("bounds", [])
			if not bounds is Array or bounds.size() != 4: continue
			plan.parcels.append({"id": StringName(properties.get("parcel_id", "")), "bounds": Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3])), "template": StringName(str(relationship.get("object_ref", "")).trim_prefix("template:")), "rotation": int(properties.get("rotation", 0)), "relationship_validation": relationship.get("validation_state", "validated")})
	plan.reservations.assign(ReservationLedger.decoded_records(spatial_layout.get("reservations", [])))
	var catalog := IndustrialModuleCatalog.create()
	for record in spatial_layout.get("placements", []):
		var definition: EnvironmentModuleDefinition = catalog.get(StringName(record.get("component_id", "")))
		if definition == null or definition.module_type not in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]: continue
		var origin = record.get("origin", [])
		if origin is Array and origin.size() == 2:
			var macro := Vector2i(int(origin[0]) / plan.macro_size, int(origin[1]) / plan.macro_size)
			if macro not in plan.road_cells: plan.road_cells.append(macro)
	return plan

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
	_validate_parcels(failures, catalog, map_size)
	_validate_reservations(failures, map_size)
	_validate_reservation_placement_conflicts(failures, catalog, map_size)
	_validate_relationships(failures)
	_validate_functional_parcels(failures, catalog)
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
	var placement_ids: Dictionary = {}
	var runtime_by_signature: Dictionary = {}
	for placement in spatial_layout.get("placements", []):
		if placement is Dictionary:
			var signature := _encoded_placement_signature(placement)
			placement_ids[signature] = str(placement.get("placement_id", ""))
			var origin = placement.get("origin", [])
			if origin is Array and origin.size() == 2:
				runtime_by_signature[signature] = EnvironmentModulePlacement.new(StringName(placement.get("component_id", "")), Vector2i(int(origin[0]), int(origin[1])), int(placement.get("rotation", 0)), int(placement.get("variation", 0)), int(placement.get("elevation", 0)))
	var encoded_parcels: Array[Dictionary] = []
	var parcels: Array = plan.parcels.duplicate()
	parcels.sort_custom(func(a, b): return String(a.get("id", "")) < String(b.get("id", "")))
	for parcel in parcels:
		var parcel_id := String(parcel.get("id", ""))
		var bounds: Rect2i = parcel.get("bounds", Rect2i())
		var template := String(parcel.get("template", "empty"))
		var occupants: Array[Dictionary] = []
		for occupant in parcel.get("occupants", []):
			var placement_ref := str(placement_ids.get(str(occupant.get("placement_signature", "")), ""))
			occupants.append({"placement_ref": placement_ref, "required": bool(occupant.get("required", true))})
		occupants.sort_custom(func(a, b): return str(a.placement_ref) < str(b.placement_ref))
		var frontages: Array[Dictionary] = []
		var parcel_road_refs: Array[String] = []
		for source_span in parcel.get("frontage_spans", []):
			var span: Dictionary = source_span.duplicate(true)
			var resolved_roads: Array[String] = []
			for signature in source_span.get("road_refs", []):
				var road_ref := str(placement_ids.get(str(signature), ""))
				if not road_ref.is_empty() and road_ref not in resolved_roads: resolved_roads.append(road_ref)
			resolved_roads.sort()
			span["road_refs"] = resolved_roads
			frontages.append(span)
			for road_ref in resolved_roads:
				if road_ref not in parcel_road_refs: parcel_road_refs.append(road_ref)
		parcel_road_refs.sort()
		encoded_parcels.append({
			"parcel_id": parcel_id,
			"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
			"template_id": template,
			"rotation": int(parcel.get("rotation", 0)),
			"selected_frontage_id": str(parcel.get("selected_frontage_id", "")),
			"placement_offset": int(parcel.get("placement_offset", 0)),
			"occupants": occupants,
			"road_refs": parcel_road_refs,
			"frontage_spans": frontages,
			"validation_state": "validated",
		})
		relationships.append({
			"relationship_id": "parcel_%s" % parcel_id,
			"kind": "parcel_template",
			"subject_ref": "parcel:%s" % parcel_id,
			"object_ref": "template:%s" % template,
			"required": true,
			"properties": {"parcel_id": parcel_id, "bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y], "rotation": int(parcel.get("rotation", 0)), "selected_frontage_id": str(parcel.get("selected_frontage_id", "")), "placement_offset": int(parcel.get("placement_offset", 0))},
		})
		for occupant in occupants:
			relationships.append({
				"relationship_id": "occupant_%s_%s" % [parcel_id, occupant.placement_ref],
				"kind": ParcelContract.REQUIRED_OCCUPANT,
				"subject_ref": "parcel:%s" % parcel_id,
				"object_ref": occupant.placement_ref,
				"required": occupant.required,
			})
		for span in frontages:
			var frontage_ref := "frontage:%s" % span.frontage_id
			for road_ref in span.road_refs:
				relationships.append({
					"relationship_id": "street_%s_%s" % [span.frontage_id, road_ref],
					"kind": ParcelContract.FRONTAGE_TO_STREET,
					"subject_ref": frontage_ref,
					"object_ref": road_ref,
					"required": true,
					"properties": {"parcel_ref": "parcel:%s" % parcel_id, "width_cells": span.width_cells},
				})
		var access_kind: String = ParcelContract.relationship_kind_for_template(template)
		var runtime_parcel: Dictionary = parcel.duplicate(true)
		runtime_parcel["frontage_spans"] = frontages
		var selected_frontage := RelationshipValidator.select_frontage(runtime_parcel, template)
		if not access_kind.is_empty() and not selected_frontage.is_empty():
			var runtime_placements: Array[EnvironmentModulePlacement] = []
			for occupant in parcel.get("occupants", []):
				var signature := str(occupant.get("placement_signature", ""))
				if runtime_by_signature.has(signature): runtime_placements.append(runtime_by_signature[signature])
			var properties := RelationshipValidator.relationship_properties(runtime_parcel, template, selected_frontage, runtime_placements, IndustrialModuleCatalog.create())
			properties["access_region"] = "frontage_span"
			properties["clearance_depth_cells"] = selected_frontage.clearance_depth_cells
			relationships.append({
				"relationship_id": "access_%s" % parcel_id,
				"kind": access_kind,
				"subject_ref": "parcel:%s" % parcel_id,
				"object_ref": "frontage:%s" % selected_frontage.frontage_id,
				"required": true,
				"properties": properties,
			})
	spatial_layout["parcels"] = encoded_parcels
	spatial_layout["reservations"] = ReservationLedger.encoded_records(plan.reservations)

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
	elif origin == "edited":
		var source_origin := str(provenance.get("source_origin", ""))
		if source_origin not in ["authored", "generated"]: _fail(failures, "INCONSISTENT_PROVENANCE", "provenance.source_origin", "edited documents must preserve their authored or generated source")
		if source_origin == "generated" and (str(provenance.get("generator_id", "")).is_empty() or not bool(provenance.get("has_generation_seed", false))): _fail(failures, "INCONSISTENT_PROVENANCE", "provenance", "edited generated documents must retain their original generator and seed")

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

func _validate_parcels(failures: Array[Dictionary], catalog: Dictionary, map_size: Vector2i) -> void:
	var parcels = spatial_layout.get("parcels", [])
	if not parcels is Array:
		_fail(failures, "MALFORMED_PARCELS", "spatial_layout.parcels", "parcels must be an array")
		return
	var placements: Dictionary = {}
	for record in spatial_layout.get("placements", []):
		if record is Dictionary: placements[str(record.get("placement_id", ""))] = record
	var parcel_ids: Dictionary = {}
	var frontage_ids: Dictionary = {}
	var owner_by_placement: Dictionary = {}
	for index in parcels.size():
		var parcel = parcels[index]
		var field := "spatial_layout.parcels[%d]" % index
		if not parcel is Dictionary:
			_fail(failures, "MALFORMED_PARCEL", field, "parcel must be an object")
			continue
		var parcel_id := str(parcel.get("parcel_id", ""))
		if parcel_id.is_empty() or parcel_ids.has(parcel_id):
			_fail(failures, "INVALID_PARCEL_ID", field + ".parcel_id", "parcel identity is missing or duplicated", parcel_id)
		parcel_ids[parcel_id] = true
		var encoded_bounds = parcel.get("bounds", [])
		if not encoded_bounds is Array or encoded_bounds.size() != 4:
			_fail(failures, "MALFORMED_PARCEL_BOUNDS", field + ".bounds", "bounds must contain x, z, width, and depth", parcel_id)
			continue
		var bounds := Rect2i(int(encoded_bounds[0]), int(encoded_bounds[1]), int(encoded_bounds[2]), int(encoded_bounds[3]))
		if bounds.size.x <= 0 or bounds.size.y <= 0 or bounds.position.x < 0 or bounds.position.y < 0 or bounds.end.x > map_size.x or bounds.end.y > map_size.y:
			_fail(failures, "INVALID_PARCEL_BOUNDS", field + ".bounds", "parcel bounds are empty or outside the map", parcel_id)
		for occupant in parcel.get("occupants", []):
			if not occupant is Dictionary: continue
			var placement_ref := str(occupant.get("placement_ref", ""))
			if not placements.has(placement_ref):
				_fail(failures, "MISSING_PARCEL_OCCUPANT", field + ".occupants", "owned placement '%s' does not exist" % placement_ref, parcel_id)
			elif owner_by_placement.has(placement_ref):
				_fail(failures, "AMBIGUOUS_PARCEL_OWNERSHIP", field + ".occupants", "placement '%s' is already owned by parcel '%s'" % [placement_ref, owner_by_placement[placement_ref]], placement_ref)
			else:
				owner_by_placement[placement_ref] = parcel_id
		for frontage in parcel.get("frontage_spans", []):
			_validate_frontage_span(failures, frontage, parcel_id, bounds, placements, catalog, frontage_ids, field)

func _validate_frontage_span(failures: Array[Dictionary], frontage, parcel_id: String, bounds: Rect2i, placements: Dictionary, catalog: Dictionary, frontage_ids: Dictionary, field: String) -> void:
	if not frontage is Dictionary:
		_fail(failures, "MALFORMED_FRONTAGE", field + ".frontage_spans", "frontage must be an object", parcel_id)
		return
	var frontage_id := str(frontage.get("frontage_id", ""))
	if frontage_id.is_empty() or frontage_ids.has(frontage_id):
		_fail(failures, "INVALID_FRONTAGE_ID", field + ".frontage_spans.frontage_id", "frontage identity is missing or duplicated", frontage_id)
	frontage_ids[frontage_id] = true
	var direction_data = frontage.get("outward_direction", [])
	var start_data = frontage.get("start", [])
	var end_data = frontage.get("end", [])
	if not direction_data is Array or direction_data.size() != 2 or not start_data is Array or start_data.size() != 2 or not end_data is Array or end_data.size() != 2:
		_fail(failures, "MALFORMED_FRONTAGE_GEOMETRY", field + ".frontage_spans", "direction and half-open endpoints must contain two coordinates", frontage_id)
		return
	var direction := Vector2i(int(direction_data[0]), int(direction_data[1]))
	var start := Vector2i(int(start_data[0]), int(start_data[1]))
	var finish := Vector2i(int(end_data[0]), int(end_data[1]))
	if direction not in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT] or not _span_is_on_boundary(bounds, direction, start, finish):
		_fail(failures, "INVALID_FRONTAGE_GEOMETRY", field + ".frontage_spans", "frontage interval is not a positive span on the claimed parcel boundary", frontage_id)
		return
	var width := absi(finish.x - start.x) + absi(finish.y - start.y)
	if int(frontage.get("width_cells", -1)) != width:
		_fail(failures, "INVALID_FRONTAGE_WIDTH", field + ".frontage_spans.width_cells", "stored width does not match the half-open interval", frontage_id)
	var road_refs = frontage.get("road_refs", [])
	if not road_refs is Array or road_refs.is_empty():
		_fail(failures, "MISSING_FRONTAGE_ROAD", field + ".frontage_spans.road_refs", "frontage requires at least one adjacent road", frontage_id)
		return
	var road_cells: Dictionary = {}
	for road_ref in road_refs:
		var record: Dictionary = placements.get(str(road_ref), {})
		var definition: EnvironmentModuleDefinition = catalog.get(StringName(record.get("component_id", "")))
		if definition == null or definition.module_type not in [EnvironmentModuleDefinition.ModuleType.ROAD, EnvironmentModuleDefinition.ModuleType.INTERSECTION]:
			_fail(failures, "INVALID_FRONTAGE_ROAD", field + ".frontage_spans.road_refs", "'%s' is not a road placement" % road_ref, frontage_id)
			continue
		var origin = record.get("origin", [])
		if origin is Array and origin.size() == 2:
			var placement := EnvironmentModulePlacement.new(definition.component_id, Vector2i(int(origin[0]), int(origin[1])), int(record.get("rotation", 0)), int(record.get("variation", 0)), int(record.get("elevation", 0)))
			for cell in definition.rotated_cells(definition.footprint_cells, placement.rotation): road_cells[placement.origin + cell] = true
	for adjacent in _frontage_adjacent_cells(start, finish, direction):
		if not road_cells.has(adjacent):
			_fail(failures, "FRONTAGE_ROAD_GAP", field + ".frontage_spans", "frontage cell beside %s has no referenced road geometry" % adjacent, frontage_id)
			break

func _validate_reservations(failures: Array[Dictionary], map_size: Vector2i) -> void:
	var encoded = spatial_layout.get("reservations", [])
	if not encoded is Array:
		_fail(failures, "MALFORMED_RESERVATIONS", "spatial_layout.reservations", "reservations must be an array")
		return
	var parcel_refs: Dictionary = {}
	var frontage_refs: Dictionary = {}
	for parcel in spatial_layout.get("parcels", []):
		if not parcel is Dictionary: continue
		parcel_refs["parcel:%s" % parcel.get("parcel_id", "")] = true
		for frontage in parcel.get("frontage_spans", []):
			if frontage is Dictionary: frontage_refs["frontage:%s" % frontage.get("frontage_id", "")] = true
	var zone_refs: Dictionary = {}
	for zone in mission_context.get("zones", []):
		if zone is Dictionary: zone_refs["zone:%s" % zone.get("zone_id", "")] = true
	var seen: Dictionary = {}
	var ledger := ReservationLedger.new()
	for index in encoded.size():
		var record = encoded[index]
		var field := "spatial_layout.reservations[%d]" % index
		if not record is Dictionary:
			_fail(failures, "MALFORMED_RESERVATION", field, "reservation must be an object")
			continue
		var reservation_id := str(record.get("reservation_id", ""))
		var owner_ref := str(record.get("owner_ref", ""))
		var role := str(record.get("role", ""))
		if reservation_id.is_empty() or seen.has(reservation_id): _fail(failures, "INVALID_RESERVATION_ID", field, "reservation identity is missing or duplicated", reservation_id)
		seen[reservation_id] = true
		if role not in ReservationLedger.ROLES: _fail(failures, "UNSUPPORTED_RESERVATION_ROLE", field + ".role", "reservation role '%s' is unsupported" % role, reservation_id)
		if owner_ref.begins_with("parcel:") and not parcel_refs.has(owner_ref): _fail(failures, "MISSING_RESERVATION_OWNER", field + ".owner_ref", "parcel owner '%s' does not exist" % owner_ref, reservation_id)
		elif owner_ref.begins_with("zone:") and not zone_refs.has(owner_ref): _fail(failures, "MISSING_RESERVATION_OWNER", field + ".owner_ref", "mission owner '%s' does not exist" % owner_ref, reservation_id)
		elif not owner_ref.begins_with("parcel:") and not owner_ref.begins_with("zone:"): _fail(failures, "MISSING_RESERVATION_OWNER", field + ".owner_ref", "reservation owner must reference a parcel or mission zone", reservation_id)
		var source_ref := str(record.get("source_ref", ""))
		if source_ref.begins_with("frontage:") and not frontage_refs.has(source_ref): _fail(failures, "MISSING_RESERVATION_SOURCE", field + ".source_ref", "frontage source '%s' does not exist" % source_ref, reservation_id)
		var cells: Array[Vector2i] = []
		for encoded_cell in record.get("cells", []):
			if not encoded_cell is Array or encoded_cell.size() != 2:
				_fail(failures, "MALFORMED_RESERVATION_CELL", field + ".cells", "reservation cell must contain x and z", reservation_id)
				continue
			var cell := Vector2i(int(encoded_cell[0]), int(encoded_cell[1]))
			cells.append(cell)
			if cell.x < 0 or cell.y < 0 or cell.x >= map_size.x or cell.y >= map_size.y: _fail(failures, "RESERVATION_OUT_OF_BOUNDS", field + ".cells", "cell %s is outside the map" % cell, reservation_id)
		var runtime: Dictionary = record.duplicate(true)
		runtime["cells"] = cells
		if not ledger.try_reserve(runtime):
			var failure: Dictionary = ledger.failures.back()
			_fail(failures, str(failure.code), field, str(failure.message), reservation_id)

func _validate_reservation_placement_conflicts(failures: Array[Dictionary], catalog: Dictionary, map_size: Vector2i) -> void:
	var ledger := ReservationLedger.new()
	for record in ReservationLedger.decoded_records(spatial_layout.get("reservations", [])):
		if not ledger.try_reserve(record): return
	var transform_helper := EnvironmentModuleLayout.new(&"reservation_validation", 0)
	var owner_by_placement: Dictionary = {}
	for parcel in spatial_layout.get("parcels", []):
		if not parcel is Dictionary: continue
		for occupant in parcel.get("occupants", []):
			if occupant is Dictionary: owner_by_placement[str(occupant.get("placement_ref", ""))] = "parcel:%s" % parcel.get("parcel_id", "")
	for record in spatial_layout.get("placements", []):
		if not record is Dictionary: continue
		var component_id := StringName(record.get("component_id", ""))
		var definition: EnvironmentModuleDefinition = catalog.get(component_id)
		var origin = record.get("origin", [])
		if definition == null or not origin is Array or origin.size() != 2: continue
		var placement := EnvironmentModulePlacement.new(component_id, Vector2i(int(origin[0]), int(origin[1])), int(record.get("rotation", 0)), int(record.get("variation", 0)), int(record.get("elevation", 0)))
		var allowed := ledger.placement_allowed(definition, placement, transform_helper, str(owner_by_placement.get(str(record.get("placement_id", "")), "")))
		if not allowed.ok:
			_fail(failures, str(allowed.code), "spatial_layout.placements.%s" % record.get("placement_id", ""), str(allowed.message), str(allowed.reservation_id))

static func _span_is_on_boundary(bounds: Rect2i, direction: Vector2i, start: Vector2i, finish: Vector2i) -> bool:
	if direction == Vector2i.UP or direction == Vector2i.DOWN:
		var boundary_y := bounds.position.y if direction == Vector2i.UP else bounds.end.y
		return start.y == boundary_y and finish.y == boundary_y and start.x >= bounds.position.x and finish.x <= bounds.end.x and finish.x > start.x
	var boundary_x := bounds.position.x if direction == Vector2i.LEFT else bounds.end.x
	return start.x == boundary_x and finish.x == boundary_x and start.y >= bounds.position.y and finish.y <= bounds.end.y and finish.y > start.y

static func _frontage_adjacent_cells(start: Vector2i, finish: Vector2i, direction: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if direction.y != 0:
		var z := start.y - 1 if direction == Vector2i.UP else start.y
		for x in range(start.x, finish.x): result.append(Vector2i(x, z))
	else:
		var x := start.x - 1 if direction == Vector2i.LEFT else start.x
		for z in range(start.y, finish.y): result.append(Vector2i(x, z))
	return result

func _validate_relationships(failures: Array[Dictionary]) -> void:
	var references: Dictionary = {"document:%s" % document_id: true}
	for assembly_id in InitialEnvironmentAssemblyLibrary.records().keys(): references["assembly:%s" % String(assembly_id)] = true
	for assembly_id in IndustrialBuildingCatalog.create().keys(): references["assembly:%s" % String(assembly_id)] = true
	for placement in spatial_layout.get("placements", []):
		if placement is Dictionary:
			references[str(placement.get("placement_id", ""))] = true
	for parcel in spatial_layout.get("parcels", []):
		if not parcel is Dictionary: continue
		references["parcel:%s" % parcel.get("parcel_id", "")] = true
		for frontage in parcel.get("frontage_spans", []):
			if frontage is Dictionary: references["frontage:%s" % frontage.get("frontage_id", "")] = true
	var relationship_ids: Dictionary = {}
	for relationship in relationships:
		if not relationship is Dictionary:
			_fail(failures, "MALFORMED_RELATIONSHIP", "relationships", "relationship must be an object")
			continue
		var relation_id := str(relationship.get("relationship_id", ""))
		var subject := str(relationship.get("subject_ref", ""))
		var object := str(relationship.get("object_ref", ""))
		var kind := str(relationship.get("kind", ""))
		if relation_id.is_empty() or relationship_ids.has(relation_id): _fail(failures, "MISSING_RELATIONSHIP_ID", "relationships", "relationship identity is missing or duplicated")
		relationship_ids[relation_id] = true
		if not references.has(subject): _fail(failures, "MISSING_RELATIONSHIP_REFERENCE", "relationships.%s.subject_ref" % relation_id, "subject '%s' does not exist" % subject, relation_id)
		if object.begins_with("template:"):
			if object.trim_prefix("template:").is_empty(): _fail(failures, "MISSING_RELATIONSHIP_REFERENCE", "relationships.%s.object_ref" % relation_id, "template reference is empty", relation_id)
		elif not references.has(object): _fail(failures, "MISSING_RELATIONSHIP_REFERENCE", "relationships.%s.object_ref" % relation_id, "object '%s' does not exist" % object, relation_id)
		if kind in ParcelContract.FUNCTIONAL_RELATIONSHIPS:
			if not relationship.has("required"): _fail(failures, "MALFORMED_SPATIAL_RELATIONSHIP", "relationships.%s.required" % relation_id, "functional relationships must state whether they are required", relation_id)
			if kind == ParcelContract.FRONTAGE_TO_STREET and (not subject.begins_with("frontage:") or object.begins_with("frontage:")):
				_fail(failures, "MALFORMED_SPATIAL_RELATIONSHIP", "relationships.%s" % relation_id, "frontage-to-street must connect a frontage to a road placement", relation_id)
			elif kind == ParcelContract.REQUIRED_OCCUPANT and not subject.begins_with("parcel:"):
				_fail(failures, "MALFORMED_SPATIAL_RELATIONSHIP", "relationships.%s" % relation_id, "occupant relationships must be owned by a parcel", relation_id)
			elif kind in [ParcelContract.PEDESTRIAN_ACCESS, ParcelContract.LOADING_ACCESS, ParcelContract.SERVICE_CLEARANCE] and (not subject.begins_with("parcel:") or not object.begins_with("frontage:")):
				_fail(failures, "MALFORMED_SPATIAL_RELATIONSHIP", "relationships.%s" % relation_id, "functional access must connect a parcel to a frontage region", relation_id)

func _validate_functional_parcels(failures: Array[Dictionary], catalog: Dictionary) -> void:
	var placement_records: Dictionary = {}
	for record in spatial_layout.get("placements", []):
		if record is Dictionary: placement_records[str(record.get("placement_id", ""))] = record
	var access_by_parcel: Dictionary = {}
	for relationship in relationships:
		if not relationship is Dictionary or relationship.get("kind", "") not in [ParcelContract.PEDESTRIAN_ACCESS, ParcelContract.LOADING_ACCESS, ParcelContract.SERVICE_CLEARANCE]: continue
		access_by_parcel[str(relationship.get("subject_ref", "")).trim_prefix("parcel:")] = relationship
	for encoded in spatial_layout.get("parcels", []):
		if not encoded is Dictionary: continue
		var template_id := str(encoded.get("template_id", ""))
		var contract := RelationshipValidator.contract_for(template_id)
		if contract.is_empty(): continue
		var parcel_id := str(encoded.get("parcel_id", ""))
		var bounds_data = encoded.get("bounds", [])
		if not bounds_data is Array or bounds_data.size() != 4: continue
		var parcel := {
			"id": parcel_id,
			"bounds": Rect2i(int(bounds_data[0]), int(bounds_data[1]), int(bounds_data[2]), int(bounds_data[3])),
			"rotation": int(encoded.get("rotation", 0)),
			"selected_frontage_id": str(encoded.get("selected_frontage_id", "")),
			"placement_offset": int(encoded.get("placement_offset", 0)),
			"frontage_spans": encoded.get("frontage_spans", []).duplicate(true),
		}
		var placements: Array[EnvironmentModulePlacement] = []
		for occupant in encoded.get("occupants", []):
			if not occupant is Dictionary: continue
			var record: Dictionary = placement_records.get(str(occupant.get("placement_ref", "")), {})
			var origin = record.get("origin", [])
			if origin is Array and origin.size() == 2:
				placements.append(EnvironmentModulePlacement.new(StringName(record.get("component_id", "")), Vector2i(int(origin[0]), int(origin[1])), int(record.get("rotation", 0)), int(record.get("variation", 0)), int(record.get("elevation", 0))))
		var relationship: Dictionary = access_by_parcel.get(parcel_id, {})
		if relationship.is_empty():
			_fail(failures, "MISSING_REQUIRED_RELATIONSHIP", "relationships", "%s requires a %s relationship" % [parcel_id, contract.kind], parcel_id)
			continue
		if relationship.get("kind", "") != contract.kind:
			_fail(failures, "INVALID_RELATIONSHIP_KIND", "relationships.%s" % relationship.get("relationship_id", ""), "%s requires %s" % [template_id, contract.kind], parcel_id)
		var selected := RelationshipValidator.select_frontage(parcel, template_id)
		var referenced_id := str(relationship.get("object_ref", "")).trim_prefix("frontage:")
		if selected.is_empty() or str(selected.get("frontage_id", "")) != referenced_id:
			_fail(failures, "INVALID_FRONTAGE_REFERENCE", "relationships.%s.object_ref" % relationship.get("relationship_id", ""), "functional relationship does not reference the compatible frontage", parcel_id)
		for issue in RelationshipValidator.validate_geometry(parcel, template_id, placements, catalog, selected):
			_fail(failures, str(issue.code), "relationships.%s" % relationship.get("relationship_id", ""), str(issue.message), str(issue.reference))

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
			var current_geometry := EnvironmentAssemblyContract.current_geometry_sha256(asset_id)
			if current_geometry.is_empty(): _fail(failures, "MISSING_ASSET_DEPENDENCY", "dependencies.%s" % key, "%s required by %s is unavailable" % [asset_id, record.get("placement_id", "")], key)
			elif dependency.get("geometry_sha256", "") != current_geometry: _fail(failures, "STALE_GEOMETRY_DEPENDENCY", "dependencies.%s.geometry_sha256" % key, "%s geometry revision changed" % asset_id, key)
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
		if dependency.get("kind", "") == "asset":
			var asset_id := str(dependency.get("id", ""))
			var current_geometry := EnvironmentAssemblyContract.current_geometry_sha256(asset_id)
			if current_geometry.is_empty() and bool(dependency.get("required", true)):
				_fail(failures, "MISSING_ASSET_DEPENDENCY", "dependencies.%s" % key, "%s is unavailable" % key, key)
		elif dependency.get("kind", "") == "assembly":
			var current := _assembly_dependency(str(dependency.get("id", "")))
			if not bool(current.get("available", false)):
				_fail(failures, "MISSING_ASSEMBLY_DEPENDENCY", "dependencies.%s" % key, "%s does not resolve to an authored assembly" % key, key)
			elif not bool(current.get("valid", false)):
				_fail(failures, "INVALID_ASSEMBLY_DEPENDENCY", "dependencies.%s" % key, "%s no longer satisfies its authored assembly definition" % key, key)
			elif dependency.get("certification_signature", "") != current.get("certification_signature", ""):
				_fail(failures, "STALE_ASSEMBLY_DEPENDENCY", "dependencies.%s.certification_signature" % key, "%s assembly dependency changed" % key, key)
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

static func _encoded_placement_signature(record: Dictionary) -> String:
	var origin = record.get("origin", [0, 0])
	return "%s@%s,%s,%s:r%s:v%s" % [record.get("component_id", ""), origin[0], record.get("elevation", 0), origin[1], record.get("rotation", 0), record.get("variation", 0)]

static func _assembly_dependency(assembly_id: String) -> Dictionary:
	var records := InitialEnvironmentAssemblyLibrary.records()
	if records.has(StringName(assembly_id)):
		var contract: EnvironmentAssemblyContract = records[StringName(assembly_id)].contract
		var parts: Array[String] = [String(contract.assembly_id), str(contract.role), str(contract.completeness), str(contract.certification_state)]
		for component in contract.components:
			parts.append("%s:%s:%s" % [component.get("asset_id", ""), component.get("geometry_sha256", ""), component.get("calibration_signature", "")])
		parts.sort()
		return {"kind": "assembly", "id": assembly_id, "available": true, "valid": contract.certification_state == EnvironmentAssemblyContract.CertificationState.CERTIFIED, "resolution": "certified_contract", "certification_state": "certified", "certification_signature": "|".join(parts).sha256_text(), "required_by": []}
	var buildings := IndustrialBuildingCatalog.create()
	if buildings.has(StringName(assembly_id)):
		var building: EnvironmentBuildingDefinition = buildings[StringName(assembly_id)]
		return {"kind": "assembly", "id": assembly_id, "available": true, "valid": building.validate().is_empty(), "resolution": "building_definition", "certification_state": "definition_only", "certification_signature": _building_definition_signature(building), "required_by": []}
	return {"kind": "assembly", "id": assembly_id, "available": false, "valid": false, "resolution": "missing", "certification_state": "missing", "certification_signature": "", "required_by": []}

static func _building_definition_signature(building: EnvironmentBuildingDefinition) -> String:
	var module: EnvironmentModuleDefinition = building.module
	var parts: Array[String] = [
		String(building.assembly_id), String(building.purpose), str(building.enclosure),
		"parcel=%d,%d" % [building.parcel_size.x, building.parcel_size.y],
		"module=%s:%d,%d:%d:%d:%s" % [module.component_id, module.size.x, module.size.y, module.tactical_role, module.module_type, module.visual_envelope],
		"walls=" + _cells_signature(building.wall_cells),
		"entrances=" + _cells_signature(building.entrance_cells),
		"floors=" + _cells_signature(building.usable_floor_cells),
		"roofs=" + _cells_signature(building.roof_cells),
		"clearance=" + _cells_signature(module.clearance_cells),
	]
	for asset_id in building.source_assets:
		parts.append("asset=%s:%s:%s" % [asset_id, EnvironmentAssemblyContract.current_geometry_sha256(asset_id), EnvironmentAssemblyContract.current_calibration_signature(asset_id)])
	for connection: EnvironmentModuleConnection in module.connections:
		parts.append("connection=%d,%d:%d,%d:%d:%d" % [connection.local_cell.x, connection.local_cell.y, connection.direction.x, connection.direction.y, connection.type, connection.elevation])
	parts.sort()
	return "|".join(parts).sha256_text()

static func _cells_signature(cells: Array[Vector2i]) -> String:
	var values: Array[String] = []
	for cell in cells:
		values.append("%d,%d" % [cell.x, cell.y])
	values.sort()
	return ";".join(values)

static func _fail(target: Array[Dictionary], code: String, field: String, message: String, reference := "") -> void:
	target.append({"code": code, "field": field, "reference": reference, "message": message})
