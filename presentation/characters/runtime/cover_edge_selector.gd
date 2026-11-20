class_name CoverEdgeSelector
extends RefCounted
## Chooses which side of a wall a unit would peek around, from the wall's real extent. PURE geometry: it reads the grid and the cover contact the pose
## code already has and returns a side. It never touches tactical state, visibility or protection, and knows nothing about enemies.
##
## SELECTION RULES (CoverPostureProfile holds the numbers):
##  1. Each end of the wall (left and right as the unit faces the wall) is a candidate edge with a distance along the wall from the unit.
##  2. An edge is USABLE when it is within `edge_reach` and the open ground just past the wall's end, and every cell between the unit and it, is
##     walkable, not cover and not occupied. An obstructed or unreachable edge is never chosen however near it is.
##  3. One usable edge: that one. None: NONE (a protected posture; the unit does not pretend to see around the wall).
##  4. Both usable: the nearer; if they differ by no more than `tie_tolerance`, the preferred `tie_side` (right).
##  5. HYSTERESIS: once a side is chosen it is kept while it stays usable, unless the other is nearer by more than `hysteresis`.
## Wall extent: tile maps scan neighbouring cover cells along the wall; surface maps use the contact's authored bounds (an AABB). Round or irregular
## obstacles have no clean end, so they yield NONE unless bounds are present: a documented limitation.

enum Side { LEFT = -1, NONE = 0, RIGHT = 1 }
## How a unit in cover presents an authorized attack (see plan_attack). PROTECTED is the passive posture (no attack).
enum FiringMode { PROTECTED, OVER_COVER, AROUND_LEFT, AROUND_RIGHT, ORDINARY }


## {"left": {"distance": m, "usable": bool}, "right": {...}, "normal": Vector3 (unit to wall), "tangent": Vector3 (toward the unit's right)}
static func edges(grid: GridManager, stand: Vector3, contact: Dictionary, profile: CoverPostureProfile) -> Dictionary:
	var result := {"left": {"distance": INF, "usable": false}, "right": {"distance": INF, "usable": false}, "normal": Vector3.ZERO, "tangent": Vector3.ZERO}
	var direction: Vector3 = contact.get("direction", Vector3.ZERO)
	direction.y = 0.0
	if grid == null or direction.length() < 0.01:
		return result
	direction = direction.normalized()
	var right := direction.cross(Vector3.UP).normalized()
	result.normal = direction
	result.tangent = right
	var bounds: Variant = contact.get("bounds", null)
	if grid.map_data.surface_placement_enabled:
		if not (bounds is AABB) or not (bounds as AABB).has_volume():
			return result
		var box: AABB = bounds
		var low := INF
		var high := -INF
		for corner in 8:
			var p := box.get_endpoint(corner)
			low = minf(low, p.dot(right))
			high = maxf(high, p.dot(right))
		var at := stand.dot(right)
		result.right = _surface_edge(grid, stand, right, high - at, profile)
		result.left = _surface_edge(grid, stand, -right, at - low, profile)
		return result
	var cell := grid.world_to_grid(stand)
	var step := Vector3i(roundi(right.x), 0, roundi(right.z))
	var toward := Vector3i(roundi(direction.x), 0, roundi(direction.z))
	var wall_cell := cell + toward
	result.right = _tile_edge(grid, cell, wall_cell, step, profile)
	result.left = _tile_edge(grid, cell, wall_cell, -step, profile)
	return result


static func _tile_edge(grid: GridManager, cell: Vector3i, wall_cell: Vector3i, step: Vector3i, profile: CoverPostureProfile) -> Dictionary:
	var along := 0
	while along < profile.wall_scan_limit:
		var next := grid.get_cell_data(wall_cell + step * (along + 1))
		if next == null or next.cover_height <= 0.0 or next.cover_type == MapCellData.CoverType.NONE:
			break
		along += 1
	var distance := (along + 0.5) * grid.cell_size
	var usable := distance <= profile.edge_reach
	if usable:
		# The ground the unit would walk over to look past the end: from its own cell to just past the wall.
		for k in range(1, along + 2):
			if not _open(grid, grid.get_cell_data(cell + step * k)):
				usable = false
				break
	return {"distance": distance, "usable": usable}


static func _surface_edge(grid: GridManager, stand: Vector3, along_dir: Vector3, distance: float, profile: CoverPostureProfile) -> Dictionary:
	var usable := distance <= profile.edge_reach and distance >= 0.0
	if usable:
		var own := grid.world_to_grid(stand)
		var probe := 0.0
		while probe <= distance + grid.cell_size * 0.6:
			var data := grid.get_cell_data(grid.world_to_grid(stand + along_dir * probe))
			# (The unit's own cell is occupied by the unit itself: only the ground it would walk over counts.)
			if data != null and data.grid_position != own and not _open(grid, data):
				usable = false
				break
			probe += grid.cell_size * 0.5
	return {"distance": maxf(distance, 0.0), "usable": usable}


static func _open(grid: GridManager, data: MapCellData) -> bool:
	return data != null and data.walkable and data.cover_height <= 0.0 and not grid.is_cell_occupied(data.grid_position)


## The side to peek around, with hysteresis from the `previous` side (NONE when there was none).
static func choose(found: Dictionary, previous: int, profile: CoverPostureProfile) -> int:
	var right: Dictionary = found.right
	var left: Dictionary = found.left
	var right_ok: bool = right.usable
	var left_ok: bool = left.usable
	if not right_ok and not left_ok:
		return Side.NONE
	if right_ok != left_ok:
		return Side.RIGHT if right_ok else Side.LEFT
	var wanted: int
	if absf(float(right.distance) - float(left.distance)) <= profile.tie_tolerance:
		wanted = profile.tie_side
	else:
		wanted = Side.RIGHT if float(right.distance) < float(left.distance) else Side.LEFT
	if previous != Side.NONE and previous != wanted:
		var kept: Dictionary = right if previous == Side.RIGHT else left
		var other: Dictionary = left if previous == Side.RIGHT else right
		if kept.usable and float(kept.distance) - float(other.distance) <= profile.hysteresis:
			return previous
	return wanted


## TARGET-AWARE FIRING PLAN for an attack the tactical layer has ALREADY authorized. `to_target` is the direction (world) to the attack's target position, which the
## action result carries; nothing else about the enemy is read or searched for, and this never decides whether a shot is legal. Only the geometry of the wall
## the unit stands against and the direction of the shot are used:
##  * the wall is not between unit and target (`open_side_threshold`)  -> ORDINARY (stand and fire, no peek);
##  * LOW cover                                                         -> OVER_COVER (rise and fire over the top);
##  * FULL cover, target clearly to one side                            -> around the edge on THAT side, if it is usable (a shot to the right passes the right end);
##  * FULL cover, target straight ahead (no side is better)             -> the passive choice (`previous`/`passive`), so a long wall keeps its existing fallback;
##  * FULL cover, the target's side edge is unusable                    -> the passive choice, and a mismatch is recorded (a legal shot with no plausible pose).
## `previous` is the side of an earlier attack, kept while the target stays within `attack_side_hysteresis` of straight ahead (no left/right flicker between
## consecutive attacks). `passive` is the passive-cover side (CoverEdgeSelector.choose). `face_distance` is how far the wall face is from the unit centre (m).
## Returns {"mode", "side", "mismatch": String ("" when none), "along": cos to the wall normal, "lateral": cos to the tangent (+ = right), "crossing": m}.
static func plan_attack(found: Dictionary, full_cover: bool, to_target: Vector3, previous: int, passive: int, face_distance: float, profile: CoverPostureProfile) -> Dictionary:
	var result := {"mode": FiringMode.ORDINARY, "side": Side.NONE, "mismatch": "", "along": 0.0, "lateral": 0.0, "crossing": INF}
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	var normal: Vector3 = found.get("normal", Vector3.ZERO)
	var tangent: Vector3 = found.get("tangent", Vector3.ZERO)
	if flat.length() < 0.01 or normal == Vector3.ZERO:
		return result
	flat = flat.normalized()
	var along := flat.dot(normal)
	var lateral := flat.dot(tangent)
	result.along = along
	result.lateral = lateral
	if along <= profile.open_side_threshold:
		return result
	if not full_cover:
		result.mode = FiringMode.OVER_COVER
		return result
	var side: int
	if absf(lateral) <= profile.straight_ahead_threshold:
		side = passive
		result.mismatch = "" if side != Side.NONE else "target_ahead_no_usable_edge"
	else:
		var wanted: int = Side.RIGHT if lateral > 0.0 else Side.LEFT
		if previous != Side.NONE and previous != wanted and absf(lateral) < profile.straight_ahead_threshold + profile.attack_side_hysteresis:
			var kept: Dictionary = found.right if previous == Side.RIGHT else found.left
			if kept.usable:
				wanted = previous
		var edge: Dictionary = found.right if wanted == Side.RIGHT else found.left
		if edge.usable:
			side = wanted
			# Does the straight line to the target clear the wall's end where it passes the wall's face? (Diagnostic only: the tactical shot was authorized from the
			# cell centre; a visual ray that still crosses the wall means no honest pose exists for it.)
			var forward := maxf(along, 0.05)
			var crossing := face_distance * absf(lateral) / forward
			result.crossing = crossing
			if crossing + 0.05 < float(edge.distance):
				result.mismatch = "ray_crosses_wall_end"
		else:
			side = passive
			result.mismatch = "target_side_edge_unusable"
	result.side = side
	if side == Side.NONE:
		result.mode = FiringMode.PROTECTED
		if result.mismatch.is_empty():
			result.mismatch = "no_usable_edge"
	else:
		result.mode = FiringMode.AROUND_RIGHT if side == Side.RIGHT else FiringMode.AROUND_LEFT
	return result

