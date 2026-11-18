class_name AIPositionScorer
extends RefCounted

static func evaluate(
	unit: TacticalUnit,
	candidate: Vector3i,
	start: Vector3i,
	goal: Vector3i,
	route_progress: float,
	layers: Array,
	hostiles: Array[TacticalUnit],
	grid: GridManager,
	policy: AIDifficultyPolicy,
	squad: SquadContext,
	movement: AIMovementContext = null
) -> Dictionary:
	# A commitment an ally holds is a hard veto with a named owner; only crowding is a soft score.
	var blocked := squad.block_reason(unit, candidate) if squad else ""
	if not blocked.is_empty():
		return {"total": -INF, "summary": blocked}
	var squad_adjustment := squad.crowding_adjustment(unit, candidate) if squad else 0.0
	# Situational profile layers (AIMovementProfile) multiply the terms in order, after difficulty and
	# commander have set the weights. No layer: unchanged.
	var route_multiplier := 4.0
	var goal_multiplier := 1.5
	for layer: AIMovementProfile in layers:
		route_multiplier *= layer.route_progress
		goal_multiplier *= layer.goal_progress
	var progress := float(route_progress) * route_multiplier * policy.movement_progress_weight
	if goal.x >= 0:
		progress += (start.distance_to(goal) - candidate.distance_to(goal)) * goal_multiplier * policy.movement_progress_weight
	var cover := 0.0
	var exposure := 0.0
	var firing := 0.0
	var danger := 0.0
	var incoming_lanes := 0
	for hostile in hostiles:
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		var hostile_cell := grid.get_unit_grid(hostile)
		var distance := CombatRules.attack_distance(hostile_cell, candidate, grid)
		var directional_cover := CombatRules.get_directional_cover(hostile_cell, candidate, grid, hostile.standing_height, unit.standing_height)
		if distance <= hostile.attack_range:
			match directional_cover:
				MapCellData.CoverType.LOW:
					cover += 4.0
				MapCellData.CoverType.FULL:
					cover += 7.0
			if CombatRules.evaluate_attack_after_move(hostile, unit, candidate, grid, unit.get_world_3d()).is_legal:
				incoming_lanes += 1
				match directional_cover:
					MapCellData.CoverType.FULL:
						exposure -= 5.0
					MapCellData.CoverType.LOW:
						exposure -= 9.0
					_:
						exposure -= 14.0
		if not unit.is_carrying_unit() and distance <= unit.attack_range:
			if CombatRules.evaluate_attack_from_cell(unit, candidate, hostile, grid, unit.get_world_3d()).is_legal:
				var target_cover := CombatRules.get_directional_cover(candidate, hostile_cell, grid, unit.standing_height, hostile.standing_height)
				firing += 6.0 if target_cover != MapCellData.CoverType.NONE else 10.0
		if distance <= 2:
			danger -= 8.0
	if incoming_lanes >= 2:
		danger -= float(incoming_lanes - 1) * 9.0
	cover *= policy.position_cover_weight
	exposure *= policy.position_exposure_weight
	firing *= policy.position_firing_weight
	danger *= policy.position_danger_weight
	var crowding_multiplier := 1.0
	for layer: AIMovementProfile in layers:
		cover *= layer.cover
		exposure *= layer.exposure
		firing *= layer.firing
		danger *= layer.danger
		crowding_multiplier *= layer.crowding
	var squad_score := squad_adjustment * policy.crowding_penalty_weight * crowding_multiplier
	# Terms that need to know the unit's surroundings (flanking, staying with allies); zero unless a layer
	# asks for them and the context is available.
	var flank := 0.0
	var cohesion := 0.0
	if movement != null:
		var flank_weight := 0.0
		var cohesion_weight := 0.0
		for layer: AIMovementProfile in layers:
			flank_weight += layer.flank_weight
			cohesion_weight += layer.ally_cohesion_weight
		flank = movement.flank_term(unit, candidate, flank_weight, grid)
		cohesion = movement.cohesion_term(candidate, cohesion_weight, grid)
	var total := progress + cover + exposure + firing + danger + squad_score + flank + cohesion
	var summary := "progress %+.0f, cover %+.0f, exposure %+.0f, firing %+.0f, danger %+.0f, squad %+.0f" % [progress, cover, exposure, firing, danger, squad_score]
	if flank != 0.0 or cohesion != 0.0:
		summary += ", flank %+.0f, cohesion %+.0f" % [flank, cohesion]
	return {
		"total": total,
		"flank": flank,
		"cohesion": cohesion,
		"progress": progress,
		"cover": cover,
		"exposure": exposure,
		"firing": firing,
		"danger": danger,
		"squad": squad_score,
		"summary": summary,
	}
