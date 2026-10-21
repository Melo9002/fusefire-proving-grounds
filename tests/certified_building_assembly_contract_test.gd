extends SceneTree

const ASSET_ID := "city_kit_industrial/building-i"
const COMPONENT_ID := &"industrial_shell_i"
const ASSEMBLY_ID := &"city_industrial_shell_i"
const EXPECTED_FRONTAGES := [Vector3.BACK, Vector3.LEFT, Vector3.FORWARD, Vector3.RIGHT]

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var buildings := IndustrialBuildingCatalog.create()
	var building: EnvironmentBuildingDefinition = buildings[ASSEMBLY_ID]
	var contract: EnvironmentAssemblyContract = building.assembly_contract
	_test_positive_contract(building, contract)
	_test_negative_contracts(building, contract)
	await _test_resolved_geometry(building, contract)
	print("Certified building assembly contract: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_positive_contract(building: EnvironmentBuildingDefinition, contract: EnvironmentAssemblyContract) -> void:
	check(contract != null, "building-i exposes a reusable assembly contract")
	if contract == null:
		return
	var errors := contract.validate(building)
	check(errors.is_empty(), "building-i certification validates: %s" % "; ".join(errors))
	check(contract.is_certified(building), "building-i is explicitly certified, not merely semantically identified")
	var certified := IndustrialBuildingCatalog.certified_assemblies()
	check(certified.size() == 1 and certified.has(ASSEMBLY_ID), "Phase 3.1 exposes exactly one certified sealed shell")
	check(contract.role == EnvironmentAssemblyContract.AssemblyRole.SEALED_BUILDING_SHELL, "Contract distinguishes a sealed shell from open and modular structures")
	check(contract.completeness == EnvironmentAssemblyContract.Completeness.COMPLETE_EXTERIOR, "Contract claims complete exterior geometry")
	check(contract.supported_rotations == [0, 1, 2, 3], "All canonical quarter turns are explicitly supported")
	check(contract.components.size() == 1 and contract.components[0].required, "The monolithic shell is one required imported component")
	check(contract.components[0].asset_id == ASSET_ID, "The contract retains the stable imported asset ID")
	check(contract.components[0].local_position == Vector3(5.0, 0.0, 6.0) and contract.components[0].yaw_quarters == 2, "The source-to-module transform is explicit")
	check(contract.tactical_footprint == building.module.footprint_cells, "Tactical occupancy remains an explicit authored footprint")
	check(building.module.footprint_cells.all(func(cell): return not building.module.cell_effects[cell].walkable and building.module.cell_effects[cell].blocks_los), "Every sealed-shell tactical cell is explicitly blocking")
	var frontage: Dictionary = contract.relationships.street_frontage
	check(frontage.direction == Vector2i.DOWN and frontage.access_kind == "exterior_frontage_apron", "The named frontage relationship uses normalized module-local +Z")
	check(not frontage.interior_access, "The sealed exterior does not imply a playable interior")
	check(frontage.access_cells.size() == 18, "The frontage owns a six-by-three protected exterior apron")
	check(EnvironmentAssemblyContract.current_geometry_sha256(ASSET_ID) == contract.components[0].geometry_sha256, "The certified GLB dependency is current")
	check(EnvironmentAssemblyContract.current_calibration_signature(ASSET_ID) == contract.components[0].calibration_signature, "The resolved calibration dependency is current")

func _test_negative_contracts(building: EnvironmentBuildingDefinition, source: EnvironmentAssemblyContract) -> void:
	var broken := source.duplicate_contract()
	broken.components[0].asset_id = "city_kit_industrial/missing-building"
	check(_has_code(broken.validate(building), "MISSING_REQUIRED_ASSET"), "Missing required imported geometry is rejected")

	broken = source.duplicate_contract()
	broken.relationships.street_frontage.direction = Vector2i.UP
	check(_has_code(broken.validate(building), "FRONTAGE_MISMATCH"), "A frontage that disagrees with the resolved shell transform is rejected")

	broken = source.duplicate_contract()
	broken.required_clearance_cells.remove_at(0)
	check(_has_code(broken.validate(building), "INVALID_CLEARANCE"), "A truncated protected apron is rejected")

	broken = source.duplicate_contract()
	var semantics := SemanticAssetCatalog.load_data()
	semantics = semantics.duplicate(true)
	semantics.confirmed[ASSET_ID].completeness = "fragment"
	check(_has_code(broken.validate(building, semantics), "UNSUPPORTED_COMPLETENESS"), "A fragment cannot retain complete-exterior certification")

	broken = source.duplicate_contract()
	broken.components[0].geometry_sha256 = "stale-geometry"
	check(_has_code(broken.validate(building), "STALE_GEOMETRY_DEPENDENCY"), "Changed source geometry invalidates certification")

	broken = source.duplicate_contract()
	broken.components[0].calibration_signature = "stale-calibration"
	check(_has_code(broken.validate(building), "STALE_CALIBRATION_DEPENDENCY"), "Changed resolved calibration invalidates certification")

	broken = source.duplicate_contract()
	broken.supported_rotations.append(4)
	check(_has_code(broken.validate(building), "UNSUPPORTED_ROTATION"), "A non-canonical orientation is rejected")

func _test_resolved_geometry(building: EnvironmentBuildingDefinition, contract: EnvironmentAssemblyContract) -> void:
	var layout := EnvironmentModuleLayout.new(&"certified_building_geometry", 3101)
	for rotation in 4:
		var placement := EnvironmentModulePlacement.new(COMPONENT_ID, Vector2i(16, 16), rotation)
		var data := FlatMapGenerator.generate(48, 48, 1.0, 3101)
		data.environment_modules.append(placement)
		var holder := Node3D.new()
		root.add_child(holder)
		ModularEnvironmentPresenter.build(data, holder, 1.0)
		await process_frame
		var module := _find_module(holder, COMPONENT_ID)
		var visual := _first_visual(module)
		check(visual != null, "building-i resolves through the real presentation path at r%d" % rotation)
		if visual != null:
			var actual_frontage := (visual.basis.orthonormalized() * Vector3.FORWARD).normalized()
			check(actual_frontage.dot(EXPECTED_FRONTAGES[rotation]) > 0.999, "r%d physical frontage agrees with the independent expected direction: expected %s, got %s" % [rotation, EXPECTED_FRONTAGES[rotation], actual_frontage])
			var actual_bounds: AABB = visual.global_transform * visual.occlusion_bounds
			var approved := _grid_bounds_to_world(data, layout.world_visual_envelope(building.module, placement))
			check(_contains_with_tolerance(approved, actual_bounds, 0.021), "r%d actual imported geometry remains inside the approved envelope: approved %s, actual %s" % [rotation, approved, actual_bounds])
		holder.queue_free()
		await process_frame

func _find_module(holder: Node3D, component_id: StringName) -> Node3D:
	var modular := holder.get_node_or_null("ModularEnvironment")
	if modular == null:
		return null
	for child in modular.get_children():
		if child.get_meta("component_id", &"") == component_id:
			return child as Node3D
	return null

func _first_visual(module: Node3D) -> TacticalVisualOccluder:
	if module == null:
		return null
	var visuals := module.find_children("*", "TacticalVisualOccluder", true, false)
	return visuals[0] as TacticalVisualOccluder if not visuals.is_empty() else null

func _grid_bounds_to_world(data: MapData, bounds: AABB) -> AABB:
	var origin := data.get_cell(Vector3i.ZERO).world_position
	return AABB(bounds.position + Vector3(origin.x, 0.0, origin.z), bounds.size)

func _contains_with_tolerance(outer: AABB, inner: AABB, tolerance: float) -> bool:
	return inner.position.x >= outer.position.x - tolerance and inner.position.y >= outer.position.y - tolerance and inner.position.z >= outer.position.z - tolerance \
		and inner.end.x <= outer.end.x + tolerance and inner.end.y <= outer.end.y + tolerance and inner.end.z <= outer.end.z + tolerance

func _has_code(errors: PackedStringArray, code: String) -> bool:
	for error in errors:
		if error.begins_with(code + ":"):
			return true
	return false

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
