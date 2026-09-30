class_name AIPositionScorer
extends RefCounted

static func evaluate(
	unit: TacticalUnit,
	candidate: Vector3i,
	start: Vector3i,
	goal: Vector3i,
	route_progress: float,
	objective_route: bool,
	hostiles: Array[TacticalUnit],
	grid: GridManager,
	policy: AIDifficultyPolicy,
	squad: SquadContext
) -> Dictionary:
	var squad_adjustment := squad.destination_adjustment(unit, candidate) if squad else 0.0
	if squad_adjustment <= -1000.0:
		return {"total": -INF, "summary": "Reserved by ally"}
	var progress := float(route_progress) * (8.0 if objective_route else 4.0) * policy.movement_progress_weight
	if goal.x >= 0:
		progress += (start.distance_to(goal) - candidate.distance_to(goal)) * 1.5 * policy.movement_progress_weight
	var cover := 0.0
	var exposure := 0.0
	var firing := 0.0
	var danger := 0.0
	var incoming_lanes := 0
	var candidate_world := grid.grid_to_world(candidate)
	for hostile in hostiles:
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		var hostile_cell := grid.get_unit_grid(hostile)
		var distance := CombatRules.attack_distance(hostile_cell, candidate, grid)
		var directional_cover := CombatRules.get_directional_cover(hostile_cell, candidate, grid)
		if distance <= hostile.attack_range:
			match directional_cover:
				MapCellData.CoverType.LOW:
					cover += 4.0
				MapCellData.CoverType.FULL:
					cover += 7.0
			if CombatRules.has_line_of_sight_to_position(hostile, candidate_world, grid, unit.get_world_3d()):
				incoming_lanes += 1
				match directional_cover:
					MapCellData.CoverType.FULL:
						exposure -= 5.0
					MapCellData.CoverType.LOW:
						exposure -= 9.0
					_:
						exposure -= 14.0
		if not unit.is_carrying_unit() and distance <= unit.attack_range:
			var origin := candidate_world + Vector3.UP * unit.standing_height
			var target := CombatRules.get_shot_destination(hostile, grid)
			if CombatRules.get_blocking_cell(origin, target, grid) == null:
				var target_cover := CombatRules.get_directional_cover(candidate, hostile_cell, grid)
				firing += 6.0 if target_cover != MapCellData.CoverType.NONE else 10.0
		if distance <= 2:
			danger -= 8.0
	if incoming_lanes >= 2:
		danger -= float(incoming_lanes - 1) * 9.0
	cover *= policy.position_cover_weight
	exposure *= policy.position_exposure_weight
	firing *= policy.position_firing_weight
	danger *= policy.position_danger_weight
	# A carrier cannot return fire: preserving the passenger outweighs speed.
	if unit.is_carrying_unit():
		exposure *= 2.5
		danger *= 2.0
		cover *= 1.5
	var squad_score := squad_adjustment * policy.crowding_penalty_weight
	var total := progress + cover + exposure + firing + danger + squad_score
	return {
		"total": total,
		"progress": progress,
		"cover": cover,
		"exposure": exposure,
		"firing": firing,
		"danger": danger,
		"squad": squad_score,
		"summary": "progress %+.0f, cover %+.0f, exposure %+.0f, firing %+.0f, danger %+.0f, squad %+.0f" % [progress, cover, exposure, firing, danger, squad_score],
	}
