class_name EnvironmentParcelRelationshipValidator
extends RefCounted
## Bounded functional contracts for the parcel recipes currently authored by
## CoherentEnvironmentAssembler. This is deliberately a validator, not a
## search language: each recipe declares only the relationships it actually
## supports.

const ParcelContract = preload("res://systems/generation/environment_parcel_spatial_contract.gd")
const ReservationLedger = preload("res://systems/generation/environment_spatial_reservation_ledger.gd")

const CONTRACTS := {
	"industrial_yard_block": {"kind": ParcelContract.LOADING_ACCESS, "local_edge": Vector2i.DOWN, "minimum_width": 4, "required": [&"paved_courtyard", &"industrial_loading_canopy", &"machine_cover_cluster"], "classification": "open_industrial_yard"},
	"loading_bay": {"kind": ParcelContract.LOADING_ACCESS, "local_edge": Vector2i.DOWN, "minimum_width": 4, "required": [&"paved_courtyard", &"industrial_loading_canopy"], "classification": "open_loading_bay"},
	"equipment_compound": {"kind": ParcelContract.SERVICE_CLEARANCE, "local_edge": Vector2i.LEFT, "minimum_width": 3, "required": [&"paved_courtyard", &"factory_pipe_receiver_unit"], "classification": "open_equipment_area"},
	"service_alley": {"kind": ParcelContract.PEDESTRIAN_ACCESS, "local_edge": Vector2i.DOWN, "minimum_width": 2, "required": [&"paved_alley"], "classification": "open_service_alley"},
	"staging_pad": {"kind": ParcelContract.LOADING_ACCESS, "local_edge": Vector2i.DOWN, "minimum_width": 4, "required": [&"paved_courtyard"], "classification": "open_staging_pad"},
	"public_forecourt": {"kind": ParcelContract.PEDESTRIAN_ACCESS, "local_edge": Vector2i.DOWN, "minimum_width": 2, "required": [&"paved_courtyard"], "classification": "open_forecourt"},
}

static func contract_for(template_id: String) -> Dictionary:
	if template_id.begins_with("building_frontage/"):
		return {"kind": ParcelContract.PEDESTRIAN_ACCESS, "local_edge": Vector2i.DOWN, "minimum_width": 2, "required": [&"paved_courtyard", StringName(template_id.trim_prefix("building_frontage/"))], "classification": "sealed_exterior_frontage"}
	return (CONTRACTS.get(template_id, {}) as Dictionary).duplicate(true)

static func select_frontage(parcel: Dictionary, template_id: String) -> Dictionary:
	var candidates := frontage_candidates(parcel, template_id)
	var selected_id := str(parcel.get("selected_frontage_id", ""))
	if not selected_id.is_empty():
		for candidate in candidates:
			if str(candidate.get("frontage_id", "")) == selected_id: return candidate
	return candidates[0] if not candidates.is_empty() else {}

static func frontage_candidates(parcel: Dictionary, template_id: String) -> Array[Dictionary]:
	var contract := contract_for(template_id)
	if contract.is_empty(): return []
	var candidates: Array[Dictionary] = []
	for span in parcel.get("frontage_spans", []):
		if span is Dictionary and int(span.get("width_cells", 0)) >= int(contract.minimum_width):
			candidates.append(span)
	# Stable preference: widest span, then the authored boundary order already
	# carried by frontage_id. This remains deterministic for equivalent input.
	candidates.sort_custom(func(a, b):
		if int(a.width_cells) != int(b.width_cells): return int(a.width_cells) > int(b.width_cells)
		return str(a.frontage_id) < str(b.frontage_id))
	return candidates

static func rotation_for_frontage(template_id: String, span: Dictionary) -> int:
	var contract := contract_for(template_id)
	if contract.is_empty(): return 0
	var encoded = span.get("outward_direction", [])
	if not encoded is Array or encoded.size() != 2: return -1
	var expected := Vector2i(int(encoded[0]), int(encoded[1]))
	var helper := EnvironmentModuleDefinition.new(&"relationship_rotation", &"diagnostic", Vector2i.ONE)
	for rotation in 4:
		if helper.rotate_direction(contract.local_edge, rotation) == expected: return rotation
	return -1

static func validate_geometry(parcel: Dictionary, template_id: String, placements: Array, catalog: Dictionary, span: Dictionary = {}) -> Array[Dictionary]:
	var failures: Array[Dictionary] = []
	var contract := contract_for(template_id)
	if contract.is_empty(): return failures
	var parcel_id := str(parcel.get("id", parcel.get("parcel_id", "")))
	if span.is_empty(): span = select_frontage(parcel, template_id)
	if span.is_empty():
		_fail(failures, "MISSING_REQUIRED_FRONTAGE", parcel_id, "", "no frontage span satisfies %s's %d-cell requirement" % [template_id, contract.minimum_width])
		return failures
	if int(span.get("width_cells", 0)) < int(contract.minimum_width):
		_fail(failures, "INSUFFICIENT_FRONTAGE_WIDTH", parcel_id, str(span.get("frontage_id", "")), "frontage width %d is less than required width %d" % [span.get("width_cells", 0), contract.minimum_width])
	var rotation := int(parcel.get("rotation", rotation_for_frontage(template_id, span)))
	var encoded = span.get("outward_direction", [])
	var outward := Vector2i(int(encoded[0]), int(encoded[1])) if encoded is Array and encoded.size() == 2 else Vector2i.ZERO
	var helper := EnvironmentModuleDefinition.new(&"relationship_rotation", &"diagnostic", Vector2i.ONE)
	if helper.rotate_direction(contract.local_edge, rotation) != outward:
		_fail(failures, "INVALID_FRONTAGE_ORIENTATION", parcel_id, str(span.get("frontage_id", "")), "%s local access edge does not face the referenced street" % template_id)
	var counts: Dictionary = {}
	for placement: EnvironmentModulePlacement in placements: counts[placement.component_id] = int(counts.get(placement.component_id, 0)) + 1
	for required_id in contract.required:
		if int(counts.get(required_id, 0)) == 0:
			_fail(failures, "MISSING_REQUIRED_OCCUPANT", parcel_id, str(required_id), "%s requires %s" % [template_id, required_id])
	var bounds: Rect2i = parcel.get("bounds", Rect2i())
	var role := ParcelContract.reservation_role_for_template(template_id)
	var access_cells := relationship_cells(parcel, template_id, placements, catalog, span)
	for placement: EnvironmentModulePlacement in placements:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null or definition.placement_layer == EnvironmentModuleDefinition.PlacementLayer.GROUND: continue
		var occupied := _world_cells(definition, placement)
		for cell in access_cells:
			if cell in occupied:
				var code := "BLOCKED_PEDESTRIAN_APPROACH" if contract.kind == ParcelContract.PEDESTRIAN_ACCESS else ("BLOCKED_LOADING_CLEARANCE" if contract.kind == ParcelContract.LOADING_ACCESS else "MISSING_SERVICE_CLEARANCE")
				_fail(failures, code, parcel_id, placement.signature(), "%s blocks required access cell %s" % [placement.component_id, cell])
				break
	if template_id == "equipment_compound":
		_validate_equipment_service(parcel, placements, catalog, span, failures)
	return failures

static func validate_tactical(parcel: Dictionary, template_id: String, data: MapData, graph: Pathfinder, span: Dictionary = {}) -> Array[Dictionary]:
	var failures: Array[Dictionary] = []
	var contract := contract_for(template_id)
	if contract.is_empty(): return failures
	var parcel_id := str(parcel.get("id", parcel.get("parcel_id", "")))
	if span.is_empty(): span = select_frontage(parcel, template_id)
	if span.is_empty(): return failures
	var bounds: Rect2i = parcel.get("bounds", Rect2i())
	var placements: Array[EnvironmentModulePlacement] = []
	for placement: EnvironmentModulePlacement in data.environment_modules:
		if _placement_within_parcel(placement, bounds): placements.append(placement)
	var cells := relationship_cells(parcel, template_id, placements, IndustrialModuleCatalog.create(), span)
	var usable: Array[Vector3i] = []
	for cell in cells:
		var position := Vector3i(cell.x, 0, cell.y)
		var tactical := data.get_cell(position)
		if tactical == null or not tactical.walkable or not tactical.can_stop:
			var code := "MISSING_TACTICAL_ACCESS" if contract.kind == ParcelContract.PEDESTRIAN_ACCESS else ("BLOCKED_LOADING_CLEARANCE" if contract.kind == ParcelContract.LOADING_ACCESS else "MISSING_SERVICE_CLEARANCE")
			_fail(failures, code, parcel_id, str(cell), "required access cell %s is not a walkable stopping cell in MapData" % cell)
		else: usable.append(position)
	if usable.size() >= 2 and graph.calculate_3d_path(usable[0], usable[-1]).is_empty():
		_fail(failures, "MISSING_TACTICAL_ACCESS", parcel_id, str(span.get("frontage_id", "")), "physical approach exists but MapData has no tactical route across it")
	return failures

static func relationship_properties(parcel: Dictionary, template_id: String, span: Dictionary, placements: Array = [], catalog: Dictionary = {}) -> Dictionary:
	var contract := contract_for(template_id)
	if contract.is_empty() or span.is_empty(): return {}
	var bounds: Rect2i = parcel.get("bounds", Rect2i())
	var cells := relationship_cells(parcel, template_id, placements, catalog, span) if not placements.is_empty() and not catalog.is_empty() else ReservationLedger.frontage_access_cells(span, bounds, ParcelContract.reservation_role_for_template(template_id))
	var encoded_cells: Array = []
	for cell in cells: encoded_cells.append([cell.x, cell.y])
	return {
		"frontage_id": str(span.get("frontage_id", "")),
		"minimum_width_cells": int(contract.minimum_width),
		"local_access_direction": [contract.local_edge.x, contract.local_edge.y],
		"expected_outward_direction": span.get("outward_direction", []).duplicate(),
		"access_cells": encoded_cells,
		"classification": contract.classification,
	}

static func relationship_cells(parcel: Dictionary, template_id: String, placements: Array, catalog: Dictionary, span: Dictionary) -> Array[Vector2i]:
	var bounds: Rect2i = parcel.get("bounds", Rect2i())
	var contract := contract_for(template_id)
	if contract.is_empty(): return []
	var boundary := ReservationLedger.frontage_access_cells(span, bounds, ParcelContract.reservation_role_for_template(template_id))
	if template_id == "equipment_compound":
		var equipment := IndustrialEquipmentParcelDefinition.new()
		var route := equipment.rotated_relationship_cells(equipment.operator_approach, int(parcel.get("rotation", 0)))
		for index in route.size(): route[index] += bounds.position
		for cell in boundary:
			if cell not in route: route.append(cell)
		return route
	if not template_id.begins_with("building_frontage/"): return boundary
	var shell_id := StringName(template_id.trim_prefix("building_frontage/"))
	var shell: EnvironmentModulePlacement
	for placement: EnvironmentModulePlacement in placements:
		if placement.component_id == shell_id:
			shell = placement
			break
	var definition: EnvironmentModuleDefinition = catalog.get(shell_id)
	if shell == null or definition == null: return boundary
	var outward: Vector2i = definition.rotate_direction(Vector2i.DOWN, shell.rotation)
	var center := (definition.size.x - 1) / 2
	var result: Array[Vector2i] = []
	for local_x in [center, mini(center + 1, definition.size.x - 1)]:
		var edge := shell.origin + definition.rotate_cell(Vector2i(local_x, definition.size.y - 1), shell.rotation)
		var cursor := edge + outward
		while bounds.has_point(cursor):
			if cursor not in result: result.append(cursor)
			cursor += outward
		if cursor not in result: result.append(cursor)
	return result

static func _validate_equipment_service(parcel: Dictionary, placements: Array, catalog: Dictionary, span: Dictionary, failures: Array[Dictionary]) -> void:
	var definition := IndustrialEquipmentParcelDefinition.new()
	var bounds: Rect2i = parcel.get("bounds", Rect2i())
	var rotation := int(parcel.get("rotation", 0))
	var operator := definition.rotated_relationship_cells(definition.operator_approach, rotation)
	for index in operator.size(): operator[index] += bounds.position
	var access := ReservationLedger.frontage_access_cells(span, bounds, ReservationLedger.LOADING_SERVICE_APPROACH)
	if operator.is_empty() or operator[0] not in access:
		_fail(failures, "INVALID_SERVICE_CONNECTION", str(parcel.get("id", "")), str(span.get("frontage_id", "")), "certified operator route does not begin at the selected street frontage")
	for cell in operator:
		for placement: EnvironmentModulePlacement in placements:
			var module: EnvironmentModuleDefinition = catalog.get(placement.component_id)
			if module == null or module.placement_layer == EnvironmentModuleDefinition.PlacementLayer.GROUND: continue
			if cell in _world_cells(module, placement):
				_fail(failures, "MISSING_SERVICE_CLEARANCE", str(parcel.get("id", "")), placement.signature(), "%s obstructs certified service cell %s" % [placement.component_id, cell])
				return

static func _world_cells(definition: EnvironmentModuleDefinition, placement: EnvironmentModulePlacement) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in definition.rotated_cells(definition.footprint_cells, placement.rotation): result.append(placement.origin + cell)
	return result

static func _placement_within_parcel(placement: EnvironmentModulePlacement, bounds: Rect2i) -> bool:
	return bounds.has_point(placement.origin)

static func _fail(target: Array[Dictionary], code: String, parcel_id: String, reference: String, message: String) -> void:
	target.append({"code": code, "parcel_id": parcel_id, "reference": reference, "message": message})
