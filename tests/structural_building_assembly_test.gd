extends SceneTree

var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var buildings := IndustrialBuildingCatalog.create()
	check(IndustrialBuildingCatalog.validation_errors().is_empty(), "Every procedural building assembly satisfies its structural contract")
	var service: EnvironmentBuildingDefinition = buildings.service_building
	check(service.enclosure == EnvironmentBuildingDefinition.Enclosure.CLOSED and service.is_complete(), "Service shop is explicitly a complete closed building")
	check(service.entrance_cells.size() == 4, "Service shop has one readable four-cell street entrance")
	check(service.wall_cells.size() + service.entrance_cells.size() == service.parcel_size.x * 2 + service.parcel_size.y * 2 - 4, "Closed-building perimeter is fully assigned to walls or entrances")
	check(service.usable_floor_cells.all(func(cell): return cell in service.roof_cells), "Every usable service-building floor cell is roof-covered")
	check(service.module.visuals.all(func(visual): return visual.get("kind", "") == "box"), "Service-building shell uses exact derived geometry instead of overlapping deep facade blocks")

	var canopy: EnvironmentBuildingDefinition = buildings.loading_canopy
	check(canopy.enclosure == EnvironmentBuildingDefinition.Enclosure.OPEN_SHELTER and canopy.is_complete(), "Loading canopy is deliberately open rather than an incomplete closed building")
	check(canopy.wall_cells.size() == 4 and not canopy.roof_cells.is_empty(), "Open canopy records four supports and authored roof coverage")

	var broken := EnvironmentBuildingDefinition.new(&"broken_fixture", &"test", EnvironmentBuildingDefinition.Enclosure.CLOSED, service.parcel_size)
	broken.module = service.module
	broken.wall_cells.assign(service.wall_cells)
	broken.entrance_cells.assign(service.entrance_cells)
	broken.entrance_directions = service.entrance_directions.duplicate()
	broken.usable_floor_cells.assign(service.usable_floor_cells)
	broken.roof_cells.assign(service.roof_cells)
	broken.roof_cells.erase(service.usable_floor_cells[0])
	check(not broken.validate().is_empty(), "A closed building with missing roof coverage is rejected")

	var generated := FlatMapGenerator.generate_modular_environment_sample(40, 30, 1.0, 2202, &"building_gallery")
	check(generated.environment_modules.size() == 5, "Building gallery assembles closed, open and prebuilt structural examples")
	var graph := Pathfinder.new()
	MapGraphBuilder.build(generated, graph)
	var validation := MapValidator.validate(generated, graph, {TacticalUnit.Faction.PLAYER: 5, TacticalUnit.Faction.ENEMY: 5})
	check(validation.is_valid(), "Building gallery remains a valid playable inspection map")
	var presentation := Node3D.new()
	root.add_child(presentation)
	ModularEnvironmentPresenter.build(generated, presentation, 1.0)
	var service_node := _find_module(presentation, &"complete_service_building")
	var canopy_node := _find_module(presentation, &"industrial_loading_canopy")
	check(service_node != null and service_node.get_meta("assembly_complete", false), "Presenter identifies the closed building as a validated assembly")
	check(canopy_node != null and canopy_node.get_meta("assembly_enclosure", &"") == &"open_shelter", "Presenter identifies intentional open structures")
	check(service_node != null and not service_node.find_children("*", "MeshInstance3D", true, false).is_empty(), "Derived building geometry is inspectable in the shared presenter")
	presentation.queue_free()
	await process_frame
	print("Structural building assembly: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _find_module(parent: Node, component_id: StringName) -> Node3D:
	var modular_root := parent.get_node_or_null("ModularEnvironment")
	if modular_root == null:
		return null
	for child in modular_root.get_children():
		if child.get_meta("component_id", &"") == component_id:
			return child as Node3D
	return null

func check(condition: bool, message: String) -> void:
	if condition:
		return
	failures += 1
	push_error(message)
