class_name IndustrialEquipmentParcelDefinition
extends RefCounted
## One bounded authored service parcel. Physical mating remains owned by the
## nested socket assembly; access and maintenance are explicit spatial rules.

const PARCEL_ID := &"certified_pipe_service_pad"
const SIZE := Vector2i(10, 10)
const SUPPORT_ASSET := "city_kit_roads/tile-low"

var assembly_contract: EnvironmentAssemblyContract
var required_placements: Array[EnvironmentModulePlacement] = []
var optional_placements: Array[EnvironmentModulePlacement] = []
var service_connection := Vector2i(0, 4)
var operator_approach: Array[Vector2i] = [Vector2i(0, 4), Vector2i(1, 4), Vector2i(1, 5), Vector2i(2, 5), Vector2i(3, 5)]
var loading_approach: Array[Vector2i] = [Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5)]
var blocked_access_overrides: Array[Vector2i] = []
var equipment_termination_present := true
var force_unsupported_geometry := false
var optional_dressing_available := true

func _init() -> void:
	required_placements = [
		EnvironmentModulePlacement.new(&"paved_courtyard", Vector2i.ZERO),
		EnvironmentModulePlacement.new(&"factory_pipe_receiver_unit", Vector2i(2, 2)),
	]
	optional_placements = [
		EnvironmentModulePlacement.new(&"cargo_container", Vector2i(7, 0), 0, 0),
		EnvironmentModulePlacement.new(&"yard_fence", Vector2i(9, 6)),
	]
	assembly_contract = _create_contract()

func duplicate_definition() -> IndustrialEquipmentParcelDefinition:
	var copy := IndustrialEquipmentParcelDefinition.new()
	copy.required_placements = _duplicate_placements(required_placements)
	copy.optional_placements = _duplicate_placements(optional_placements)
	copy.operator_approach.assign(operator_approach)
	copy.loading_approach.assign(loading_approach)
	copy.blocked_access_overrides.assign(blocked_access_overrides)
	copy.equipment_termination_present = equipment_termination_present
	copy.force_unsupported_geometry = force_unsupported_geometry
	copy.optional_dressing_available = optional_dressing_available
	copy.assembly_contract = assembly_contract.duplicate_contract()
	return copy

func placements(origin := Vector2i.ZERO, include_optional := true, parcel_rotation := 0) -> Array[EnvironmentModulePlacement]:
	var result: Array[EnvironmentModulePlacement] = []
	var catalog := IndustrialModuleCatalog.create()
	for placement in required_placements:
		result.append(_rotated_placement(placement, catalog[placement.component_id], parcel_rotation, origin))
	if include_optional and optional_dressing_available:
		for placement in optional_placements:
			result.append(_rotated_placement(placement, catalog[placement.component_id], parcel_rotation, origin))
	return result

func rotated_relationship_cells(cells: Array[Vector2i], rotation: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell in cells: result.append(_rotate_parcel_cell(cell, rotation))
	return result

func validate() -> PackedStringArray:
	var failures := PackedStringArray()
	var catalog := IndustrialModuleCatalog.create()
	var required_ids := [&"paved_courtyard", &"factory_pipe_receiver_unit"]
	for id in required_ids:
		if not required_placements.any(func(value): return value.component_id == id):
			failures.append("MISSING_REQUIRED_COMPONENT:%s" % id)
	if not failures.is_empty(): return failures
	if force_unsupported_geometry:
		failures.append("UNSUPPORTED_GEOMETRY:parcel configuration is not certified")
	for error in IndustrialEquipmentAssemblyCatalog.validate({}, equipment_termination_present):
		failures.append(error)
	for error in _validate_dependencies(): failures.append(error)
	var layout := EnvironmentModuleLayout.new(PARCEL_ID, 3303)
	for placement in required_placements:
		var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
		if definition == null or not layout.try_add(definition, placement, SIZE):
			failures.append("INVALID_REQUIRED_PLACEMENT:%s:%s" % [placement.component_id, ";".join(layout.errors)])
			return failures
	if optional_dressing_available:
		for placement in optional_placements:
			var definition: EnvironmentModuleDefinition = catalog.get(placement.component_id)
			if definition != null:
				layout.try_add(definition, placement, SIZE) # Optional rejection does not invalidate function.
	var equipment := required_placements.filter(func(value): return value.component_id == &"factory_pipe_receiver_unit")[0] as EnvironmentModulePlacement
	var equipment_definition: EnvironmentModuleDefinition = catalog[equipment.component_id]
	var required_clearance := layout.world_clearance_cells(equipment_definition, equipment)
	for cell in required_clearance:
		if cell not in operator_approach:
			failures.append("INVALID_CLEARANCE:operator approach omits %s" % cell)
	for cell in operator_approach:
		if cell in blocked_access_overrides or _blocked_by_required(cell, catalog):
			failures.append("BLOCKED_OPERATOR_ACCESS:%s" % cell)
	for cell in loading_approach:
		if cell in blocked_access_overrides or _blocked_by_required(cell, catalog):
			failures.append("BLOCKED_LOADING_ACCESS:%s" % cell)
	if operator_approach.is_empty() or operator_approach[0] != service_connection or not _path_is_contiguous(operator_approach):
		failures.append("INVALID_SERVICE_ROUTE:operator path must begin at the parcel boundary and remain contiguous")
	if service_connection.x != 0:
		failures.append("INVALID_SERVICE_CONNECTION:connection is not on the certified west boundary")
	if failures.is_empty():
		for rotation in assembly_contract.supported_rotations:
			var rotated_layout := EnvironmentModuleLayout.new(PARCEL_ID, 3303)
			var rotated_placements := placements(Vector2i.ZERO, true, rotation)
			for placement in rotated_placements:
				if not rotated_layout.try_add(catalog[placement.component_id], placement, SIZE):
					failures.append("UNSUPPORTED_ROTATION:r%d:%s" % [rotation, ";".join(rotated_layout.errors)])
					break
			var rotated_operator := rotated_relationship_cells(operator_approach, rotation)
			for cell in rotated_operator:
				if _blocked_by_placements(cell, rotated_placements, catalog):
					failures.append("BLOCKED_OPERATOR_ACCESS:r%d:%s" % [rotation, cell])
			var rotated_equipment := rotated_placements.filter(func(value): return value.component_id == &"factory_pipe_receiver_unit")[0] as EnvironmentModulePlacement
			for clearance in rotated_layout.world_clearance_cells(catalog[rotated_equipment.component_id], rotated_equipment):
				if clearance not in rotated_operator: failures.append("INVALID_CLEARANCE:r%d:%s" % [rotation, clearance])
	return failures

func certification_signature() -> String:
	var placement_parts: Array[String] = []
	for placement in required_placements: placement_parts.append(placement.signature())
	for placement in optional_placements: placement_parts.append("optional:" + placement.signature())
	var dependency_parts: Array[String] = []
	for component in assembly_contract.components:
		dependency_parts.append("%s:%s:%s" % [component.asset_id, component.get("geometry_sha256", "optional"), component.get("calibration_signature", "optional")])
	var operator_parts: Array[String] = []
	var loading_parts: Array[String] = []
	for cell in operator_approach: operator_parts.append("%d,%d" % [cell.x, cell.y])
	for cell in loading_approach: loading_parts.append("%d,%d" % [cell.x, cell.y])
	return "%s|%s|%s|%s|%s" % [PARCEL_ID, ",".join(placement_parts), ";".join(operator_parts), ";".join(loading_parts), ",".join(dependency_parts)]

func _create_contract() -> EnvironmentAssemblyContract:
	var result := EnvironmentAssemblyContract.new(PARCEL_ID)
	result.role = EnvironmentAssemblyContract.AssemblyRole.EQUIPMENT_PARCEL
	result.completeness = EnvironmentAssemblyContract.Completeness.INTENTIONALLY_OPEN
	for asset_id in [SUPPORT_ASSET, IndustrialEquipmentAssemblyCatalog.RECEIVER, IndustrialEquipmentAssemblyCatalog.PIPE]:
		result.components.append({"asset_id": asset_id, "required": true, "geometry_sha256": EnvironmentAssemblyContract.current_geometry_sha256(asset_id), "calibration_signature": EnvironmentAssemblyContract.current_calibration_signature(asset_id)})
	result.components.append({"asset_id": "city_kit_industrial/shipping-container-a", "required": false})
	result.tactical_footprint.assign(IndustrialEquipmentAssemblyCatalog.module().footprint_cells)
	result.approved_visual_envelope = AABB(Vector3.ZERO, Vector3(10, 3.55, 10))
	result.required_clearance_cells.assign(operator_approach)
	result.relationships = {
		"support_surface": {"component": &"paved_courtyard", "required": true},
		"primary_equipment": {"assembly": &"pipe_receiver_unit", "required": true},
		"service_connection": service_connection,
		"operator_approach": operator_approach.duplicate(),
		"loading_approach": loading_approach.duplicate(),
		"optional_dressing": [&"cargo_container", &"yard_fence"],
	}
	result.supported_rotations = [0, 1, 2, 3]
	result.certification_state = EnvironmentAssemblyContract.CertificationState.CERTIFIED
	return result

func _validate_dependencies() -> PackedStringArray:
	var failures := PackedStringArray()
	for component in assembly_contract.components:
		if not component.get("required", false): continue
		var asset_id: String = component.asset_id
		if EnvironmentAssemblyContract.current_geometry_sha256(asset_id).is_empty():
			failures.append("MISSING_REQUIRED_ASSET:%s" % asset_id)
		elif component.geometry_sha256 != EnvironmentAssemblyContract.current_geometry_sha256(asset_id):
			failures.append("STALE_GEOMETRY_DEPENDENCY:%s" % asset_id)
		if component.calibration_signature != EnvironmentAssemblyContract.current_calibration_signature(asset_id):
			failures.append("STALE_CALIBRATION_DEPENDENCY:%s" % asset_id)
	return failures

func _blocked_by_required(cell: Vector2i, catalog: Dictionary) -> bool:
	return _blocked_by_placements(cell, required_placements, catalog)

static func _blocked_by_placements(cell: Vector2i, placement_list: Array, catalog: Dictionary) -> bool:
	for placement in placement_list:
		var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
		if definition.placement_layer == EnvironmentModuleDefinition.PlacementLayer.GROUND: continue
		for occupied in definition.rotated_cells(definition.footprint_cells, placement.rotation):
			if placement.origin + occupied == cell: return true
	return false

static func _path_is_contiguous(cells: Array[Vector2i]) -> bool:
	for index in range(1, cells.size()):
		if cells[index - 1].distance_squared_to(cells[index]) != 1: return false
	return true

static func _duplicate_placements(source: Array[EnvironmentModulePlacement]) -> Array[EnvironmentModulePlacement]:
	var result: Array[EnvironmentModulePlacement] = []
	for value in source:
		result.append(EnvironmentModulePlacement.new(value.component_id, value.origin, value.rotation, value.variation, value.elevation))
	return result

static func _rotate_parcel_cell(cell: Vector2i, rotation: int) -> Vector2i:
	var result := cell
	for _step in posmod(rotation, 4): result = Vector2i(SIZE.y - 1 - result.y, result.x)
	return result

static func _rotated_placement(placement: EnvironmentModulePlacement, definition: EnvironmentModuleDefinition, rotation: int, origin: Vector2i) -> EnvironmentModulePlacement:
	var transformed: Array[Vector2i] = []
	for cell in definition.rotated_cells(definition.footprint_cells, placement.rotation):
		transformed.append(_rotate_parcel_cell(placement.origin + cell, rotation))
	var minimum := transformed[0]
	for point in transformed:
		minimum.x = mini(minimum.x, point.x)
		minimum.y = mini(minimum.y, point.y)
	return EnvironmentModulePlacement.new(placement.component_id, origin + minimum, placement.rotation + rotation, placement.variation, placement.elevation)
