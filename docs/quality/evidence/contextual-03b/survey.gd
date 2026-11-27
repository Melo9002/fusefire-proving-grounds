extends SceneTree
## Sample fixed planar vectors across authored maps. This tool does not submit actions.
const Battle := preload("res://levels/prototype_map/prototype_map.tscn")
const VECTORS := [
	Vector3i(4, 0, 0), Vector3i(7, 0, 0), Vector3i(-4, 0, 0), Vector3i(-7, 0, 0),
	Vector3i(0, 0, 4), Vector3i(0, 0, 7), Vector3i(0, 0, -4), Vector3i(0, 0, -7),
	Vector3i(4, 0, 3), Vector3i(3, 0, -5), Vector3i(-5, 0, 3), Vector3i(-3, 0, -4),
]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for site in [BattlefieldCatalog.CONTEXTUAL_DEPOT, BattlefieldCatalog.CONTEXTUAL_FREIGHT, BattlefieldCatalog.FLEET_STATION]:
		var config := BattleConfiguration.new()
		config.generated_map = true
		config.battle_seed = 16
		config.select_battlefield(site)
		config.player_count = 1
		config.enemy_count = 1
		config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1)
		var level := Battle.instantiate() as BattleLevel
		level.configure_battle(config)
		root.add_child(level)
		for frame in 6: await process_frame
		if not level.battle_initialization_succeeded:
			push_error("Unable to initialize survey site " + site)
			quit(1)
			return
		var grid := level.battle_controller.grid_manager
		# Fleet Station stays disabled for ordinary play. The survey can inspect it.
		grid.map_data.contextual_discovery_enabled = true
		_survey(site, grid, level.turn_manager.player_units[0], level.turn_manager.enemy_units[0])
		level.queue_free()
		await process_frame
	quit(0)

func _survey(site: StringName, grid: GridManager, actor: TacticalUnit, enemy: TacticalUnit) -> void:
	var counts := {}
	var witnesses := 0
	var sources := {}
	var started := Time.get_ticks_usec()
	var attempted := 0
	for cell: MapCellData in grid.map_data.cells.values():
		if not cell.can_stop: continue
		var source := cell.grid_position
		for delta in VECTORS:
			var destination: Vector3i = source + delta
			var target := grid.map_data.get_cell(destination)
			if not target or not target.can_stop: continue
			var direct: Dictionary = CombatRules._evaluate_target_visibility_cells(actor, source, enemy, destination, grid)
			var details := {}
			var contextual := CombatRules._contextual_step(actor, source, enemy, destination, grid, details)
			attempted += int(details.get("attempted", 0))
			var category := "direct_only" if direct.visible_count else str(details.get("reason", "no_solution"))
			if contextual:
				category = "both" if direct.visible_count else "contextual_only"
				if not direct.visible_count:
					sources[source] = true
					if witnesses < 14:
						var incoming := CombatRules._evaluate_target_visibility_cells(enemy, destination, actor, source, grid)
						print("[ContextualWitness] ", site, " from=", source, " target=", destination, " offset=", contextual.body_offset, " incoming_samples=", incoming.visible_count)
						witnesses += 1
			counts[category] = int(counts.get(category, 0)) + 1
	print("[ContextualSurvey] ", site, " totals=", JSON.stringify(counts), " unique_contextual_stops=", sources.size(),
		" candidate_attempts=", attempted, " duration_ms=", (Time.get_ticks_usec() - started) / 1000.0)
