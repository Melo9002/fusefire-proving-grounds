class_name MapValidator
extends RefCounted

static func validate(map_data: MapData, pathfinder: Pathfinder, required_spawn_counts: Dictionary = {}) -> MapValidationResult:
	var result := MapValidationResult.new()
	if not map_data:
		result.add_error("MAP_MISSING", "MapData is missing.")
		return result
	if map_data.cells.is_empty():
		result.add_error("NO_CELLS", "The battlefield contains no cells.")
		return result

	_validate_cells(map_data, pathfinder, result)
	_validate_los_index(map_data, result)
	_validate_links(map_data, pathfinder, result)
	_validate_generated_traversals(map_data, pathfinder, result)
	_validate_platforms(map_data, result)
	_validate_hills(map_data, result)
	_validate_zones(map_data, result)
	_validate_mission_placement(map_data, pathfinder, result)
	_validate_spawns(map_data, pathfinder, required_spawn_counts, result)
	return result

static func _validate_generated_traversals(map_data: MapData, pathfinder: Pathfinder, result: MapValidationResult) -> void:
	for traversal in map_data.generated_traversals:
		if not traversal or not map_data.has_cell(traversal.from_cell) or not map_data.has_cell(traversal.to_cell):
			result.add_error("GENERATED_TRAVERSAL_ENDPOINT_MISSING", "Generated traversal references a missing endpoint.")
			continue
		var route := pathfinder.calculate_3d_path(traversal.from_cell, traversal.to_cell) if pathfinder else PackedVector3Array()
		if route.is_empty():
			result.add_error("GENERATED_TRAVERSAL_DISCONNECTED", "Generated traversal does not connect its endpoints.", traversal.from_cell, true)

static func _validate_platforms(map_data: MapData, result: MapValidationResult) -> void:
	for platform in map_data.platforms:
		if not platform or platform.cells.is_empty() or platform.elevation_level <= 0:
			result.add_error("INVALID_PLATFORM", "A generated platform is missing its elevation data.")
			continue
		var expected_count := platform.footprint.size.x * platform.footprint.size.y
		if platform.cells.size() != expected_count:
			result.add_error("INCOMPLETE_PLATFORM", "A generated platform does not cover its full footprint.")
		for position in platform.cells:
			var cell := map_data.get_cell(position)
			if not platform.footprint.has_point(Vector2i(position.x, position.z)) or position.y != platform.elevation_level:
				result.add_error("PLATFORM_CELL_MISMATCH", "A platform cell lies outside its declared surface.", position, true)
			elif not cell or not cell.walkable or not cell.can_stop:
				result.add_error("PLATFORM_CELL_INVALID", "A platform surface must contain walkable stopping cells.", position, true)

static func _validate_hills(map_data: MapData, result: MapValidationResult) -> void:
	for hill in map_data.hills:
		if not hill or hill.surface_cells.is_empty():
			result.add_error("INVALID_HILL", "A generated hill has no surface data.")
			continue
		var expected_count := hill.footprint.size.x * hill.footprint.size.y
		if hill.surface_cells.size() != expected_count:
			result.add_error("INCOMPLETE_HILL", "A generated hill does not cover its full footprint.")
		for position in hill.surface_cells:
			var surface := map_data.get_cell(position)
			var base := map_data.get_cell(Vector3i(position.x, 0, position.z))
			if not hill.footprint.has_point(Vector2i(position.x, position.z)) or position.y < 1 or position.y > 3:
				result.add_error("HILL_CELL_MISMATCH", "A hill cell lies outside its declared terrain.", position, true)
			elif not surface or not surface.walkable or not surface.can_stop or not base or base.walkable or not base.blocks_line_of_sight:
				result.add_error("HILL_CELL_INVALID", "A hill needs a walkable surface over solid terrain.", position, true)

static func _validate_cells(map_data: MapData, pathfinder: Pathfinder, result: MapValidationResult) -> void:
	for key in map_data.cells:
		var cell = map_data.cells[key] as MapCellData
		if not cell:
			result.add_error("NULL_CELL", "A map entry has no MapCellData.")
			continue
		if key != cell.grid_position:
			result.add_error("CELL_KEY_MISMATCH", "Dictionary key %s does not match the cell coordinate." % key, cell.grid_position, true)
		if not is_finite(cell.world_position.x) or not is_finite(cell.world_position.y) or not is_finite(cell.world_position.z):
			result.add_error("INVALID_WORLD_POSITION", "World position contains a non-finite value.", cell.grid_position, true)
		if not is_finite(cell.elevation):
			result.add_error("INVALID_ELEVATION", "Elevation is not finite.", cell.grid_position, true)
		if cell.movement_cost < 1:
			result.add_error("INVALID_MOVEMENT_COST", "Movement cost must be at least 1.", cell.grid_position, true)
		if cell.cover_height < 0.0:
			result.add_error("INVALID_COVER_HEIGHT", "Cover height cannot be negative.", cell.grid_position, true)
		if cell.can_stop and not cell.walkable:
			result.add_error("INVALID_STOP_CELL", "A stoppable cell must also be walkable.", cell.grid_position, true)
		if cell.cover_type == MapCellData.CoverType.LOW and (not cell.walkable or cell.can_stop or cell.cover_height <= 0.0):
			result.add_error("INVALID_LOW_COVER", "Low cover must be traversable, non-stoppable, and have positive height.", cell.grid_position, true)
		if cell.cover_type == MapCellData.CoverType.FULL and (cell.walkable or cell.can_stop or cell.cover_height <= 0.0):
			result.add_error("INVALID_FULL_COVER", "Full cover must block walking and have positive height.", cell.grid_position, true)
		if cell.blocks_line_of_sight and cell.cover_height <= 0.0:
			result.add_error("INVALID_LOS_BLOCKER", "LOS-blocking terrain must have positive height.", cell.grid_position, true)
		if not pathfinder or not pathfinder.grid_to_id_map.has(cell.grid_position):
			result.add_error("PATH_NODE_MISSING", "Cell has no matching pathfinding node.", cell.grid_position, true)
		elif pathfinder.astar.is_point_disabled(pathfinder.grid_to_id_map[cell.grid_position]) == cell.walkable:
			result.add_error("PATH_STATE_MISMATCH", "Pathfinding availability disagrees with walkability.", cell.grid_position, true)

static func _validate_los_index(map_data: MapData, result: MapValidationResult) -> void:
	var indexed: Dictionary = {}
	for blocker in map_data.los_blocking_cells:
		if not blocker or (not map_data.shot_obstacles.has(blocker) if blocker.is_shot_only else map_data.get_cell(blocker.grid_position) != blocker):
			result.add_error("UNKNOWN_LOS_BLOCKER", "The LOS index references a missing cell.")
			continue
		indexed[blocker] = true
		if not blocker.blocks_line_of_sight or blocker.cover_height <= 0.0:
			result.add_error("STALE_LOS_BLOCKER", "The LOS index contains terrain that cannot block shots.", blocker.grid_position, true)
	for cell: MapCellData in map_data.cells.values():
		if cell.blocks_line_of_sight and cell.cover_height > 0.0 and not indexed.has(cell):
			result.add_error("LOS_BLOCKER_NOT_INDEXED", "LOS-blocking terrain is absent from the LOS index.", cell.grid_position, true)
	for obstacle: MapCellData in map_data.shot_obstacles:
		var column := Vector2i(obstacle.grid_position.x, obstacle.grid_position.z)
		var bounds := obstacle.authored_shot_bounds
		var finite := true
		for axis in 3:
			finite = finite and is_finite(bounds.position[axis]) and is_finite(bounds.size[axis])
		if not obstacle.is_shot_only or obstacle.walkable or obstacle.can_stop or not finite or not bounds.has_volume() or not Rect2i(Vector2i.ZERO, map_data.map_size).has_point(column):
			result.add_error("INVALID_SHOT_OBSTACLE", "Raised shot geometry must have finite bounds inside the map and cannot be walkable.", obstacle.grid_position, true)
		if not indexed.has(obstacle) or not map_data.shot_columns.get(column, []).has(obstacle):
			result.add_error("SHOT_OBSTACLE_NOT_INDEXED", "Raised shot geometry is missing from its LOS or column index.", obstacle.grid_position, true)

static func _validate_links(map_data: MapData, pathfinder: Pathfinder, result: MapValidationResult) -> void:
	for link in map_data.traversal_links:
		if not link:
			result.add_error("NULL_TRAVERSAL_LINK", "Traversal-link data is missing.")
			continue
		if link.from_cell == link.to_cell:
			result.add_error("SELF_TRAVERSAL_LINK", "A traversal link cannot connect a cell to itself.", link.from_cell, true)
		for endpoint in [link.from_cell, link.to_cell]:
			var cell := map_data.get_cell(endpoint)
			if not cell:
				result.add_error("TRAVERSAL_ENDPOINT_MISSING", "Traversal link references a missing endpoint.", endpoint, true)
			elif not cell.walkable or not cell.can_stop:
				result.add_error("TRAVERSAL_ENDPOINT_INVALID", "Traversal endpoint must be a walkable stopping cell.", endpoint, true)
		if pathfinder and map_data.has_cell(link.from_cell) and map_data.has_cell(link.to_cell):
			var from_id: int = pathfinder.grid_to_id_map.get(link.from_cell, -1)
			var to_id: int = pathfinder.grid_to_id_map.get(link.to_cell, -1)
			if from_id < 0 or to_id < 0 or not pathfinder.astar.are_points_connected(from_id, to_id, link.bidirectional):
				result.add_error("TRAVERSAL_LINK_DISCONNECTED", "Traversal link is absent from the path graph.", link.from_cell, true)

static func _validate_spawns(map_data: MapData, pathfinder: Pathfinder, required_counts: Dictionary, result: MapValidationResult) -> void:
	var occupied_spawn_cells: Dictionary = {}
	for faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ENEMY, TacticalUnit.Faction.ALLY, TacticalUnit.Faction.NEUTRAL]:
		var faction_cells: Array[Vector3i] = map_data.get_spawn_cells(faction)
		for cell_position in faction_cells:
			if occupied_spawn_cells.has(cell_position):
				result.add_error("DUPLICATE_SPAWN", "Spawn cell is assigned to more than one position or faction.", cell_position, true)
			occupied_spawn_cells[cell_position] = faction
			var cell := map_data.get_cell(cell_position)
			if not cell:
				result.add_error("SPAWN_CELL_MISSING", "Spawn references a cell outside the battlefield.", cell_position, true)
			elif not cell.walkable or not cell.can_stop:
				result.add_error("SPAWN_CELL_INVALID", "Spawn must be a walkable stopping cell.", cell_position, true)

	for faction in required_counts:
		var required: int = required_counts[faction]
		var available := map_data.get_spawn_cells(faction).size()
		if available < required:
			result.add_error("INSUFFICIENT_SPAWNS", "Faction %s needs %d spawn cells but has %d." % [faction, required, available])

	var player_spawns := map_data.get_spawn_cells(TacticalUnit.Faction.PLAYER)
	var enemy_spawns := map_data.get_spawn_cells(TacticalUnit.Faction.ENEMY)
	if player_spawns.is_empty() or enemy_spawns.is_empty():
		result.add_error("OPPOSING_SPAWNS_MISSING", "Player and enemy spawn data are both required.")
		return
	if not pathfinder:
		result.add_error("PATHFINDER_MISSING", "Spawn connectivity cannot be checked without a pathfinder.")
		return
	var combat_factions := [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ALLY, TacticalUnit.Faction.ENEMY]
	for first_index in combat_factions.size():
		var first_faction: TacticalUnit.Faction = combat_factions[first_index]
		for second_index in range(first_index + 1, combat_factions.size()):
			var second_faction: TacticalUnit.Faction = combat_factions[second_index]
			if not FactionRules.are_hostile(first_faction, second_faction):
				continue
			for first_cell in map_data.get_spawn_cells(first_faction):
				for second_cell in map_data.get_spawn_cells(second_faction):
					if map_data.has_cell(first_cell) and map_data.has_cell(second_cell) \
						and pathfinder.calculate_3d_path(first_cell, second_cell).is_empty():
						result.add_error("SPAWNS_DISCONNECTED", "Hostile spawn cells do not share a route: %s -> %s." % [first_cell, second_cell])

static func _validate_zones(map_data: MapData, result: MapValidationResult) -> void:
	for zone in map_data.zones.values():
		if not zone or zone.zone_id.is_empty():
			result.add_error("INVALID_ZONE", "A map zone is missing its identity data.")
			continue
		if zone.cells.is_empty():
			result.add_error("EMPTY_ZONE", "Zone %s contains no cells." % zone.zone_id)
		var seen: Dictionary[Vector3i, bool] = {}
		for position in zone.cells:
			if seen.has(position):
				result.add_error("DUPLICATE_ZONE_CELL", "Zone %s repeats a cell." % zone.zone_id, position, true)
			seen[position] = true
			var cell := map_data.get_cell(position)
			if not cell:
				result.add_error("ZONE_CELL_MISSING", "Zone %s references a cell outside the battlefield." % zone.zone_id, position, true)
			elif not cell.walkable or not cell.can_stop:
				result.add_error("ZONE_CELL_INVALID", "Zone %s must use walkable stopping cells." % zone.zone_id, position, true)

static func _validate_mission_placement(map_data: MapData, pathfinder: Pathfinder, result: MapValidationResult) -> void:
	if not pathfinder:
		return
	var deployment_cells: Dictionary[Vector3i, bool] = {}
	for zone in map_data.get_zones_by_kind(MapZoneData.Kind.DEPLOYMENT):
		for position in zone.cells:
			deployment_cells[position] = true
	var occupied: Dictionary[Vector3i, StringName] = {}
	for zone_id in [&"reach", &"extract", &"enemy_extract", &"rescue_spawn"]:
		var zone := map_data.get_zone(zone_id)
		if not zone:
			continue
		for position in zone.cells:
			if deployment_cells.has(position):
				result.add_error("MISSION_ZONE_OVERLAPS_DEPLOYMENT", "Mission zone %s overlaps deployment." % zone_id, position, true)
			if occupied.has(position):
				result.add_error("MISSION_ZONES_OVERLAP", "Mission zones %s and %s overlap." % [occupied[position], zone_id], position, true)
			occupied[position] = zone_id
		var origins := map_data.get_spawn_cells(TacticalUnit.Faction.ENEMY if zone_id == &"enemy_extract" else TacticalUnit.Faction.PLAYER)
		for position in zone.cells:
			var reachable := false
			for origin in origins:
				if not pathfinder.calculate_3d_path(origin, position).is_empty():
					reachable = true
					break
			if not reachable:
				result.add_error("MISSION_ZONE_UNREACHABLE", "Mission zone %s cannot be reached by its pursuing faction." % zone_id, position, true)
