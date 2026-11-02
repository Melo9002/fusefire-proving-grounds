extends SceneTree
func _initialize():
	var failures := 0
	if not LoadingYardLayout.validate().is_empty(): failures += 1
	for turn in 4:
		var map := LoadingYardLayout.generate(17, 1.0, turn)
		var graph := Pathfinder.new()
		MapGraphBuilder.build(map, graph)
		MissionZonePlanner.populate_defaults(map, graph)
		var report := MapValidator.validate(map, graph, {TacticalUnit.Faction.PLAYER: 5, TacticalUnit.Faction.ENEMY: 5, TacticalUnit.Faction.ALLY: 5})
		if not report.is_valid():
			print("Turn %d: %s" % [turn, report.describe()])
			failures += 1
		var parcel := LoadingYardLayout.PARCEL.instantiate()
		var connection := ParcelConnection.from_scene(parcel)
		var rotated_size := ParcelTransform.rotated_size(LoadingYardLayout.PARCEL_SIZE, turn)
		var origin := Vector3i((LoadingYardLayout.SIZE.x - rotated_size.x) / 2, 0, (LoadingYardLayout.SIZE.y - rotated_size.y) / 2)
		var world := connection.world_cell(LoadingYardLayout.PARCEL_SIZE, origin, turn)
		var outward := connection.world_outward(turn)
		var beyond := world + Vector3i(outward.x, 0, outward.y)
		if beyond.x < 0 or beyond.z < 0 or beyond.x >= LoadingYardLayout.SIZE.x or beyond.z >= LoadingYardLayout.SIZE.y: failures += 1
		parcel.free()
	print("Loading yard diagnostics: %d failures" % failures)
	quit(1 if failures else 0)
