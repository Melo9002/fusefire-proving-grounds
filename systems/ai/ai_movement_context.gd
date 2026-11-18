class_name AIMovementContext
extends RefCounted
## What the extra movement-profile terms need to know about a unit's surroundings: its allies, and the
## target an ally already has a shot at (for flanking). Built once per movement decision from the same
## shared queries the rest of the AI uses; read-only, and it never draws a random number.

## Beyond this many cells an ally no longer adds to cohesion.
const COHESION_RANGE := 6.0
## A flanking position this far (degrees) from every ally's bearing to the target earns the full bonus.
const FULL_FLANK_ANGLE := 90.0
## Extra share of the flanking weight when the target has no cover against the flanking position.
const OPEN_TARGET_SHARE := 0.25

var allies: Array[TacticalUnit] = []
var focus_target: TacticalUnit
## Bearings (target to ally, on the ground plane) of the allies that can already shoot the focus target.
var focus_bearings: Array[Vector2] = []

## Ground-plane distance in cells from `cell` to the nearest ally, or INF with none.
func nearest_ally_distance(cell: Vector3i, grid: GridManager) -> float:
	var nearest := INF
	for ally in allies:
		if not is_instance_valid(ally) or not ally.stats or ally.stats.is_defeated:
			continue
		nearest = minf(nearest, CombatRules.attack_distance(cell, grid.get_unit_grid(ally), grid))
	return nearest

## Reward for being near allies: full at their side, none at COHESION_RANGE and beyond.
func cohesion_term(cell: Vector3i, weight: float, grid: GridManager) -> float:
	if weight <= 0.0:
		return 0.0
	var distance := nearest_ally_distance(cell, grid)
	if is_inf(distance):
		return 0.0
	return weight * clampf((COHESION_RANGE - distance) / COHESION_RANGE, 0.0, 1.0)

## Reward for a firing position that spreads fire onto the focus target from a new bearing. Zero unless the
## unit has a legal shot at the target from `cell` and at least one ally already has one from elsewhere.
func flank_term(unit: TacticalUnit, cell: Vector3i, weight: float, grid: GridManager) -> float:
	if weight <= 0.0 or not is_instance_valid(focus_target) or focus_bearings.is_empty():
		return 0.0
	var evaluation := CombatRules.evaluate_attack_from_cell(unit, cell, focus_target, grid, unit.get_world_3d())
	if not evaluation.is_legal:
		return 0.0
	var target_cell := grid.get_unit_grid(focus_target)
	var bearing := CombatRules.shield_direction(target_cell, cell, grid)
	if bearing.is_zero_approx():
		return 0.0
	var smallest := 180.0
	for ally_bearing in focus_bearings:
		smallest = minf(smallest, rad_to_deg(acos(clampf(bearing.dot(ally_bearing), -1.0, 1.0))))
	var share := clampf(smallest / FULL_FLANK_ANGLE, 0.0, 1.0)
	var cover := CombatRules.get_directional_cover(cell, target_cell, grid, unit.standing_height, focus_target.standing_height)
	if cover == MapCellData.CoverType.NONE:
		share += OPEN_TARGET_SHARE
	return weight * share

## Builds the context for `unit`: its friendly units and the nearest hostile an ally already has a legal
## shot at (the flanking focus), with the bearings those allies hold.
static func build(unit: TacticalUnit, friendlies: Array[TacticalUnit], hostiles: Array[TacticalUnit], grid: GridManager) -> AIMovementContext:
	var context := AIMovementContext.new()
	if not is_instance_valid(unit):
		return context
	for friendly in friendlies:
		if friendly != unit and is_instance_valid(friendly) and friendly.stats and not friendly.stats.is_defeated:
			context.allies.append(friendly)
	var unit_cell := grid.get_unit_grid(unit)
	var best_distance := INF
	for hostile in hostiles:
		if not is_instance_valid(hostile) or not hostile.stats or hostile.stats.is_defeated:
			continue
		var distance := CombatRules.attack_distance(unit_cell, grid.get_unit_grid(hostile), grid)
		if distance >= best_distance:
			continue
		var bearings: Array[Vector2] = []
		for ally in context.allies:
			if CombatRules.evaluate_attack(ally, hostile, grid, ally.get_world_3d()).is_legal:
				var bearing := CombatRules.shield_direction(grid.get_unit_grid(hostile), grid.get_unit_grid(ally), grid)
				if not bearing.is_zero_approx():
					bearings.append(bearing)
		if bearings.is_empty():
			continue
		best_distance = distance
		context.focus_target = hostile
		context.focus_bearings = bearings
	return context
