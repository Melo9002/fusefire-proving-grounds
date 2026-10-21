extends SceneTree

var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var parcel := IndustrialEquipmentParcelDefinition.new()
	_test_positive(parcel)
	_test_negative(parcel)
	_test_library()
	await _test_map_and_presentation(parcel)
	print("Certified equipment parcel: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_positive(parcel: IndustrialEquipmentParcelDefinition) -> void:
	check(parcel.validate().is_empty(), "certified open pipe-service pad validates: %s" % ";".join(parcel.validate()))
	check(parcel.assembly_contract.role == EnvironmentAssemblyContract.AssemblyRole.EQUIPMENT_PARCEL, "parcel has an explicit equipment-parcel role")
	check(parcel.assembly_contract.completeness == EnvironmentAssemblyContract.Completeness.INTENTIONALLY_OPEN, "open service pad is not misclassified as an enclosure")
	check(parcel.required_placements.size() == 2 and parcel.optional_placements.size() == 2, "required support/equipment are distinct from optional cargo/fence dressing")
	check(parcel.assembly_contract.supported_rotations == [0, 1, 2, 3], "whole-parcel relationships support all canonical road-facing rotations")
	check(parcel.operator_approach.front() == parcel.service_connection and parcel.operator_approach.back() == Vector2i(3, 5), "operator approach runs from the west service boundary to equipment clearance")
	var repeated := IndustrialEquipmentParcelDefinition.new()
	check(parcel.certification_signature() == repeated.certification_signature(), "identical definitions and dependencies reconstruct deterministically")
	var without_dressing := parcel.duplicate_definition()
	without_dressing.optional_dressing_available = false
	check(without_dressing.validate().is_empty(), "optional dressing failure does not invalidate parcel function")

func _test_negative(source: IndustrialEquipmentParcelDefinition) -> void:
	var broken := source.duplicate_definition()
	broken.required_placements = broken.required_placements.filter(func(value): return value.component_id != &"factory_pipe_receiver_unit")
	check(_has_code(broken.validate(), "MISSING_REQUIRED_COMPONENT"), "missing primary equipment is rejected")

	broken = source.duplicate_definition()
	broken.equipment_termination_present = false
	check(_has_code(broken.validate(), "MISSING_TERMINATION"), "missing required physical termination is rejected")

	broken = source.duplicate_definition()
	broken.blocked_access_overrides.append(Vector2i(1, 4))
	check(_has_code(broken.validate(), "BLOCKED_OPERATOR_ACCESS"), "blocked operator access is rejected")

	broken = source.duplicate_definition()
	broken.blocked_access_overrides.append(Vector2i(0, 3))
	check(_has_code(broken.validate(), "BLOCKED_LOADING_ACCESS"), "blocked loading approach is rejected separately")

	broken = source.duplicate_definition()
	broken.operator_approach.erase(Vector2i(2, 5))
	check(_has_code(broken.validate(), "INVALID_CLEARANCE"), "missing equipment service clearance is rejected")

	broken = source.duplicate_definition()
	broken.force_unsupported_geometry = true
	check(_has_code(broken.validate(), "UNSUPPORTED_GEOMETRY"), "unsupported parcel geometry remains uncertified")

	broken = source.duplicate_definition()
	broken.assembly_contract.components[0].geometry_sha256 = "stale"
	check(_has_code(broken.validate(), "STALE_GEOMETRY_DEPENDENCY"), "changed support geometry invalidates parcel certification")

	broken = source.duplicate_definition()
	broken.assembly_contract.components[1].calibration_signature = "stale"
	check(_has_code(broken.validate(), "STALE_CALIBRATION_DEPENDENCY"), "changed equipment calibration invalidates parcel certification")

func _test_library() -> void:
	var records := InitialEnvironmentAssemblyLibrary.records()
	check(records.size() == 3 and InitialEnvironmentAssemblyLibrary.validation_errors().is_empty(), "initial library contains three internally consistent certified examples")
	check(records.city_industrial_shell_i.classification == &"sealed_building_shell", "building-i remains the sealed exterior example")
	check(records.pipe_receiver_unit.classification == &"open_machine_pipe_installation", "socket assembly remains accurately classified as equipment")
	check(records.certified_pipe_service_pad.classification == &"open_equipment_loading_parcel", "parcel records its open functional role")
	check(records.values().all(func(record): return record.technically_valid and not record.owner_visual_approval), "technical certification remains distinct from owner visual approval")

func _test_map_and_presentation(parcel: IndustrialEquipmentParcelDefinition) -> void:
	var data := FlatMapGenerator.generate(32, 32, 1.0, 3303)
	var layout := ModularIndustrialLayoutBuilder.apply(data, 1.0, 3303, &"certified_equipment_parcel")
	check(layout.errors.is_empty(), "authored parcel compiles with its connected imported road: %s" % ";".join(layout.errors))
	var world_operator := parcel.operator_approach.map(func(cell): return cell + Vector2i(10, 10))
	check(world_operator.all(func(cell): return data.get_cell(Vector3i(cell.x, 0, cell.y)).walkable), "MapData independently keeps the operator route tactically traversable")
	for cell in [Vector2i(12, 12), Vector2i(13, 14)]:
		check(not data.get_cell(Vector3i(cell.x, 0, cell.y)).walkable, "authored equipment occupancy blocks tactical cell %s" % cell)
	var holder := Node3D.new()
	root.add_child(holder)
	ModularEnvironmentPresenter.build(data, holder, 1.0)
	await process_frame
	var visuals := holder.find_children("*", "TacticalVisualOccluder", true, false)
	var socket_visuals := visuals.filter(func(node): return node.get_meta("socket_assembly_id", &"") == &"pipe_receiver_unit")
	check(socket_visuals.size() == 2, "parcel presents both real socket-connected equipment meshes")
	check(visuals.any(func(node): return String(node.get_meta("asset_path", "")).ends_with("tile-low.glb")), "parcel support surface comes from the imported paving asset")
	holder.queue_free()
	await process_frame

func _has_code(errors: PackedStringArray, code: String) -> bool:
	for error in errors:
		if error == code or error.begins_with(code + ":"): return true
	return false

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
