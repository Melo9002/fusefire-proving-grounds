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
