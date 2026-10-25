extends SceneTree

const Cargo = preload("res://systems/generation/industrial_cargo_assembly_catalog.gd")
const LayoutStore = preload("res://tools/map_editor_layout_store.gd")

var failures := 0
var catalog := IndustrialModuleCatalog.create()

func _init() -> void:
	_test_certified_family()
	_test_negative_contracts()
	_test_generation_and_document_lifecycle()
	print("Certified cargo asset family: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_certified_family() -> void:
	var contract := Cargo.contract()
	var module := Cargo.module()
	check(contract.certification_state == EnvironmentAssemblyContract.CertificationState.CERTIFIED, "shipping-container variants have an explicit certification state")
	check(Cargo.validate_contract(contract).is_empty(), "all three real imported variants satisfy geometry, calibration, semantic, envelope, and tactical contracts")
	check(contract.role == EnvironmentAssemblyContract.AssemblyRole.TACTICAL_OBSTACLE_FAMILY and contract.completeness == EnvironmentAssemblyContract.Completeness.COMPLETE_OBJECT, "containers are complete standalone obstacles rather than structural fragments")
	check(contract.supported_rotations == [0, 1, 2, 3], "the rectangular obstacle supports every canonical quarter turn")
	check(module.structural_assembly_id == Cargo.ASSEMBLY_ID and module.visuals[0].asset_ids == Cargo.ASSET_IDS, "presentation resolves variants through the certified semantic catalog family")
	check(module.footprint_cells.all(func(cell): return not module.cell_effects[cell].walkable and module.cell_effects[cell].blocks_los and module.cell_effects[cell].cover_type == MapCellData.CoverType.FULL), "tactical occupancy remains explicitly authored independently of imported meshes")
	for rotation in 4:
		var layout := EnvironmentModuleLayout.new(&"cargo_rotation", rotation)
		check(layout.try_add(module, EnvironmentModulePlacement.new(&"cargo_container", Vector2i(6, 6), rotation), Vector2i(20, 20)), "rotation %d fits through canonical module placement" % rotation)
		var envelope := layout.world_visual_envelope(module, layout.placements[0])
		check(envelope.size.x > 0.0 and envelope.size.z > 0.0, "rotation %d retains a measurable approved visual envelope" % rotation)

func _test_negative_contracts() -> void:
	var stale_geometry := Cargo.contract()
	stale_geometry.components[0].geometry_sha256 = "stale"
	check(_has_prefix(Cargo.validate_contract(stale_geometry), "STALE_GEOMETRY_DEPENDENCY"), "geometry drift invalidates family certification")
	var stale_calibration := Cargo.contract()
	stale_calibration.components[1].calibration_signature = "stale"
	check(_has_prefix(Cargo.validate_contract(stale_calibration), "STALE_CALIBRATION_DEPENDENCY"), "calibration drift invalidates family certification")
	var missing := Cargo.contract()
	missing.components.pop_back()
	check("MISSING_REQUIRED_COMPONENT" in Cargo.validate_contract(missing), "a missing certified variant cannot masquerade as the complete family")
	var wrong_role := Cargo.contract()
	wrong_role.completeness = EnvironmentAssemblyContract.Completeness.COMPLETE_EXTERIOR
	check("UNSUPPORTED_COMPLETENESS" in Cargo.validate_contract(wrong_role), "a standalone container family cannot be mislabeled as a building exterior")

func _test_generation_and_document_lifecycle() -> void:
	var first := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, 17, &"industrial_district")
	var repeated := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, 17, &"industrial_district")
	check(first.environment_modules.any(func(value): return value.component_id == &"cargo_container"), "the certified family is used by an existing compatible industrial parcel")
	check(_placement_signature(first) == _placement_signature(repeated), "certified variant integration preserves deterministic placement")
	var document := BattlefieldLayoutDocument.from_generated(first, "certified_cargo_seed_17")
	var cargo_records: Array = document.spatial_layout.placements.filter(func(value): return value.component_id == "cargo_container")
	check(not cargo_records.is_empty() and cargo_records.all(func(value): return value.assembly_ref == String(Cargo.ASSEMBLY_ID) and value.asset_refs.size() == 1 and value.asset_refs[0] in Cargo.ASSET_IDS), "documents pin the chosen imported variant and family certification")
	check(document.dependencies.any(func(value): return value.kind == "assembly" and value.id == String(Cargo.ASSEMBLY_ID)), "layout dependencies include the cargo-family certification signature")
	var decoded := LayoutStore.decode(LayoutStore.encode(document), catalog)
	check(decoded.ok and decoded.document.to_module_layout(catalog).signature() == document.to_module_layout(catalog).signature(), "cargo family survives save/load and deterministic reconstruction")
	var stale := BattlefieldLayoutDocument.from_dictionary(document.to_dictionary())
	for dependency in stale.dependencies:
		if dependency.get("kind", "") == "assembly" and dependency.get("id", "") == String(Cargo.ASSEMBLY_ID): dependency.certification_signature = "stale"
	check(not LayoutStore.decode(LayoutStore.encode(stale), catalog).ok, "stale cargo-family certification rejects document loading")

func _placement_signature(data: MapData) -> String:
	var values: Array[String] = []
	for placement: EnvironmentModulePlacement in data.environment_modules: values.append(placement.signature())
	return "|".join(values)

func _has_prefix(values: PackedStringArray, prefix: String) -> bool:
	return Array(values).any(func(value): return String(value).begins_with(prefix))

func check(condition: bool, message: String) -> void:
	if condition: print("PASS: ", message)
	else:
		failures += 1
		push_error("FAIL: " + message)
