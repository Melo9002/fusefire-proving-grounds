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
	var shot := query.evaluation
	var damage_note := " · Shield ×%.2f" % query.shield_damage_multiplier if query.shield_applied else " · " + shot.shield_reason if not shot.shield_reason.is_empty() else ""
	return heading + "%d%% hit · %d AP · %d SP\nDamage on hit: %d%s · cover: %s · %s\nBase %d · Protection -%d (cover %d / exposure %d; strongest only)\nRange penalty %.1f · Height %+.1f · Aim +%d · Shield %+d\nRaw %.2f → %d%% (limits %d–%d; rounded)" % [query.hit_chance, query.cost.ap, query.supply_points_cost, query.damage_on_hit, damage_note, cover_names[shot.cover_type], query.obstruction, shot.base_accuracy, shot.protection_penalty, shot.cover_penalty, shot.obstruction_penalty, shot.range_penalty, shot.height_modifier, query.aim_bonus, shot.shield_accuracy_modifier, shot.raw_chance, query.hit_chance, shot.minimum_hit_chance, shot.maximum_hit_chance]

static func movement(query: MoveQueryResult, actor: TacticalUnit, enemies: Array[TacticalUnit], grid: GridManager, use_supply := true, use_shield := true) -> String:
	var lines := PackedStringArray(["Move: %d AP · %d AP remaining · route cost %.1f" % [query.cost.ap, query.actor_ap_after, query.path_cost]])
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.stats or enemy.stats.is_defeated or not FactionRules.are_hostile(actor.faction, enemy.faction):
			continue
		var evaluation := CombatRules.evaluate_attack_after_move(enemy, actor, query.target_cell, grid, actor.get_world_3d())
		var cover := CombatRules.get_directional_cover(grid.get_unit_grid(enemy), query.target_cell, grid, enemy.standing_height, actor.standing_height)
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
	lines.append("After Move: Aim canceled. Shield canceled. Enemy actions and Guard along the route can change this.")
	return "\n".join(lines)

static func committed(result) -> PackedStringArray:
	var lines := PackedStringArray()
	if result is AttackActionResult:
		lines.append(_shot_result(result.request.actor_id, result.request.target_id, result.did_hit, result.damage, result.target_defeated))
	elif result is AimActionResult:
		lines.append("%s: Aim +%d — next Attack; canceled by Move, Reload or stance changes" % [result.request.actor_id, result.accuracy_bonus])
	elif result is ShieldActionResult:
		lines.append("%s: Shield toward %s — %.0f° front, %+d accuracy, ×%.2f damage" % [result.request.actor_id, result.request.target_id, result.protected_arc_degrees, result.accuracy_modifier, result.damage_multiplier])
	elif result is SimpleActionResult and result.shield_retained:
		lines.append("%s: skipped remaining AP; Shield stays active until next activation" % result.request.actor_id)
	elif result is OverwatchActionResult:
		lines.append("%s entered Guard — one reaction reserved" % result.request.actor_id)
	if result is AttackActionResult or result is MoveActionResult:
		lines.append_array(result.defense_notes)
		var watcher_ids: Array = result.guard_checks.keys()
		watcher_ids.sort()
		for watcher_id in watcher_ids:
			var skipped: Dictionary = result.guard_checks[watcher_id]
			lines.append("Guard: %s did not fire at %s — %s (last checked: %s, %s). %s" % [watcher_id, skipped.target, skipped.reason, skipped.trigger, skipped.checkpoint, "Reaction still reserved." if skipped.reserved else "No reaction remains."])
		for event: OverwatchReactionEvent in result.reaction_events:
			lines.append("Guard: " + _shot_result(event.watcher_id, result.request.actor_id, event.did_hit, event.damage, event.target_defeated) + " · %s · %d%% hit · 1 SP; reaction spent" % ["movement at %s" % event.checkpoint_cell if event.checkpoint_index > 0 else "retaliation after being attacked", event.hit_chance])
	return lines

static func _shot_result(attacker: StringName, target: StringName, hit: bool, damage: int, defeated: bool) -> String:
	return "%s → %s: %s%s" % [attacker, target, "hit for %d" % damage if hit else "miss", " · defeated" if defeated else ""]
