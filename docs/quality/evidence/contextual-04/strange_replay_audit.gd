extends "res://docs/quality/evidence/contextual-04/replay_audit.gd"
## Inspect a recorded wait and the preceding one-way lane without advancing the AI.
const INSPECT := [45, 46, 55, 56, 59, 63, 64, 70, 73]
const LAST_ENEMY := &"EnemyUnit2"
const BRAVO := &"PlayerUnit2"

func _capture(index: int, _total: int) -> void:
	var battle := level.battle_controller
	var service := battle.action_service
	var revision := service.state_revision
	if revision not in INSPECT: return
	var enemy := service.actor_registry.resolve(LAST_ENEMY)
	var bravo := service.actor_registry.resolve(BRAVO)
	var grid := battle.grid_manager
	if not is_instance_valid(enemy) or not is_instance_valid(bravo): return
	var state := {"index": index, "revision": revision, "contextual": grid.map_data.contextual_discovery_enabled,
		"lanes": [_lane(enemy, bravo, grid), _lane(bravo, enemy, grid)],
		"enemy_ap": enemy.stats.current_ap, "enemy_sp": enemy.stats.current_supply_points,
		"bravo_ap": bravo.stats.current_ap, "bravo_sp": bravo.stats.current_supply_points}
	if revision in [63, 70]:
		state["destinations"] = await _options(battle, enemy, bravo)
	print("[StrangeAudit] ", JSON.stringify(state))

func _options(battle: BattleController, enemy: TacticalUnit, bravo: TacticalUnit) -> Dictionary:
	var grid := battle.grid_manager
	var inventory := battle.query_move(enemy)
	var rng := battle.action_service.get_combat_rng_state()
	var revision := battle.action_service.state_revision
	var source := enemy.grid_position
	var ai := enemy.get_parent().get_node_or_null("%sAI" % enemy.name) as AIController
	var route := PackedVector3Array()
	if ai: route = await ai._path_to_target_neighbor(source, bravo.grid_position, bravo)
	var route_cells: Array[Vector3i] = []
	for point in route: route_cells.append(grid.world_to_grid(point))
	var row := {"legal_stops": inventory.legal_destination_cells.size(), "shots": [], "approach": str(route_cells),
		"current_exposure": ai._advance_exposure(source) if ai else -1.0}
	for cell in inventory.legal_destination_cells:
		if cell == source: continue
		var out := CombatRules.evaluate_attack_from_cell(enemy, cell, bravo, grid, null)
		if not out.is_legal: continue
		var move := battle.query_move(enemy, cell)
		if not move.is_legal(): continue
		var inc := CombatRules.evaluate_attack_after_move(bravo, enemy, cell, grid, null)
		row.shots.append({"cell": str(cell), "chance": out.hit_chance, "incoming": inc.hit_chance,
			"ap_left": move.actor_ap_after, "cost": move.path_cost,
			"in_route_corridor": ai._in_route_corridor(cell, route_cells) if ai else false,
			"exposure": ai._advance_exposure(cell) if ai else -1.0, "enemy_support": str(grid.grid_to_world(cell))})
	row.read_only = rng == battle.action_service.get_combat_rng_state() and revision == battle.action_service.state_revision and source == enemy.grid_position
	return row
