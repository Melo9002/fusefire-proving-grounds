class_name CombatRules
extends RefCounted
static var cover_tuning = preload("res://systems/combat_cover_tuning.tres")

class AttackEvaluation:
	var is_legal: bool
	var hit_chance: int
	var cover_type: MapCellData.CoverType
	var reason: String
	var aim_point: Vector3
	var visibility_fraction: float
	var obstruction: String
	var blocking_cell: MapCellData
	var blocking_bounds := AABB()
	var cover_cell: MapCellData
	var cover_penalty := 0
	var obstruction_penalty := 0
	var protection_penalty := 0
	var distance_tiles := 0.0
	var range_fraction := 0.0
	var range_penalty := 0.0
	var height_modifier := 0.0
	var accuracy_bonus := 0
	var raw_chance := 0.0
	var base_accuracy := 0
	var minimum_hit_chance := 0
	var maximum_hit_chance := 100
	var shield_reason := ""
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
	return _evaluate_attack_cells(attacker, grid.get_unit_grid(attacker), target, grid.get_unit_grid(target), grid, accuracy_bonus, allow_shield)

## Pure checkpoint evaluation. Guard retains the mover's current Shield until
## movement resolves; completed-destination previews use evaluate_attack_after_move.
static func evaluate_attack_at_cell(attacker: TacticalUnit, target: TacticalUnit, target_cell: Vector3i, grid: GridManager, _world: World3D, accuracy_bonus := 0, allow_shield := true) -> AttackEvaluation:
	if not is_instance_valid(attacker):
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Invalid target")
	return _evaluate_attack_cells(attacker, grid.get_unit_grid(attacker), target, target_cell, grid, accuracy_bonus, allow_shield)

## A completed Move cancels the target's Shield. Do not mutate live stance for previews.
static func evaluate_attack_after_move(attacker: TacticalUnit, target: TacticalUnit, target_cell: Vector3i, grid: GridManager, world: World3D, accuracy_bonus := 0) -> AttackEvaluation:
	return evaluate_attack_at_cell(attacker, target, target_cell, grid, world, accuracy_bonus, false)

## Geometric coverage for a hypothetical hostile body, not AP/faction permission.
## Occupied cells use the actual body's height; empty cells use the shooter's height.
static func has_firing_lane_to_cell(attacker: TacticalUnit, target_cell: Vector3i, grid: GridManager) -> bool:
	if not is_instance_valid(attacker) or not attacker.stats or attacker.stats.is_defeated or attacker.is_carrying_unit(): return false
	var source := grid.get_unit_grid(attacker)
	if source == target_cell or not grid.map_data.has_cell(source) or not grid.map_data.has_cell(target_cell): return false
	if attack_distance(source, target_cell, grid) > attacker.attack_range: return false
	return _evaluate_target_visibility_cells(attacker, source, grid.get_unit_at(target_cell), target_cell, grid, true).visible_count > 0

## Pure outgoing preview. Moving cancels Aim, so callers should use zero bonus.
static func evaluate_attack_from_cell(attacker: TacticalUnit, attacker_cell: Vector3i, target: TacticalUnit, grid: GridManager, _world: World3D, accuracy_bonus := 0, allow_shield := true) -> AttackEvaluation:
	if not is_instance_valid(target):
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Invalid target")
	return _evaluate_attack_cells(attacker, attacker_cell, target, grid.get_unit_grid(target), grid, accuracy_bonus, allow_shield)

static func _evaluate_attack_cells(attacker: TacticalUnit, attacker_cell: Vector3i, target: TacticalUnit, target_cell: Vector3i, grid: GridManager, accuracy_bonus: int, allow_shield: bool) -> AttackEvaluation:
	if not is_instance_valid(attacker) or not is_instance_valid(target):
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Invalid target")
	if not cover_tuning.is_valid():
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Invalid combat tuning")
	if not grid.map_data.has_cell(attacker_cell) or not grid.map_data.has_cell(target_cell):
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Outside battlefield", target.global_position)
	var default_aim := _shot_destination_at(target, target_cell, grid)
	if attacker.is_carrying_unit():
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Cannot shoot while carrying", default_aim)
	if not attacker.stats or not target.stats or attacker.stats.is_defeated or target.stats.is_defeated:
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Unit defeated", default_aim)
	if not FactionRules.are_hostile(attacker.faction, target.faction):
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Not hostile", default_aim)
	if attacker.attack_range <= 0 or not is_finite(grid.cell_size) or grid.cell_size <= 0:
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Invalid attack range or tile size", default_aim)
	var distance := attack_distance(attacker_cell, target_cell, grid)
	if distance > attacker.attack_range:
		return AttackEvaluation.new(false, 0, MapCellData.CoverType.NONE, "Out of range", default_aim)
	var visibility := _evaluate_target_visibility_cells(attacker, attacker_cell, target, target_cell, grid)
	if visibility.visible_count == 0:
		var blocked := AttackEvaluation.new(false, 0, MapCellData.CoverType.FULL, "Blocked", visibility.aim_point, 0.0, "Blocked", visibility.blocker)
		blocked.blocking_bounds = _blocking_part_bounds(get_support_position(attacker_cell, grid) + Vector3.UP * attacker.standing_height, visibility.aim_point, visibility.blocker, grid.cell_size)
		return blocked
	var cover_cell := _protecting_cover(attacker_cell, target_cell, grid, attacker.standing_height, target.standing_height)
	var protection_origin := get_support_position(attacker_cell, grid) + Vector3.UP * attacker.standing_height
	var target_ground := get_support_position(target_cell, grid)
	var cover := _cover_type_for_ray(cover_cell, protection_origin, target_ground + Vector3.UP * target.standing_height * 0.5, target_ground.y, grid.cell_size)
	var cover_penalty: int = cover_tuning.full_cover_penalty if cover == MapCellData.CoverType.FULL else cover_tuning.low_cover_penalty if cover == MapCellData.CoverType.LOW else 0
	var obstruction_penalties := [50, 50, 40, 25, 10, 0]
	var obstruction_penalty: int = obstruction_penalties[visibility.visible_count]
	var shield := get_shield_protection_at_cells(attacker_cell, target, target_cell, grid) if allow_shield else {}
	var shield_accuracy := int(shield.get("accuracy_modifier", 0))
	var distance_fraction := distance / float(attacker.attack_range)
	var range_penalty: float = cover_tuning.range_penalty_for(distance_fraction)
	var height_delta := (get_support_position(attacker_cell, grid).y - target_ground.y) / grid.cell_size
	var height_modifier: float = cover_tuning.height_modifier_for(height_delta)
	var raw_chance: float = cover_tuning.base_accuracy - range_penalty - maxi(cover_penalty, obstruction_penalty) + height_modifier + accuracy_bonus + shield_accuracy
	var chance := chance_for_raw(raw_chance)
	var fraction: float = float(visibility.visible_count) / float(visibility.sample_count)
	var evaluation := AttackEvaluation.new(true, chance, cover, "", visibility.aim_point, fraction, _obstruction_label(visibility.visible_count, visibility.sample_count), visibility.blocker, bool(shield.get("applied", false)), shield_accuracy, float(shield.get("damage_multiplier", 1.0)))
	evaluation.shield_reason = String(shield.get("reason", ""))
	evaluation.cover_cell = cover_cell
	evaluation.cover_penalty = cover_penalty
	evaluation.obstruction_penalty = obstruction_penalty
	evaluation.protection_penalty = maxi(cover_penalty, obstruction_penalty)
	evaluation.distance_tiles = distance
	evaluation.range_fraction = distance_fraction
	evaluation.range_penalty = range_penalty
	evaluation.height_modifier = height_modifier
	evaluation.accuracy_bonus = accuracy_bonus
	evaluation.raw_chance = raw_chance
	evaluation.base_accuracy = cover_tuning.base_accuracy
	evaluation.minimum_hit_chance = cover_tuning.minimum_hit_chance
	evaluation.maximum_hit_chance = cover_tuning.maximum_hit_chance
	return evaluation

## The hit chance for an unclamped total: clamp to the tuning's limits, then round once. Epsilon absorbs
## arithmetic noise at exact half-points. The one place this rule lives, also used to value hypothetical
## modifiers such as a Shield stance that is not active yet.
static func chance_for_raw(raw_chance: float) -> int:
	return floori(clampf(raw_chance, cover_tuning.minimum_hit_chance, cover_tuning.maximum_hit_chance) + 0.5 + 0.0000001)

## Both committed facing and incoming direction use supported positions, not animation.
static func shield_direction(from_cell: Vector3i, to_cell: Vector3i, grid: GridManager) -> Vector2:
	var delta := get_support_position(to_cell, grid) - get_support_position(from_cell, grid)
	return Vector2(delta.x, delta.z).normalized()

static func get_shield_protection(attacker: TacticalUnit, target: TacticalUnit, grid: GridManager) -> Dictionary:
	if not is_instance_valid(attacker) or not is_instance_valid(target): return {"applied": false, "accuracy_modifier": 0, "damage_multiplier": 1.0}
	return get_shield_protection_at_cells(grid.get_unit_grid(attacker), target, grid.get_unit_grid(target), grid)

static func get_shield_protection_at_cells(attacker_cell: Vector3i, target: TacticalUnit, target_cell: Vector3i, grid: GridManager) -> Dictionary:
	if not is_instance_valid(target) or not target.tactical_state or not target.tactical_state.is_shielding or not target.shield_capability:
		return {"applied": false, "accuracy_modifier": 0, "damage_multiplier": 1.0}
	var incoming := shield_direction(target_cell, attacker_cell, grid)
	var in_arc := is_within_protected_arc(target.tactical_state.shield_facing, incoming, target.shield_capability.protected_arc_degrees)
	var has_capacity := target.shield_capability.has_capacity(target.tactical_state.shield_attacks_covered)
	var applied := in_arc and has_capacity
	var reason := "Outside Shield arc"
	if in_arc: reason = "Inside Shield arc" if has_capacity else "Shield overwhelmed (%d attacks already covered)" % target.tactical_state.shield_attacks_covered
	return {"applied": applied, "accuracy_modifier": target.shield_capability.accuracy_modifier if applied else 0, "damage_multiplier": target.shield_capability.damage_multiplier if applied else 1.0, "reason": reason}

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
	if not is_finite(grid.cell_size) or grid.cell_size <= 0: return INF
	var from := get_support_position(from_cell, grid)
	var to := get_support_position(to_cell, grid)
	return from.distance_to(to) / grid.cell_size if from.is_finite() and to.is_finite() else INF

static func can_reach_adjacent(from_cell: Vector3i, to_cell: Vector3i, grid: GridManager) -> bool:
	var delta := to_cell - from_cell
	if delta.y != 0 or delta == Vector3i.ZERO or absi(delta.x) > 1 or absi(delta.z) > 1:
		return false
	if grid.map_data.surface_placement_enabled:
		var from := grid.get_cell_data(from_cell)
		var to := grid.get_cell_data(to_cell)
		if not from or not to or from.world_position.distance_to(to.world_position) > grid.cell_size * 1.5: return false
		if not SurfaceNavigation.edge_clear(grid.map_data, from.world_position, to.world_position): return false
	if delta.x != 0 and delta.z != 0:
		for side in [from_cell + Vector3i(delta.x, 0, 0), from_cell + Vector3i(0, 0, delta.z)]:
			var data := grid.get_cell_data(side)
			if not data or not data.walkable or not data.can_stop:
				return false
	return true

static func has_line_of_sight_to_position(attacker: TacticalUnit, destination: Vector3, grid: GridManager, _world: World3D) -> bool:
	var target_cell = grid.world_to_grid(destination)
	var origin = get_support_position(grid.get_unit_grid(attacker), grid) + Vector3.UP * attacker.standing_height
	var target = get_support_position(target_cell, grid) + Vector3.UP * attacker.standing_height
	return get_blocking_cell(origin, target, grid) == null

static func get_blocking_cell_between_units(attacker: TacticalUnit, target: TacticalUnit, grid: GridManager) -> MapCellData:
	return get_blocking_cell(get_shot_origin(attacker, grid), get_shot_destination(target, grid), grid)

## Tactical surfaces, not animation transforms or rounded floor labels, anchor shots.
static func get_support_position(cell: Vector3i, grid: GridManager) -> Vector3:
	var data := grid.get_cell_data(cell)
	return data.world_position if data else grid.grid_to_world(cell)

static func get_shot_origin(attacker: TacticalUnit, grid: GridManager) -> Vector3:
	return get_support_position(grid.get_unit_grid(attacker), grid) + Vector3.UP * attacker.standing_height

static func get_shot_destination(target: TacticalUnit, grid: GridManager) -> Vector3:
	return get_support_position(grid.get_unit_grid(target), grid) + Vector3.UP * target.standing_height

static func _evaluate_target_visibility_cells(attacker: TacticalUnit, attacker_cell: Vector3i, target: TacticalUnit, target_cell: Vector3i, grid: GridManager, first_visible_only := false) -> Dictionary:
	var origin := get_support_position(attacker_cell, grid) + Vector3.UP * attacker.standing_height
	var body_height := target.standing_height if is_instance_valid(target) else attacker.standing_height
	var center := get_support_position(target_cell, grid) + Vector3.UP * body_height
	var horizontal := center - origin
	horizontal.y = 0.0
	var side := Vector3.RIGHT
	if not horizontal.is_zero_approx(): side = Vector3(-horizontal.z, 0.0, horizontal.x).normalized()
	var base := get_support_position(target_cell, grid)
	var samples: Array[Vector3] = [
		base + Vector3.UP * body_height * 1.2,
		base + Vector3.UP * body_height * 1.75,
		base + Vector3.UP * body_height * 0.9 + side * grid.cell_size * 0.28,
		base + Vector3.UP * body_height * 0.9 - side * grid.cell_size * 0.28,
		base + Vector3.UP * body_height * 0.5,
	]
	var visible: Array[Vector3] = []
	var first_blocker: MapCellData = null
	var blocked_aim := center
	var blocked_distance := INF
	var ignored_cells: Array[Vector3i] = [attacker_cell, target_cell]
	for sample in samples:
		# Boolean coverage can stop at one clear body sample. Full evaluations
		# explain the blocked sample nearest the body center, with stable ties.
		var distance := sample.distance_squared_to(center)
		var blocker := _get_geometry_between(origin, sample, grid, false, ignored_cells, not first_visible_only and distance < blocked_distance)
		if blocker:
			if distance < blocked_distance:
				first_blocker = blocker
				blocked_aim = sample
				blocked_distance = distance
		else:
			visible.append(sample)
			if first_visible_only: break
	return {"visible_count": visible.size(), "sample_count": samples.size(), "aim_point": visible[0] if not visible.is_empty() else blocked_aim, "blocker": first_blocker}

static func _shot_destination_at(target: TacticalUnit, target_cell: Vector3i, grid: GridManager) -> Vector3:
	return get_support_position(target_cell, grid) + Vector3.UP * target.standing_height

static func _obstruction_label(visible: int, total: int) -> String:
	if visible <= 0: return "Blocked"
	if visible == total: return "Clear"
	if visible <= 2: return "Heavily obstructed"
	return "Partially obstructed"

static func get_directional_cover(attacker_cell: Vector3i, target_cell: Vector3i, grid: GridManager, attacker_height := -1.0, target_height := -1.0) -> MapCellData.CoverType:
	var attacker := grid.get_unit_at(attacker_cell)
	var target := grid.get_unit_at(target_cell)
	if attacker_height < 0: attacker_height = attacker.standing_height if is_instance_valid(attacker) else 1.0
	if target_height < 0: target_height = target.standing_height if is_instance_valid(target) else 1.0
	var surface := _protecting_cover(attacker_cell, target_cell, grid, attacker_height, target_height)
	if not surface: return MapCellData.CoverType.NONE
	var origin := get_support_position(attacker_cell, grid) + Vector3.UP * attacker_height
	var ground := get_support_position(target_cell, grid)
	return _cover_type_for_ray(surface, origin, ground + Vector3.UP * target_height * 0.5, ground.y, grid.cell_size)

static func _protecting_cover(attacker_cell: Vector3i, target_cell: Vector3i, grid: GridManager, attacker_height: float, target_height: float) -> MapCellData:
	if not grid.map_data.has_cell(attacker_cell) or not grid.map_data.has_cell(target_cell): return null
	var origin := get_support_position(attacker_cell, grid) + Vector3.UP * attacker_height
	var ground := get_support_position(target_cell, grid)
	var protected_point := ground + Vector3.UP * target_height * 0.5
	var candidates: Array[MapCellData] = []
	var low_candidates: Array[MapCellData] = []
	# Strongest qualifying surface wins. The shared ray routine also handles
	# actual compound gaps and the same paired-corner sealing as shot legality.
	var nearby: Array[MapCellData] = []
	if grid.map_data.surface_placement_enabled:
		nearby = SurfaceNavigation.cover_surfaces(grid.map_data, ground)
	else:
		for offset in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
			var neighbor := grid.get_cell_data(target_cell + offset)
			if neighbor: nearby.append(neighbor)
	for cell in nearby:
		if not cell or cell.cover_type == MapCellData.CoverType.NONE: continue
		var kind := _cover_type_for_ray(cell, origin, protected_point, ground.y, grid.cell_size)
		if kind == MapCellData.CoverType.FULL: candidates.append(cell)
		elif kind == MapCellData.CoverType.LOW: low_candidates.append(cell)
	candidates.append_array(low_candidates)
	if candidates.is_empty(): return null
	return _get_geometry_between(origin, protected_point, grid, false, [attacker_cell, target_cell], false, candidates)

static func _cover_type_for_ray(cell: MapCellData, origin: Vector3, protected_point: Vector3, ground_y: float, cell_size: float) -> MapCellData.CoverType:
	if not cell: return MapCellData.CoverType.NONE
	if cell.authored_shot_parts.is_empty() and not cell.authored_shot_bounds.has_volume():
		return cell.cover_type
	var parts: Array[AABB] = cell.authored_shot_parts
	if parts.is_empty(): parts = [cell.authored_shot_bounds]
	var direct := MapCellData.CoverType.NONE
	var tangent := MapCellData.CoverType.NONE
	for part in parts:
		var kind := MapCellData.CoverType.FULL if part.end.y - ground_y >= 1.2 * cell_size else MapCellData.CoverType.LOW
		if is_finite(_bounds_entry(origin, protected_point, cell, cell_size, false, part)):
			direct = maxi(direct, kind) as MapCellData.CoverType
		elif is_finite(_bounds_entry(origin, protected_point, cell, cell_size, true, part)):
			tangent = maxi(tangent, kind) as MapCellData.CoverType
	# Tangency is only a candidate: the shared ray check must still confirm a
	# sealed pair. A tall tangent part cannot upgrade a genuinely low direct hit.
	return direct if direct != MapCellData.CoverType.NONE else tangent

static func get_blocking_cell(origin: Vector3, destination: Vector3, grid: GridManager) -> MapCellData:
	return _get_geometry_between(origin, destination, grid, true)

static func _get_geometry_between(origin: Vector3, destination: Vector3, grid: GridManager, los_blockers_only: bool, ignored_cells: Array[Vector3i] = [], nearest_blocker := true, selected_candidates: Array[MapCellData] = []) -> MapCellData:
	var origin_cell = grid.world_to_grid(origin)
	var target_cell = grid.world_to_grid(destination)
	var candidates: Array = _shot_candidates(grid, origin_cell, target_cell, los_blockers_only) if selected_candidates.is_empty() else selected_candidates
	var grazed: Array[Dictionary] = []
	var nearest: MapCellData = null
	var nearest_entry := INF
	for data: MapCellData in candidates:
		if data.is_vault_transit: continue # Solid geometry lives in the independent index.
		if data.cover_height <= 0.0:
			continue
		if not data.is_shot_only and data.grid_position in ignored_cells:
			continue
		if not data.is_shot_only and (data.grid_position == origin_cell or data.grid_position == target_cell):
			continue
		var entry := _obstacle_entry(origin, destination, data, grid.cell_size)
		if is_finite(entry) and not nearest_blocker: return data
		if is_finite(entry) and _closer_blocker(data, entry, nearest, nearest_entry):
			nearest = data
			nearest_entry = entry
		var closed_entry := _obstacle_entry(origin, destination, data, grid.cell_size, true) if data.blocks_line_of_sight else INF
		if is_finite(closed_entry):
			for other in grazed:
				var delta: Vector3i = data.grid_position - other.cell.grid_position
				if delta.y == 0 and absi(delta.x) == 1 and absi(delta.z) == 1:
					if not nearest_blocker: return data
					var seam_entry := maxf(closed_entry, float(other.entry))
					var seam_cell: MapCellData = data
					if float(other.entry) > closed_entry or (float(other.entry) == closed_entry and _closer_blocker(other.cell, seam_entry, data, seam_entry)):
						seam_cell = other.cell
					if _closer_blocker(seam_cell, seam_entry, nearest, nearest_entry):
						nearest = seam_cell
						nearest_entry = seam_entry
			grazed.append({"cell": data, "entry": closed_entry})
	return nearest

static func _closer_blocker(cell: MapCellData, entry: float, nearest: MapCellData, nearest_entry: float) -> bool:
	if entry != nearest_entry: return entry < nearest_entry
	if nearest == null: return true
	var a := cell.grid_position
	var b := nearest.grid_position
	return a.x < b.x or (a.x == b.x and (a.y < b.y or (a.y == b.y and a.z < b.z)))

static func _shot_candidates(grid: GridManager, from: Vector3i, to: Vector3i, los_blockers_only: bool) -> Array:
	var column_count := (absi(to.x - from.x) + 3) * (absi(to.z - from.z) + 3)
	var cell_count := grid.map_data.los_blocking_cells.size() if los_blockers_only else grid.map_data.cells.size() + grid.map_data.shot_obstacles.size()
	if not grid.map_floor or column_count >= cell_count:
		return grid.map_data.los_blocking_cells if los_blockers_only else grid.map_data.cells.values() + grid.map_data.shot_obstacles
	# The extra column on each edge preserves diagonal seam checks and the
	# narrow-phase tolerance at cell boundaries.
	var candidates: Array[MapCellData] = []
	for x in range(mini(from.x, to.x) - 1, maxi(from.x, to.x) + 2):
		for z in range(mini(from.z, to.z) - 1, maxi(from.z, to.z) + 2):
			for cell: MapCellData in grid.map_data.columns.get(Vector2i(x, z), []):
				if cell.cover_height > 0.0 and (not los_blockers_only or cell.blocks_line_of_sight):
					candidates.append(cell)
			candidates.append_array(grid.map_data.shot_columns.get(Vector2i(x, z), []))
	return candidates

static func _segment_enters_obstacle(origin: Vector3, destination: Vector3, cell: MapCellData, cell_size: float, closed_edges := false) -> bool:
	return is_finite(_obstacle_entry(origin, destination, cell, cell_size, closed_edges))

static func _obstacle_entry(origin: Vector3, destination: Vector3, cell: MapCellData, cell_size: float, closed_edges := false) -> float:
	if not cell.authored_shot_parts.is_empty():
		var nearest := INF
		for part in cell.authored_shot_parts:
			nearest = minf(nearest, _bounds_entry(origin, destination, cell, cell_size, closed_edges, part))
		return nearest
	return _bounds_entry(origin, destination, cell, cell_size, closed_edges, cell.authored_shot_bounds)

## Feedback highlights the intersected part, not a compound object's empty envelope.
static func _blocking_part_bounds(origin: Vector3, destination: Vector3, cell: MapCellData, cell_size: float) -> AABB:
	if not cell: return AABB()
	var nearest := INF
	var bounds := cell.authored_shot_bounds
	for part in cell.authored_shot_parts:
		var entry := _bounds_entry(origin, destination, cell, cell_size, true, part)
		if entry < nearest:
			nearest = entry
			bounds = part
	return bounds

static func _segment_enters_bounds(origin: Vector3, destination: Vector3, cell: MapCellData, cell_size: float, closed_edges: bool, bounds: AABB) -> bool:
	return is_finite(_bounds_entry(origin, destination, cell, cell_size, closed_edges, bounds))

static func _bounds_entry(origin: Vector3, destination: Vector3, cell: MapCellData, cell_size: float, closed_edges: bool, bounds: AABB) -> float:
	var inset := 0.001
	# Full-height obstacles meet at their edges. Shrinking their horizontal
	# bounds creates artificial cracks through touching diagonal blocks.
	var half_cell = cell_size * 0.5 + inset if closed_edges else cell_size * 0.5 - inset
	var minimum = Vector3(cell.world_position.x - half_cell, cell.world_position.y + inset, cell.world_position.z - half_cell)
	var maximum = Vector3(cell.world_position.x + half_cell, cell.world_position.y + cell.cover_height - inset, cell.world_position.z + half_cell)
	if bounds.has_volume():
		# Closed corner probes must include a part's touching edge too. Clamping
		# back to its open box discarded the exact seam after independent indexing.
		var edge_tolerance := Vector3(inset, 0, inset) if closed_edges else Vector3.ZERO
		minimum = minimum.max(bounds.position - edge_tolerance)
		maximum = maximum.min(bounds.end + edge_tolerance)
		if minimum.x >= maximum.x or minimum.y >= maximum.y or minimum.z >= maximum.z:
			return INF
	var direction = destination - origin
	var enter := 0.0
	var exit := 1.0
	for axis in 3:
		var start: float = origin[axis]
		var delta: float = direction[axis]
		if is_zero_approx(delta):
			if start <= minimum[axis] or start >= maximum[axis]:
				return INF
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
			return INF
	return enter if exit > 0.0 and enter < 1.0 else INF
