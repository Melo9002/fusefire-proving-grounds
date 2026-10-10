class_name CombatRules
extends RefCounted

class AttackEvaluation:
	var is_legal: bool
	var hit_chance: int
	var cover_type: MapCellData.CoverType
	var reason: String
	var aim_point: Vector3
	var visibility_fraction: float
	var obstruction: String
	var blocking_cell: MapCellData
	var shield_applied := false
	var shield_accuracy_modifier := 0
	var shield_damage_multiplier := 1.0

	func _init(
		legal: bool,
		chance: int = 0,
		cover: MapCellData.CoverType = MapCellData.CoverType.NONE,
		message: String = "",
		point := Vector3.ZERO,
		visible_fraction := 0.0,
		obstruction_label := "Blocked",
		blocker: MapCellData = null,
		p_shield_applied := false,
		p_shield_accuracy_modifier := 0,
		p_shield_damage_multiplier := 1.0
	) -> void:
		is_legal = legal
		hit_chance = chance
		cover_type = cover
		reason = message
		aim_point = point
		visibility_fraction = visible_fraction
		obstruction = obstruction_label
		blocking_cell = blocker
		shield_applied = p_shield_applied
		shield_accuracy_modifier = p_shield_accuracy_modifier
		shield_damage_multiplier = p_shield_damage_multiplier

static func evaluate_attack(attacker: TacticalUnit, target: TacticalUnit, grid: GridManager, _world: World3D, accuracy_bonus := 0, allow_shield := true) -> AttackEvaluation:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Invalid target")
	var default_aim := get_shot_destination(target, grid)
	if attacker.is_carrying_unit():
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Cannot shoot while carrying", default_aim)
	if not attacker.stats or not target.stats or attacker.stats.is_defeated or target.stats.is_defeated:
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Unit defeated", default_aim)
	if not FactionRules.are_hostile(attacker.faction, target.faction):
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Not hostile", default_aim)

	var attacker_grid = grid.get_unit_grid(attacker)
	var target_grid = grid.get_unit_grid(target)
	var grid_distance = attack_distance(attacker_grid, target_grid, grid)
	if grid_distance > attacker.attack_range:
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Out of range", default_aim)
	var visibility := _evaluate_target_visibility(attacker, target, grid)
	if visibility.visible_count == 0:
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.FULL, "Blocked", visibility.aim_point, 0.0, "Blocked", visibility.blocker)

	var cover := get_directional_cover(attacker_grid, target_grid, grid)
	var cover_penalty := 50 if cover != MapCellData.CoverType.NONE else 0
	var obstruction_penalties := [50, 50, 40, 25, 10, 0]
	var obstruction_penalty: int = obstruction_penalties[visibility.visible_count]
	var shield := get_shield_protection(attacker, target, grid) if allow_shield else {}
	var shield_accuracy := int(shield.get("accuracy_modifier", 0))
	var chance := clampi(100 - maxi(cover_penalty, obstruction_penalty) + accuracy_bonus + shield_accuracy, 5, 100)
	var fraction: float = float(visibility.visible_count) / float(visibility.sample_count)
	return AttackEvaluation.new(true, chance, cover, "", visibility.aim_point, fraction, _obstruction_label(visibility.visible_count, visibility.sample_count), visibility.blocker, bool(shield.get("applied", false)), shield_accuracy, float(shield.get("damage_multiplier", 1.0)))

static func get_shield_protection(attacker: TacticalUnit, target: TacticalUnit, grid: GridManager) -> Dictionary:
	if not is_instance_valid(attacker) or not is_instance_valid(target) or not target.tactical_state \
		or not target.tactical_state.is_shielding or not target.shield_capability:
		return {"applied": false, "accuracy_modifier": 0, "damage_multiplier": 1.0}
	var attacker_cell := grid.get_unit_grid(attacker)
	var target_cell := grid.get_unit_grid(target)
	var incoming := Vector2(float(attacker_cell.x - target_cell.x), float(attacker_cell.z - target_cell.z))
	var applied := is_within_protected_arc(target.tactical_state.shield_facing, incoming, target.shield_capability.protected_arc_degrees)
	return {
		"applied": applied,
		"accuracy_modifier": target.shield_capability.accuracy_modifier if applied else 0,
		"damage_multiplier": target.shield_capability.damage_multiplier if applied else 1.0,
	}

## The boundary is inclusive. An attacker exactly half the arc away from the
## committed facing receives protection; epsilon absorbs floating-point noise.
static func is_within_protected_arc(facing: Vector2, incoming: Vector2, arc_degrees: float) -> bool:
	if facing.is_zero_approx() or incoming.is_zero_approx():
		return false
	if arc_degrees >= 360.0:
		return true
	var threshold := cos(deg_to_rad(clampf(arc_degrees, 0.0, 360.0) * 0.5))
	return facing.normalized().dot(incoming.normalized()) + 0.00001 >= threshold

static func can_attack(attacker: TacticalUnit, target: TacticalUnit, grid: GridManager, world: World3D) -> bool:
	return evaluate_attack(attacker, target, grid, world).is_legal

static func attack_distance(from_cell: Vector3i, to_cell: Vector3i, grid: GridManager) -> float:
	return grid.grid_to_world(from_cell).distance_to(grid.grid_to_world(to_cell)) / grid.cell_size

static func can_reach_adjacent(from_cell: Vector3i, to_cell: Vector3i, grid: GridManager) -> bool:
	var delta := to_cell - from_cell
	if delta.y != 0 or delta == Vector3i.ZERO or absi(delta.x) > 1 or absi(delta.z) > 1:
		return false
	if delta.x != 0 and delta.z != 0:
		for side in [from_cell + Vector3i(delta.x, 0, 0), from_cell + Vector3i(0, 0, delta.z)]:
			var data := grid.get_cell_data(side)
			if not data or not data.walkable or not data.can_stop:
				return false
	return true

static func has_line_of_sight_to_position(attacker: TacticalUnit, destination: Vector3, grid: GridManager, _world: World3D) -> bool:
	var target_cell = grid.world_to_grid(destination)
	var origin = grid.grid_to_world(grid.get_unit_grid(attacker)) + Vector3.UP * attacker.standing_height
	var target = grid.grid_to_world(target_cell) + Vector3.UP * attacker.standing_height
	return get_blocking_cell(origin, target, grid) == null

static func get_blocking_cell_between_units(attacker: TacticalUnit, target: TacticalUnit, grid: GridManager) -> MapCellData:
	return get_blocking_cell(get_shot_origin(attacker, grid), get_shot_destination(target, grid), grid)

static func get_shot_origin(attacker: TacticalUnit, grid: GridManager) -> Vector3:
	return grid.grid_to_world(grid.get_unit_grid(attacker)) + Vector3.UP * attacker.standing_height

static func get_shot_destination(target: TacticalUnit, grid: GridManager) -> Vector3:
	return grid.grid_to_world(grid.get_unit_grid(target)) + Vector3.UP * target.standing_height

static func _evaluate_target_visibility(attacker: TacticalUnit, target: TacticalUnit, grid: GridManager) -> Dictionary:
	var origin := get_shot_origin(attacker, grid)
	var center := get_shot_destination(target, grid)
	var horizontal := center - origin
	horizontal.y = 0.0
	var side := Vector3.RIGHT
	if not horizontal.is_zero_approx():
		side = Vector3(-horizontal.z, 0.0, horizontal.x).normalized()
	var base := grid.grid_to_world(grid.get_unit_grid(target))
	var samples: Array[Vector3] = [
		base + Vector3.UP * target.standing_height * 1.2,
		base + Vector3.UP * target.standing_height * 1.75,
		base + Vector3.UP * target.standing_height * 0.9 + side * grid.cell_size * 0.28,
		base + Vector3.UP * target.standing_height * 0.9 - side * grid.cell_size * 0.28,
		base + Vector3.UP * target.standing_height * 0.5,
	]
	var visible: Array[Vector3] = []
	var first_blocker: MapCellData = null
	var ignored_cells: Array[Vector3i] = [grid.get_unit_grid(attacker), grid.get_unit_grid(target)]
	for sample in samples:
		var blocker := _get_geometry_between(origin, sample, grid, false, ignored_cells)
		if blocker:
			if not first_blocker: first_blocker = blocker
		else:
			visible.append(sample)
	return {
		"visible_count": visible.size(),
		"sample_count": samples.size(),
		"aim_point": visible[0] if not visible.is_empty() else center,
		"blocker": first_blocker,
	}

static func _obstruction_label(visible: int, total: int) -> String:
	if visible <= 0: return "Blocked"
	if visible == total: return "Clear"
	if visible <= 2: return "Heavily obstructed"
	return "Partially obstructed"

static func get_directional_cover(attacker_cell: Vector3i, target_cell: Vector3i, grid: GridManager) -> MapCellData.CoverType:
	var delta = attacker_cell - target_cell
	var candidates: Array[Vector3i] = []
	if absi(delta.x) >= absi(delta.z) and delta.x != 0:
		candidates.append(target_cell + Vector3i(signi(delta.x), 0, 0))
	if absi(delta.z) >= absi(delta.x) and delta.z != 0:
		candidates.append(target_cell + Vector3i(0, 0, signi(delta.z)))

	var strongest = MapCellData.CoverType.NONE
	for cell in candidates:
		var data = grid.get_cell_data(cell)
		if data and data.cover_type > strongest:
			strongest = data.cover_type
	return strongest

static func get_blocking_cell(origin: Vector3, destination: Vector3, grid: GridManager) -> MapCellData:
	return _get_geometry_between(origin, destination, grid, true)

static func _get_geometry_between(origin: Vector3, destination: Vector3, grid: GridManager, los_blockers_only: bool, ignored_cells: Array[Vector3i] = []) -> MapCellData:
	var origin_cell = grid.world_to_grid(origin)
	var target_cell = grid.world_to_grid(destination)
	var candidates: Array = grid.map_data.los_blocking_cells if los_blockers_only else grid.map_data.cells.values()
	var grazed: Array[MapCellData] = []
	for data: MapCellData in candidates:
		if data.cover_height <= 0.0:
			continue
		if data.grid_position in ignored_cells:
			continue
		if data.grid_position == origin_cell or data.grid_position == target_cell:
			continue
		if _segment_enters_obstacle(origin, destination, data, grid.cell_size):
			return data
		if data.blocks_line_of_sight and _segment_enters_obstacle(origin, destination, data, grid.cell_size, true):
			for other in grazed:
				var delta := data.grid_position - other.grid_position
				if delta.y == 0 and absi(delta.x) == 1 and absi(delta.z) == 1:
					return data
			grazed.append(data)
	return null

static func _segment_enters_obstacle(origin: Vector3, destination: Vector3, cell: MapCellData, cell_size: float, closed_edges := false) -> bool:
	var inset := 0.001
	# Full-height obstacles meet at their edges. Shrinking their horizontal
	# bounds creates artificial cracks through touching diagonal blocks.
	var half_cell = cell_size * 0.5 + inset if closed_edges else cell_size * 0.5 - inset
	var minimum = Vector3(cell.world_position.x - half_cell, cell.world_position.y + inset, cell.world_position.z - half_cell)
	var maximum = Vector3(cell.world_position.x + half_cell, cell.world_position.y + cell.cover_height - inset, cell.world_position.z + half_cell)
	var direction = destination - origin
	var enter := 0.0
	var exit := 1.0
	for axis in 3:
		var start: float = origin[axis]
		var delta: float = direction[axis]
		if is_zero_approx(delta):
			if start <= minimum[axis] or start >= maximum[axis]:
				return false
			continue
		var first: float = (minimum[axis] - start) / delta
		var second: float = (maximum[axis] - start) / delta
		if first > second:
			var swap = first
			first = second
			second = swap
		enter = maxf(enter, first)
		exit = minf(exit, second)
		if enter >= exit:
			return false
	return exit > 0.0 and enter < 1.0
