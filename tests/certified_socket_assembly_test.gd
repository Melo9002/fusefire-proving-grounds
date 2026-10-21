extends SceneTree

var failures := 0

func _initialize() -> void: _run.call_deferred()

func _run() -> void:
	var receiver := IndustrialEquipmentAssemblyCatalog.receiver_socket()
	var pipe := IndustrialEquipmentAssemblyCatalog.pipe_socket()
	var result := EnvironmentGeometricSocket.attachment_transform(receiver, pipe)
	check(result.ok, "verified receiver and pipe sockets are compatible")
	if result.ok:
		var expected := Transform3D(Basis(Vector3.UP, Vector3.LEFT, Vector3.BACK), Vector3(0.5, 1.793, 0.36))
		check(_transform_close(result.transform, expected), "measured frames independently resolve the expected +90Z pipe placement: %s" % result.transform)
		check(EnvironmentGeometricSocket.validate_alignment(receiver, Transform3D.IDENTITY, pipe, result.transform).is_empty(), "resolved seam position, opposed normals and tangent agree")
		var repeated := EnvironmentGeometricSocket.attachment_transform(receiver, pipe)
		check(_transform_close(result.transform, repeated.transform), "socket placement is deterministic")

	check(IndustrialEquipmentAssemblyCatalog.validate().is_empty(), "certified intentionally-open equipment unit validates")
	var placed := IndustrialEquipmentAssemblyCatalog.component_transforms()
	var separated: Dictionary = placed.duplicate(true)
	separated.vertical_pipe.origin += Vector3(0.1, 0, 0)
	check("SOCKET_ALIGNMENT_ERROR" in IndustrialEquipmentAssemblyCatalog.validate(separated), "positional separation beyond tolerance is rejected")
	var tilted: Dictionary = placed.duplicate(true)
	tilted.vertical_pipe.basis = Basis(receiver.local_frame.basis.x, 0.1) * tilted.vertical_pipe.basis
	tilted.vertical_pipe.origin += receiver.local_frame.origin - (tilted.vertical_pipe * pipe.local_frame).origin
	check("SOCKET_ANGULAR_ERROR" in IndustrialEquipmentAssemblyCatalog.validate(tilted), "angular mismatch is rejected")
	check("MISSING_TERMINATION" in IndustrialEquipmentAssemblyCatalog.validate({}, false), "unaccounted open pipe termination is rejected")
	check("INVALID_GEOMETRIC_OVERLAP" in IndustrialEquipmentAssemblyCatalog.validate({}, true, true), "invalid geometric overlap is rejected")
	var missing := placed.duplicate(true)
	missing.erase(&"vertical_pipe")
	check("MISSING_REQUIRED_COMPONENT" in IndustrialEquipmentAssemblyCatalog.validate(missing), "missing required assembly pieces are rejected")
	var wrong := IndustrialEquipmentAssemblyCatalog.pipe_socket()
	wrong.family = &"other_family"
	check(EnvironmentGeometricSocket.compatibility_failure(receiver, wrong) == &"INCOMPATIBLE_SOCKET_FAMILY", "incompatible socket families are rejected")
	check(EnvironmentGeometricSocket.compatibility_failure(receiver, pipe, 1) == &"UNSUPPORTED_ROTATION", "unsupported seam roll is rejected")
	var contract := IndustrialEquipmentAssemblyCatalog.contract()
	check(IndustrialEquipmentAssemblyCatalog.validate_contract(contract).is_empty(), "assembly certification pins both geometry and calibration dependencies")
	var stale := contract.duplicate_contract()
	stale.components[0].geometry_sha256 = "stale"
	check("STALE_GEOMETRY_DEPENDENCY" in IndustrialEquipmentAssemblyCatalog.validate_contract(stale), "changed source geometry invalidates certification")
	stale = contract.duplicate_contract()
	stale.components[1].calibration_signature = "stale"
	check("STALE_CALIBRATION_DEPENDENCY" in IndustrialEquipmentAssemblyCatalog.validate_contract(stale), "changed calibration invalidates certification")

	var module := IndustrialEquipmentAssemblyCatalog.module()
	check(module.structural_assembly_id == &"pipe_receiver_unit" and module.assembly_enclosure == &"intentionally_open_equipment", "assembly is reusable and honestly classified")
	check(module.footprint_cells.all(func(cell): return not module.cell_effects[cell].walkable), "tactical occupancy is explicitly authored independently of meshes")
	await _test_presentation(module)
	print("Certified socket assembly: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_presentation(module: EnvironmentModuleDefinition) -> void:
	for rotation in 4:
		var data := FlatMapGenerator.generate(16, 16, 1.0, 3202)
		data.environment_modules.append(EnvironmentModulePlacement.new(module.component_id, Vector2i(6, 6), rotation))
		var holder := Node3D.new()
		root.add_child(holder)
		ModularEnvironmentPresenter.build(data, holder, 1.0)
		await process_frame
		var visuals := holder.find_children("*", "TacticalVisualOccluder", true, false)
		var assembly_visuals := visuals.filter(func(node): return node.get_meta("socket_assembly_id", &"") == &"pipe_receiver_unit")
		check(assembly_visuals.size() == 2, "r%d presents both imported assembly pieces through the production path" % rotation)
		holder.queue_free()
		await process_frame

func _transform_close(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.is_equal_approx(b.origin) and a.basis.is_equal_approx(b.basis)

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: %s" % message)
	else:
		failures += 1
		push_error("FAIL: %s" % message)
