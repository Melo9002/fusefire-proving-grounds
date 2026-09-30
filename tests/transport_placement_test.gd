extends SceneTree
const PLANNER := preload("res://systems/objectives/extraction_transport_planner.gd")
var failures := 0

func _initialize() -> void:
	for seed_value in [1, 23001, 372339682]:
		var previous: Array = []
		for repeat in 2:
			var map := FlatMapGenerator.generate_with_cover(24, 20, 1.0, seed_value, 5, false)
			var pathfinder := Pathfinder.new()
			MapGraphBuilder.build(map, pathfinder)
			MissionZonePlanner.populate_defaults(map, pathfinder)
			PLANNER.place(map, pathfinder, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.EXTRACT, 1, false))
			var footprint: Array = map.transport_footprints.get(&"extract", [])
			check(footprint.size() == 8, "Truck footprint for seed %d" % seed_value)
			if repeat > 0: check(footprint == previous, "Deterministic truck placement")
			previous = footprint
			for zone: MapZoneData in map.zones.values():
				for cell in zone.cells: check(not footprint.has(cell), "No overlap with mission/deployment zones")
			for boarding in map.get_objective_zone(&"extract"):
				check(not pathfinder.calculate_3d_path(map.get_spawn_cells(TacticalUnit.Faction.PLAYER)[0], boarding).is_empty(), "Boarding remains reachable")
	print("Transport placement: %d failure(s)" % failures)
	quit(1 if failures else 0)

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)
