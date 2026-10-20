extends SceneTree

const Profiles = preload("res://systems/generation/industrial_building_placement_profiles.gd")
const Semantics = preload("res://tools/asset_lab/semantic_asset_catalog.gd")

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var catalog := IndustrialModuleCatalog.create()
	_test_profiled_shell_contracts(catalog)
	_test_semantic_district_composition(catalog)
	print("Semantic district generation: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _test_profiled_shell_contracts(catalog: Dictionary) -> void:
	check(Profiles.ids().size() == 20, "Every reviewed City Industrial shell has an explicit placement profile")
	check(Profiles.fitting_module_ids(Vector2i(20, 20)).size() == 13, "The 20-cell frontage parcel admits only shells that fit at calibrated scale plus apron")
	check(Profiles.fitting_module_ids(Vector2i(20, 20), &"commercial_street").size() == 4, "Commercial frontage selection is restricted to explicitly confirmed compact shells")
	for asset_id in Profiles.ids():
		var module_id := Profiles.module_id_for_asset(asset_id)
		var definition: EnvironmentModuleDefinition = catalog.get(module_id)
		var semantic := Semantics.effective(asset_id)
		var profile := Profiles.profile_for_asset(asset_id)
		check(definition != null, "%s resolves to a reusable module" % asset_id)
		if definition == null:
			continue
		check(definition.assembly_complete and definition.assembly_enclosure == &"prebuilt_shell", "%s remains a complete sealed exterior" % asset_id)
		check(definition.size == Vector2i(ceili(profile.bounds.x), ceili(profile.bounds.z)), "%s rounds calibrated bounds outward into its tactical footprint" % asset_id)
		check(definition.visual_envelope.size == profile.bounds, "%s rejects intersections with its measured visual envelope" % asset_id)
		check(semantic.generation_ready and semantic.completeness == "complete", "%s is procedurally eligible only through its reviewed shell contract" % asset_id)
		check(semantic.working_faces.size() == 1, "%s retains one reviewed working face" % asset_id)
		check(definition.clearance_cells.size() == Profiles.FRONTAGE_DEPTH * mini(6, definition.size.x), "%s protects a three-cell facade apron" % asset_id)
		for cell in definition.footprint_cells:
			var effect: Dictionary = definition.cell_effects.get(cell, {})
			check(not effect.get("walkable", true) and effect.get("blocks_los", false), "%s authors sealed tactical occupancy independently from its mesh" % asset_id)

func _test_semantic_district_composition(catalog: Dictionary) -> void:
	var used_shells: Dictionary = {}
	for map_seed in [17, 2208, 7319, 11027]:
		var first := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, map_seed, &"industrial_district")
		var repeated := FlatMapGenerator.generate_coherent_environment(60, 50, 1.0, map_seed, &"industrial_district")
		check(_signature(first) == _signature(repeated), "Industrial showcase seed %d remains deterministic" % map_seed)
		var has_functional_large_parcel := false
		for parcel in first.environment_layout_plan.parcels:
			if String(parcel.template).begins_with("building_frontage/") or parcel.template == &"industrial_yard_block":
				has_functional_large_parcel = true
		check(has_functional_large_parcel, "Industrial showcase seed %d contains a building frontage or purposeful yard" % map_seed)
		for placement in first.environment_modules:
			if String(placement.component_id).begins_with("industrial_shell_"):
				used_shells[placement.component_id] = true
				var definition: EnvironmentModuleDefinition = catalog[placement.component_id]
				for clearance in definition.rotated_cells(definition.clearance_cells, placement.rotation):
					var world := placement.origin + clearance
					var cell := first.get_cell(Vector3i(world.x, 0, world.y))
					check(cell != null and cell.walkable and cell.can_stop, "%s keeps its frontage apron tactically usable" % placement.component_id)
	check(used_shells.size() >= 5, "Representative seeds use a broad set of reviewed industrial shells")

func _signature(data: MapData) -> String:
	var parts: Array[String] = []
	for placement in data.environment_modules:
		parts.append(placement.signature())
	return "|".join(parts)

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
