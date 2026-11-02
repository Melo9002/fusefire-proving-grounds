extends SceneTree
func _initialize():
	var failures := 0
	for turn in 4:
		var map := LoadingYardLayout.generate(17, 1.0, turn)
		var graph := Pathfinder.new()
		MapGraphBuilder.build(map, graph)
		MissionZonePlanner.populate_defaults(map, graph)
		var report := MapValidator.validate(map, graph, {TacticalUnit.Faction.PLAYER: 5, TacticalUnit.Faction.ENEMY: 5, TacticalUnit.Faction.ALLY: 5})
		if not report.is_valid():
			print("Turn %d: %s" % [turn, report.describe()])
			failures += 1
	print("Loading yard diagnostics: %d failures" % failures)
	quit(1 if failures else 0)
