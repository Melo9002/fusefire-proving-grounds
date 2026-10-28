class_name InitialEnvironmentAssemblyLibrary
extends RefCounted
## Compact Phase 3 inventory. This intentionally avoids introducing a general
## registry before the shared layout-document work in Phase 4.

const CargoAssembly = preload("res://systems/generation/industrial_cargo_assembly_catalog.gd")

static func records(buildings := {}) -> Dictionary:
	if buildings.is_empty(): buildings = IndustrialBuildingCatalog.create()
	var building: EnvironmentBuildingDefinition = buildings[&"city_industrial_shell_i"]
	var parcel := IndustrialEquipmentParcelDefinition.new()
	var pipe_contract := IndustrialEquipmentAssemblyCatalog.contract()
	var cargo_contract := CargoAssembly.contract()
	return {
		&"city_industrial_shell_i": _record(building.assembly_contract, &"sealed_building_shell", building.validate().is_empty(), building),
		&"pipe_receiver_unit": _record(pipe_contract, &"open_machine_pipe_installation", IndustrialEquipmentAssemblyCatalog.validate_contract(pipe_contract).is_empty() and IndustrialEquipmentAssemblyCatalog.validate().is_empty()),
		&"certified_pipe_service_pad": _record(parcel.assembly_contract, &"open_equipment_loading_parcel", parcel.validate().is_empty(), parcel),
		&"shipping_container_family": _record(cargo_contract, &"standalone_tactical_obstacle_family", CargoAssembly.validate_contract(cargo_contract).is_empty()),
	}

static func validation_errors() -> PackedStringArray:
	var failures := PackedStringArray()
	var records_by_id := records()
	for id in [&"city_industrial_shell_i", &"pipe_receiver_unit", &"certified_pipe_service_pad", &"shipping_container_family"]:
		if not records_by_id.has(id):
			failures.append("MISSING_LIBRARY_EXAMPLE:%s" % id)
			continue
		var record: Dictionary = records_by_id[id]
		if not record.technically_valid: failures.append("INVALID_ASSEMBLY:%s" % id)
		var contract: EnvironmentAssemblyContract = record.contract
		if contract.assembly_id != id: failures.append("ASSEMBLY_ID_MISMATCH:%s" % id)
		if contract.components.is_empty(): failures.append("MISSING_DEPENDENCIES:%s" % id)
		if contract.supported_rotations.is_empty(): failures.append("MISSING_SUPPORTED_ORIENTATION:%s" % id)
		if contract.certification_state != EnvironmentAssemblyContract.CertificationState.CERTIFIED: failures.append("UNCERTIFIED:%s" % id)
	return failures

static func _record(contract: EnvironmentAssemblyContract, classification: StringName, technically_valid: bool, definition = null) -> Dictionary:
	return {"contract": contract, "definition": definition, "classification": classification, "technically_valid": technically_valid, "owner_visual_approval": false}
