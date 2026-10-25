class_name InitialEnvironmentAssemblyLibrary
extends RefCounted
## Compact Phase 3 inventory. This intentionally avoids introducing a general
## registry before the shared layout-document work in Phase 4.

const CargoAssembly = preload("res://systems/generation/industrial_cargo_assembly_catalog.gd")

static func records() -> Dictionary:
	var buildings := IndustrialBuildingCatalog.create()
	var building: EnvironmentBuildingDefinition = buildings[&"city_industrial_shell_i"]
	var parcel := IndustrialEquipmentParcelDefinition.new()
	return {
		&"city_industrial_shell_i": _record(building.assembly_contract, &"sealed_building_shell", true),
		&"pipe_receiver_unit": _record(IndustrialEquipmentAssemblyCatalog.contract(), &"open_machine_pipe_installation", true),
		&"certified_pipe_service_pad": _record(parcel.assembly_contract, &"open_equipment_loading_parcel", parcel.validate().is_empty()),
		&"shipping_container_family": _record(CargoAssembly.contract(), &"standalone_tactical_obstacle_family", CargoAssembly.validate_contract(CargoAssembly.contract()).is_empty()),
	}

static func validation_errors() -> PackedStringArray:
	var failures := PackedStringArray()
	var records_by_id := records()
	for id in [&"city_industrial_shell_i", &"pipe_receiver_unit", &"certified_pipe_service_pad", &"shipping_container_family"]:
		if not records_by_id.has(id):
			failures.append("MISSING_LIBRARY_EXAMPLE:%s" % id)
			continue
		var record: Dictionary = records_by_id[id]
		var contract: EnvironmentAssemblyContract = record.contract
		if contract.assembly_id != id: failures.append("ASSEMBLY_ID_MISMATCH:%s" % id)
		if contract.components.is_empty(): failures.append("MISSING_DEPENDENCIES:%s" % id)
		if contract.supported_rotations.is_empty(): failures.append("MISSING_SUPPORTED_ORIENTATION:%s" % id)
		if contract.certification_state != EnvironmentAssemblyContract.CertificationState.CERTIFIED: failures.append("UNCERTIFIED:%s" % id)
	return failures

static func _record(contract: EnvironmentAssemblyContract, classification: StringName, technically_valid: bool) -> Dictionary:
	return {"contract": contract, "classification": classification, "technically_valid": technically_valid, "owner_visual_approval": false}
