class_name IndustrialEquipmentAssemblyCatalog
extends RefCounted

const RECEIVER := "factory_kit/machine-connection-hole"
const PIPE := "factory_kit/pipe-large"

static func receiver_socket() -> EnvironmentGeometricSocket:
	var socket := EnvironmentGeometricSocket.new(&"receiver_top", &"factory_pipe")
	socket.role = EnvironmentGeometricSocket.Role.RECEIVER
	socket.local_frame = Transform3D(Basis(Vector3.FORWARD, Vector3.RIGHT, Vector3.UP), Vector3(0, 1.293, 0.36))
	socket.seam_size = Vector2(1.0, 1.0)
	socket.required = true
	return socket

static func pipe_socket() -> EnvironmentGeometricSocket:
	var socket := EnvironmentGeometricSocket.new(&"pipe_negative_x", &"factory_pipe")
	socket.role = EnvironmentGeometricSocket.Role.PLUG
	socket.local_frame = Transform3D(Basis(Vector3.FORWARD, Vector3.UP, Vector3.LEFT), Vector3(-0.5, 0.5, 0))
	socket.seam_size = Vector2(1.0, 1.0)
	socket.required = true
	return socket

static func component_transforms() -> Dictionary:
	var result := EnvironmentGeometricSocket.attachment_transform(receiver_socket(), pipe_socket())
	assert(result.ok)
	return {&"receiver_machine": Transform3D.IDENTITY, &"vertical_pipe": result.transform}

static func contract() -> EnvironmentAssemblyContract:
	var result := EnvironmentAssemblyContract.new(&"pipe_receiver_unit")
	result.role = EnvironmentAssemblyContract.AssemblyRole.EQUIPMENT_PARCEL
	result.completeness = EnvironmentAssemblyContract.Completeness.INTENTIONALLY_OPEN
	for asset_id in [RECEIVER, PIPE]:
		result.components.append({"asset_id": asset_id, "required": true, "geometry_sha256": EnvironmentAssemblyContract.current_geometry_sha256(asset_id), "calibration_signature": EnvironmentAssemblyContract.current_calibration_signature(asset_id)})
	result.tactical_footprint.assign(module().footprint_cells)
	result.approved_visual_envelope = module().visual_envelope
	result.required_clearance_cells.assign(module().clearance_cells)
	result.relationships = {"required_attachment": {"from": &"receiver_top", "to": &"pipe_negative_x"}, "external_interface": {"socket": &"pipe_positive_x", "purpose": &"future_service_extension"}}
	result.supported_rotations = [0, 1, 2, 3]
	result.certification_state = EnvironmentAssemblyContract.CertificationState.CERTIFIED
	return result

static func validate_contract(value: EnvironmentAssemblyContract) -> PackedStringArray:
	var failures := PackedStringArray()
	if value.assembly_id != &"pipe_receiver_unit": failures.append("ASSEMBLY_ID_MISMATCH")
	for component in value.components:
		var asset_id: String = component.asset_id
		if EnvironmentAssemblyContract.current_geometry_sha256(asset_id).is_empty():
			failures.append("MISSING_REQUIRED_ASSET")
		elif component.geometry_sha256 != EnvironmentAssemblyContract.current_geometry_sha256(asset_id):
			failures.append("STALE_GEOMETRY_DEPENDENCY")
		if component.calibration_signature != EnvironmentAssemblyContract.current_calibration_signature(asset_id):
			failures.append("STALE_CALIBRATION_DEPENDENCY")
	if value.completeness != EnvironmentAssemblyContract.Completeness.INTENTIONALLY_OPEN: failures.append("UNSUPPORTED_COMPLETENESS")
	return failures

static func module() -> EnvironmentModuleDefinition:
	var item := EnvironmentModuleDefinition.new(&"factory_pipe_receiver_unit", &"factory_equipment", Vector2i(2, 3))
	item.set_tactical_role(EnvironmentModuleDefinition.TacticalRole.SOLID_OBSTACLE)
	item.set_module_type(EnvironmentModuleDefinition.ModuleType.MACHINERY)
	for cell in item.footprint_cells:
		item.set_effect(cell, {"interaction": EnvironmentModuleDefinition.CellInteraction.BLOCKED, "cover_type": MapCellData.CoverType.FULL, "cover_height": 3.45, "walkable": false, "can_stop": false, "blocks_los": true, "movement_cost": 1})
	item.clearance_cells.assign([Vector2i(0, 3), Vector2i(1, 3)])
	item.set_visual_envelope(AABB(Vector3(-0.4, 0.11, -0.125), Vector3(1.8, 3.44, 2.415)))
	item.structural_assembly_id = &"pipe_receiver_unit"
	item.architectural_purpose = &"factory_pipe_receiver"
	item.assembly_enclosure = &"intentionally_open_equipment"
	item.assembly_complete = true
	item.assembly_notes = "Measured receiver/plug seam; upper pipe end remains an explicit service interface."
	item.add_socket_assembly_visual([
		{"component_id": &"receiver_machine", "asset_id": RECEIVER, "transform": Transform3D.IDENTITY, "scale": 1.5},
		{"component_id": &"vertical_pipe", "asset_id": PIPE, "transform": component_transforms().vertical_pipe, "scale": 1.5},
	], Vector2(0.5, 1.0), &"equipment_assembly", Vector3(0, 0.11, 0))
	return item

static func validate(transforms := {}, external_interface_present := true, geometry_overlaps := false) -> PackedStringArray:
	var failures := PackedStringArray()
	var placed: Dictionary = component_transforms() if transforms.is_empty() else transforms
	if not placed.has(&"receiver_machine") or not placed.has(&"vertical_pipe"):
		failures.append("MISSING_REQUIRED_COMPONENT")
		return failures
	var alignment := EnvironmentGeometricSocket.validate_alignment(receiver_socket(), placed.receiver_machine, pipe_socket(), placed.vertical_pipe)
	if not alignment.is_empty(): failures.append(alignment)
	if not external_interface_present: failures.append("MISSING_TERMINATION")
	if geometry_overlaps: failures.append("INVALID_GEOMETRIC_OVERLAP")
	return failures
