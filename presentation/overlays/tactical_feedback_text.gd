class_name TacticalFeedbackText
extends RefCounted

## Read-only descriptions of authoritative queries and committed results.
static func shot(query: AttackQueryResult) -> String:
	var heading := "%s → %s: " % [query.actor_id, query.target_id]
	if not query.is_legal():
		heading += query.reason
		if query.evaluation and query.evaluation.blocking_cell:
			heading += " at cell %s (highlighted)" % query.evaluation.blocking_cell.grid_position
		return heading
	var cover_names := ["none", "low", "full"]
	return heading + "%d%% hit · %d AP · %d SP\nDamage on hit: %d · cover: %s · %s" % [query.hit_chance, query.cost.ap, query.supply_points_cost, query.damage_on_hit, cover_names[query.evaluation.cover_type], query.obstruction]

static func movement(query: MoveQueryResult, actor: TacticalUnit, enemies: Array[TacticalUnit], grid: GridManager, use_supply := true, use_shield := true) -> String:
	var lines := PackedStringArray(["Move: %d AP · %d AP remaining · route cost %.1f" % [query.cost.ap, query.actor_ap_after, query.path_cost]])
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.stats or enemy.stats.is_defeated or not FactionRules.are_hostile(actor.faction, enemy.faction):
			continue
		var evaluation := CombatRules.evaluate_attack_at_cell(enemy, actor, query.target_cell, grid, actor.get_world_3d(), 0, use_shield)
		var cover := CombatRules.get_directional_cover(grid.get_unit_grid(enemy), query.target_cell, grid)
		var cover_name: String = ["none", "low", "full"][cover]
		var delta := grid.get_unit_grid(enemy) - query.target_cell
		var direction := ("N" if delta.z < 0 else "S") if delta.z != 0 else ""
		direction += ("W" if delta.x < 0 else "E") if delta.x != 0 else ""
		lines.append("%s from %s: cover %s · %s" % [enemy.tactical_id, direction, cover_name, "has a line of fire" if evaluation.is_legal else evaluation.reason])
		var outgoing := CombatRules.evaluate_attack_from_cell(actor, query.target_cell, enemy, grid, actor.get_world_3d(), 0, use_shield)
		var shot_description := "%d%% hit" % outgoing.hit_chance if outgoing.is_legal else outgoing.reason
		if query.actor_ap_after < TacticalActionService.ATTACK_AP_COST:
			shot_description = "No AP after moving (geometry: %s)" % shot_description
		elif use_supply and actor.stats.current_supply_points < TacticalActionService.ATTACK_SUPPLY_COST:
			shot_description = "No SP (geometry: %s)" % shot_description
		lines.append("  Your shot → %s: %s" % [enemy.tactical_id, shot_description])
	lines.append("After Move: Aim canceled. Enemy actions and Guard along the route can change this.")
	return "\n".join(lines)

static func committed(result) -> PackedStringArray:
	var lines := PackedStringArray()
	if result is AttackActionResult:
		lines.append(_shot_result(result.request.actor_id, result.request.target_id, result.did_hit, result.damage, result.target_defeated))
	elif result is OverwatchActionResult:
		lines.append("%s entered Guard — one reaction reserved" % result.request.actor_id)
	if result is AttackActionResult or result is MoveActionResult:
		for event: OverwatchReactionEvent in result.reaction_events:
			lines.append("Guard: " + _shot_result(event.watcher_id, result.request.actor_id, event.did_hit, event.damage, event.target_defeated))
	return lines

static func _shot_result(attacker: StringName, target: StringName, hit: bool, damage: int, defeated: bool) -> String:
	return "%s → %s: %s%s" % [attacker, target, "hit for %d" % damage if hit else "miss", " · defeated" if defeated else ""]
