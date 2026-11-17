class_name TacticalFeedbackText
extends RefCounted

static func chance_label(chance: int, legal := true) -> String:
	if not legal: return "Unavailable"
	if chance >= 100: return "Guaranteed"
	if chance >= 70: return "Favorable, can miss"
	if chance >= 40: return "Risky"
	return "Poor"

static func chance_color(chance: int, legal := true) -> Color:
	if not legal: return Color(0.7, 0.73, 0.78)
	if chance >= 100: return Color(0.35, 1.0, 0.5)
	if chance >= 70: return Color(0.4, 0.78, 1.0)
	if chance >= 40: return Color(1.0, 0.67, 0.25)
	return Color(1.0, 0.35, 0.32)

## Read-only descriptions of authoritative queries and committed results.
static func shot(query: AttackQueryResult) -> String:
	var heading := "%s → %s: " % [query.actor_id, query.target_id]
	if not query.is_legal():
		heading += query.reason
		if query.evaluation and not query.evaluation.is_legal and query.evaluation.reason != query.reason:
			heading += " · " + query.evaluation.reason
		if query.evaluation and query.evaluation.blocking_cell:
			heading += " at cell %s (highlighted)" % query.evaluation.blocking_cell.grid_position
		return heading
	var cover_names := ["none", "low", "full"]
	var shot := query.evaluation
	var damage_note := " · Shield ×%.2f" % query.shield_damage_multiplier if query.shield_applied else " · " + shot.shield_reason if not shot.shield_reason.is_empty() else ""
	return heading + "%d%% hit · %s · %d AP · %d SP\nDamage on hit: %d%s · cover: %s · %s\nBase %d · Protection -%d (cover %d / exposure %d; strongest only)\nRange penalty %.1f · Height %+.1f · Aim +%d · Shield %+d\nRaw %.2f → %d%% (limits %d–%d; rounded)\nAfter Attack: %d AP · %d/%d SP" % [query.hit_chance, chance_label(query.hit_chance), query.cost.ap, query.supply_points_cost, query.damage_on_hit, damage_note, cover_names[shot.cover_type], query.obstruction, shot.base_accuracy, shot.protection_penalty, shot.cover_penalty, shot.obstruction_penalty, shot.range_penalty, shot.height_modifier, query.aim_bonus, shot.shield_accuracy_modifier, shot.raw_chance, query.hit_chance, shot.minimum_hit_chance, shot.maximum_hit_chance, query.actor_ap_after, query.supply_points_after, query.max_supply_points]

## Shared read-only destination facts for both text and firing-line presentation.
static func movement_options(query: MoveQueryResult, actor: TacticalUnit, enemies: Array[TacticalUnit], grid: GridManager, use_supply := true, use_shield := true, use_aim := true) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.stats or enemy.stats.is_defeated or not FactionRules.are_hostile(actor.faction, enemy.faction): continue
		var bonus: int = CombatRules.cover_tuning.aim_accuracy_bonus if use_aim and enemy.tactical_state and enemy.tactical_state.is_aiming else 0
		var incoming := CombatRules.evaluate_attack_after_move(enemy, actor, query.target_cell, grid, null, bonus)
		var outgoing := CombatRules.evaluate_attack_from_cell(actor, query.target_cell, enemy, grid, null, 0, use_shield)
		var unavailable := ""
		if query.actor_ap_after < TacticalActionService.ATTACK_AP_COST: unavailable = "No AP after moving"
		elif use_supply and actor.stats.current_supply_points < TacticalActionService.ATTACK_SUPPLY_COST: unavailable = "No SP"
		var incoming_unavailable := ""
		if enemy.tactical_state and enemy.tactical_state.is_shielding and enemy.shield_capability and not enemy.shield_capability.attacks_allowed: incoming_unavailable = "Shield prevents Attack"
		elif use_supply and enemy.stats.current_supply_points < TacticalActionService.ATTACK_SUPPLY_COST: incoming_unavailable = "No SP"
		var cover: int = incoming.cover_type if incoming.is_legal else CombatRules.get_directional_cover(grid.get_unit_grid(enemy), query.target_cell, grid, enemy.standing_height, actor.standing_height)
		options.append({"enemy": enemy, "incoming": incoming, "outgoing": outgoing, "unavailable": unavailable, "cover": cover, "damage": CombatRules.cover_tuning.damage_for_hit(outgoing.shield_damage_multiplier), "incoming_damage": CombatRules.cover_tuning.damage_for_hit(incoming.shield_damage_multiplier), "incoming_unavailable": incoming_unavailable})
	return options

static func movement(query: MoveQueryResult, actor: TacticalUnit, enemies: Array[TacticalUnit], grid: GridManager, use_supply := true, use_shield := true, use_aim := true) -> String:
	return movement_description(query, actor, movement_options(query, actor, enemies, grid, use_supply, use_shield, use_aim), grid, use_supply)

static func movement_description(query: MoveQueryResult, _actor: TacticalUnit, options: Array[Dictionary], grid: GridManager, use_supply := true) -> String:
	var lines := PackedStringArray(["Move: %d AP · %d AP remaining · route cost %.1f" % [query.cost.ap, query.actor_ap_after, query.path_cost]])
	lines.append("Then Attack: %d AP · %d SP. Enemy chances below are normal shots after arrival; Guard can react along the route." % [TacticalActionService.ATTACK_AP_COST, TacticalActionService.ATTACK_SUPPLY_COST if use_supply else 0])
	for option in options:
		var enemy: TacticalUnit = option.enemy
		var incoming: CombatRules.AttackEvaluation = option.incoming
		var outgoing: CombatRules.AttackEvaluation = option.outgoing
		var delta := CombatRules.get_support_position(grid.get_unit_grid(enemy), grid) - CombatRules.get_support_position(query.target_cell, grid)
		var direction := ("N" if delta.z < 0 else "S") if not is_zero_approx(delta.z) else ""
		direction += ("W" if delta.x < 0 else "E") if not is_zero_approx(delta.x) else ""
		var threat := "%d%% hit · %d damage on hit" % [incoming.hit_chance, option.incoming_damage] if incoming.is_legal else incoming.reason
		if not option.incoming_unavailable.is_empty(): threat = "%s now (geometry: %s)" % [option.incoming_unavailable, threat]
		lines.append("%s from %s: cover %s · %s" % [enemy.tactical_id, direction, ["none", "low", "full"][option.cover], threat])
		var shot_description := "%d%% hit · %s · %d damage on hit" % [outgoing.hit_chance, chance_label(outgoing.hit_chance), option.damage] if outgoing.is_legal else outgoing.reason
		if not option.unavailable.is_empty(): shot_description = "%s (geometry: %s)" % [option.unavailable, shot_description]
		lines.append("  Your shot → %s: %s" % [enemy.tactical_id, shot_description])
		if enemy.tactical_state and enemy.tactical_state.is_overwatching:
			lines.append("  Guard active: may react along the route before arrival; uses its separate reaction modifier.")
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
