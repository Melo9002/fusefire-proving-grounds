extends "res://docs/quality/evidence/contextual-04/replay_audit.gd"
## Post-transaction board probe. Enumerates one-move terrain/legal stops. It
## deliberately does not assume the board stays unchanged until a response.

func _capture(index: int, _total: int) -> void:
	var action := recording.actions[index - 1]
	if action.kind != "attack" or int(action.resolved.get("damage", 0)) == 0: return
	var battle := level.battle_controller
	var service := battle.action_service
	var attacker := service.actor_registry.resolve(StringName(action.actor))
	var target := service.actor_registry.resolve(StringName(action.target))
	if not is_instance_valid(attacker) or not is_instance_valid(target) or target.stats.is_defeated or attacker.stats.is_defeated:
		print("[Response] ", JSON.stringify({"index":index,"status":"unavailable_after_defeat","damage":action.resolved.damage}))
		return
	var grid := battle.grid_manager
	var from := target.grid_position
	var source := attacker.grid_position
	var policy := grid.map_data.engagement_policy
	var central := CombatRules.requires_central(policy)
	var current := CombatRules.evaluate_attack(target, attacker, grid, null)
	var raw := CombatRules._has_physical_lane(target, from, attacker, source, grid, central)
	if current.is_legal: return
	var reachable := battle.pathfinder.get_reachable_cells(from, target.stats.speed)
	var attack_stops := 0
	var out_of_fire := 0
	var both := 0
	var example := ""
	for cell in reachable:
		var outgoing := CombatRules.evaluate_attack_from_cell(target, cell, attacker, grid, null)
		var incoming := CombatRules.evaluate_attack_after_move(attacker, target, cell, grid, null)
		attack_stops += int(outgoing.is_legal)
		out_of_fire += int(not incoming.is_legal)
		both += int(outgoing.is_legal and not incoming.is_legal)
		if outgoing.is_legal and example.is_empty(): example = str(cell)
	print("[Response] ", JSON.stringify({"index":index,"revision":service.state_revision,
		"attacker":attacker.tactical_id,"target":target.tactical_id,"source":str(source),"target_cell":str(from),
		"damage":action.resolved.damage,"raw_return":raw,"reason":current.reason,
		"target_ap_now":target.stats.current_ap,"target_max_ap":target.stats.max_ap,"target_sp":target.stats.current_supply_points,
		"reachable":reachable.size(),"attack_stops":attack_stops,"stops_out_of_this_enemy_fire":out_of_fire,
		"attack_stops_without_return":both,"example_attack_stop":example}))
