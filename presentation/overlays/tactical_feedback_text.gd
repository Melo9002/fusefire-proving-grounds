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
static func shot(query: AttackQueryResult, detailed := false, counterfire: CombatRules.AttackEvaluation = null) -> String:
	var heading := "%s → %s: " % [query.actor_id, query.target_id]
	var evaluation := query.evaluation
	var engagement := engagement_label(evaluation, counterfire)
	var relation := "" if engagement.is_empty() else "\n" + engagement
	if not query.is_legal():
		if not detailed and query.reason == "Blocked" and evaluation:
			var adjustment := "" if evaluation.contextual_rejection.is_empty() else "\nNo valid firing position"
			return heading + obstruction_text(evaluation) + adjustment + relation
		heading += query.reason
		if evaluation and not evaluation.is_legal:
			if evaluation.reason == "Blocked":
				if detailed and evaluation.blocking_cell:
					heading += " at cell %s (highlighted)" % evaluation.blocking_cell.grid_position
				else:
					heading += " · " + obstruction_text(evaluation)
			elif evaluation.reason != query.reason:
				heading += " · " + evaluation.reason
		return heading + relation
	var cover_names := ["none", "low", "full"]
	var damage_note := " · Shield ×%.2f" % query.shield_damage_multiplier if query.shield_applied else " · " + evaluation.shield_reason if not evaluation.shield_reason.is_empty() else ""
	if not detailed:
		var exposure := " · Target partially exposed" if evaluation.visibility_fraction < 1.0 else ""
		if evaluation.firing_solution and evaluation.firing_solution.body_offset != Vector3.ZERO:
			heading += "Side-step shot · "
		return heading + "%d%% hit · %d AP · %d SP\nDamage on hit: %d%s · Target cover: %s%s" % [
			query.hit_chance, query.cost.ap, query.supply_points_cost, query.damage_on_hit,
			damage_note, cover_names[evaluation.cover_type], exposure,
		] + relation
	return heading + "%d%% hit · %s · %d AP · %d SP\nDamage on hit: %d%s · cover: %s · %s\nBase %d · Protection -%d (cover %d / exposure %d; strongest only)\nRange penalty %.1f · Height %+.1f · Aim +%d · Shield %+d\nRaw %.2f → %d%% (limits %d–%d; rounded)\nAfter Attack: %d AP · %d/%d SP" % [query.hit_chance, chance_label(query.hit_chance), query.cost.ap, query.supply_points_cost, query.damage_on_hit, damage_note, cover_names[evaluation.cover_type], query.obstruction, evaluation.base_accuracy, evaluation.protection_penalty, evaluation.cover_penalty, evaluation.obstruction_penalty, evaluation.range_penalty, evaluation.height_modifier, query.aim_bonus, evaluation.shield_accuracy_modifier, evaluation.raw_chance, query.hit_chance, evaluation.minimum_hit_chance, evaluation.maximum_hit_chance, query.actor_ap_after, query.supply_points_after, query.max_supply_points]

static func obstruction_text(evaluation: CombatRules.AttackEvaluation) -> String:
	var blocker := evaluation.blocking_cell
	if blocker and not blocker.shot_obstacle_label.is_empty():
		return blocker.shot_obstacle_label + " blocks the firing lane"
	return "Firing lane obstructed"

## Compare directed geometry before AP, SP, activation and Guard trigger checks.
## A range failure has its own language because LOS was never evaluated.
static func engagement_label(outgoing: CombatRules.AttackEvaluation, incoming: CombatRules.AttackEvaluation) -> String:
	if not outgoing or not incoming: return ""
	if outgoing.is_legal:
		if incoming.is_legal: return "Both firing lanes clear"
		if incoming.reason == "Blocked": return "Your firing lane is clear · Their return lane is blocked"
		if incoming.reason == "Out of range": return "Your firing lane is clear · Their return shot is out of range"
	if incoming.is_legal:
		if outgoing.reason == "Blocked": return "Exposed · Your return lane is blocked"
		if outgoing.reason == "Out of range": return "Exposed · Your return shot is out of range"
	if outgoing.reason == "Blocked" and incoming.reason == "Blocked":
		return "Both firing lanes blocked"
	return ""

## Shared read-only destination facts for both text and firing-line presentation.
static func movement_options(query: MoveQueryResult, actor: TacticalUnit, enemies: Array[TacticalUnit], grid: GridManager, use_supply := true, use_shield := true, use_aim := true) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for enemy in enemies:
		if not is_instance_valid(enemy) or not enemy.is_visible_in_tree() or not enemy.stats or enemy.stats.is_defeated or not FactionRules.are_hostile(actor.faction, enemy.faction): continue
		var bonus: int = CombatRules.cover_tuning.aim_accuracy_bonus if use_aim and enemy.tactical_state and enemy.tactical_state.is_aiming else 0
		var incoming := CombatRules.evaluate_attack_after_move(enemy, actor, query.target_cell, grid, null, bonus)
		var outgoing := CombatRules.evaluate_attack_from_cell(actor, query.target_cell, enemy, grid, null, 0, use_shield)
		var unavailable := ""
		if query.actor_ap_after < TacticalActionService.ATTACK_AP_COST: unavailable = "No AP after moving"
		elif use_supply and actor.stats.current_supply_points < TacticalActionService.ATTACK_SUPPLY_COST: unavailable = "No SP"
		var incoming_unavailable := ""
		if use_shield and enemy.tactical_state and enemy.tactical_state.is_shielding and enemy.shield_capability and not enemy.shield_capability.attacks_allowed: incoming_unavailable = "Shield prevents Attack"
		elif use_supply and enemy.stats.current_supply_points < TacticalActionService.ATTACK_SUPPLY_COST: incoming_unavailable = "No SP"
		var cover: int = incoming.cover_type if incoming.is_legal else CombatRules.get_directional_cover(grid.get_unit_grid(enemy), query.target_cell, grid, enemy.standing_height, actor.standing_height)
		options.append({"enemy": enemy, "incoming": incoming, "outgoing": outgoing, "unavailable": unavailable, "cover": cover, "damage": CombatRules.damage_of(outgoing), "incoming_damage": CombatRules.damage_of(incoming), "incoming_unavailable": incoming_unavailable})
	return options

static func movement(query: MoveQueryResult, actor: TacticalUnit, enemies: Array[TacticalUnit], grid: GridManager, use_supply := true, use_shield := true, use_aim := true, detailed := false) -> String:
	return movement_description(query, actor, movement_options(query, actor, enemies, grid, use_supply, use_shield, use_aim), grid, use_supply, detailed)

static func movement_description(query: MoveQueryResult, actor: TacticalUnit, options: Array[Dictionary], grid: GridManager, use_supply := true, detailed := false) -> String:
	if not detailed:
		return _destination_summary(query, actor, options)
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

static func _destination_summary(query: MoveQueryResult, actor: TacticalUnit, options: Array[Dictionary]) -> String:
	var lines := PackedStringArray(["Move · %d AP · %d AP remaining" % [query.cost.ap, query.actor_ap_after]])
	var incoming_count := 0
	var outgoing_count := 0
	var exposed_count := 0
	var returnable_count := 0
	var entries: Array[Dictionary] = []
	var route_guard := false
	for option in options:
		var enemy: TacticalUnit = option.enemy
		var incoming: CombatRules.AttackEvaluation = option.incoming
		var outgoing: CombatRules.AttackEvaluation = option.outgoing
		var exposed := incoming.is_legal and outgoing.reason == "Blocked"
		if incoming.is_legal: incoming_count += 1
		if outgoing.is_legal:
			outgoing_count += 1
			if option.unavailable.is_empty(): returnable_count += 1
		if exposed: exposed_count += 1
		if enemy.tactical_state and enemy.tactical_state.is_overwatching: route_guard = true
		var relation := engagement_label(outgoing, incoming)
		if relation.is_empty(): relation = "Your shot: %s · Their shot: %s" % [outgoing.reason, incoming.reason]
		var text := "%s · %s · Your cover: %s" % [enemy.tactical_id, relation, ["none", "low", "full"][option.cover]]
		if incoming.is_legal and not option.incoming_unavailable.is_empty():
			text += " · Enemy now: " + option.incoming_unavailable
		if outgoing.firing_solution and outgoing.firing_solution.body_offset != Vector3.ZERO: text += " · Side-step shot available"
		if not option.unavailable.is_empty() and outgoing.is_legal: text += " · " + option.unavailable
		entries.append({"priority": 0 if exposed else (1 if incoming.is_legal else 2), "text": text})
	lines.append("On arrival · Firing lanes: %d out, %d in" % [outgoing_count, incoming_count])
	if returnable_count < outgoing_count:
		lines.append("Attack available against %d now (after Move)" % returnable_count)
	if exposed_count > 0: lines.append("Exposed to %d with no clear return lane" % exposed_count)
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.text < b.text if a.priority == b.priority else a.priority < b.priority)
	for row in entries.slice(0, 2): lines.append(row.text)
	if entries.size() > 2: lines.append("+%d more in F3" % (entries.size() - 2))
	if actor.tactical_state:
		var canceled := PackedStringArray()
		if actor.tactical_state.is_aiming: canceled.append("Aim canceled")
		if actor.tactical_state.is_shielding: canceled.append("Shield canceled")
		if not canceled.is_empty(): lines.append("After Move: " + " / ".join(canceled))
	if route_guard: lines.append("Guard active · Reactions along the route are separate")
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
			var reason: String = skipped.reason
			if reason == "Blocked":
				var obstacle: String = skipped.get("obstacle_label", "")
				reason = "Firing lane obstructed" if obstacle.is_empty() else obstacle + " blocks the firing lane"
			lines.append("Guard: %s did not fire at %s · %s. %s" % [watcher_id, skipped.target, reason, "Reaction still reserved." if skipped.reserved else "No reaction remains."])
		for event: OverwatchReactionEvent in result.reaction_events:
			lines.append("Guard: " + _shot_result(event.watcher_id, result.request.actor_id, event.did_hit, event.damage, event.target_defeated) + " · %s · %d%% hit · 1 SP; reaction spent" % ["movement at %s" % event.checkpoint_cell if event.checkpoint_index > 0 else "retaliation after being attacked", event.hit_chance])
	return lines

static func _shot_result(attacker: StringName, target: StringName, hit: bool, damage: int, defeated: bool) -> String:
	return "%s → %s: %s%s" % [attacker, target, "hit for %d" % damage if hit else "miss", " · defeated" if defeated else ""]
