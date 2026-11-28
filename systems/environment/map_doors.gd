class_name MapDoors
extends RefCounted
## The atomic state change of an authored door (Milestone 06.09). It is the ONE place that edits compiled geometry after compilation, and it edits it only through a door the compiler recorded (DoorData).
##
## How it stays equal to a static map: `capture` runs once, at map build, after the map has been compiled with every door in its authored state AND again with one door in the other state (the same compiler,
## the same resolver). The cells that differ between the two maps are the door's complete affected region (the doorway, the cells beside the jambs, the cells the swung leaf covers or frees); their geometric
## fields, the leaf's movement parts and its shot obstacles are kept per state. `apply` then swaps exactly those, rebuilds the shot index and the movement-part index, and the caller rebuilds the movement graph
## from the map (the established MapGraphBuilder path). Everything else in the map, other objects' contributions and cell data that is not geometry (hazards, zones, spawns), is untouched.
##
## Everything here is synchronous: no other tactical query can run between the first write and the last, so a half-applied door is never visible; `apply` keeps a backup and `rollback` restores it exactly when the
## final self-check (or the graph rebuild) fails.

## Geometric fields of a cell: what a door's leaf can change. Nothing else of a cell is read or written.
const FIELDS: Array[StringName] = [&"world_position", &"elevation", &"walkable", &"can_stop", &"cover_type", &"cover_height", &"blocks_line_of_sight", &"authored_shot_bounds", &"authored_shot_parts", &"is_vault_transit", &"surface_candidate", &"surface_forbidden", &"movement_cost"]
## The leaf's half thickness for the swing test (the open leaf part is about 0.15 m thick).
const LEAF_HALF_THICKNESS := 0.1
## Test hook: when true, `apply_with_graph` fails after mutating, to prove the rollback restores the map. Never set outside tests.
static var fail_after_apply := false


static func snapshot(cell: MapCellData) -> Dictionary:
	var result := {}
	for field in FIELDS:
		var value: Variant = cell.get(field)
		result[field] = (value as Array).duplicate() if value is Array else value
	return result


static func write(cell: MapCellData, values: Dictionary) -> void:
	for field in FIELDS:
		var value: Variant = values[field]
		if value is Array:
			(cell.get(field) as Array).clear()
			(cell.get(field) as Array).append_array(value)
		else:
			cell.set(field, value)


## Called once per door after `main` (every door in its authored state) and `alternate` (this door in the other state) are compiled and resolved. False when the two maps do not differ in a way the door explains.
static func capture(main: MapData, alternate: MapData, door_id: StringName) -> bool:
	var door: DoorData = main.doors.get(door_id)
	var other_door: DoorData = alternate.doors.get(door_id)
	if door == null or other_door == null or other_door.state == door.state:
		return false
	var changed: Array[Vector3i] = []
	for position: Vector3i in main.cells.keys():
		var other_cell: MapCellData = alternate.cells.get(position)
		if other_cell != null and snapshot(main.cells[position]) != snapshot(other_cell):
			changed.append(position)
	for position: Vector3i in alternate.cells.keys():
		if not main.cells.has(position):
			return false   # the alternate has a cell the main map lacks: not a door difference
	var here := {}
	var there := {}
	for position in changed:
		here[position] = snapshot(main.cells[position])
		there[position] = snapshot(alternate.cells[position])
	door.cell_geometry[door.state] = here
	door.cell_geometry[other_door.state] = there
	door.movement_parts[other_door.state] = other_door.movement_parts.get(other_door.state, [])
	var mine: Array = []
	for obstacle: MapCellData in main.shot_obstacles:
		if obstacle.door_id == door_id: mine.append(obstacle)
	var theirs: Array = []
	for obstacle: MapCellData in alternate.shot_obstacles:
		if obstacle.door_id == door_id: theirs.append(obstacle)
	door.shot_obstacles[door.state] = mine
	door.shot_obstacles[other_door.state] = theirs
	return door.is_captured()


## Whether `actor` may move the door to `desired` now, and why not. Read-only. The caller (the action service) adds the turn and lifecycle checks.
## {ok, code, message}: a rejection changes nothing anywhere.
static func check(map: MapData, grid: GridManager, actor: TacticalUnit, door_id: StringName, desired: StringName) -> Dictionary:
	var door: DoorData = map.doors.get(door_id)
	if door == null or not door.is_captured():
		return _reject(&"door_missing", "There is no such door")
	if not is_instance_valid(actor) or actor.stats == null:
		return _reject(&"actor_missing", "Acting unit is unavailable")
	if actor.stats.is_defeated:
		return _reject(&"actor_defeated", "Acting unit is defeated")
	if door.state == desired:
		return _reject(&"already_" + String(desired), "The door is already %s" % desired)
	var actor_cell := grid.get_unit_grid(actor)
	var step := door.cell - actor_cell
	if step.y != 0 or absi(step.x) + absi(step.z) != 1:
		return _reject(&"out_of_range", "Stand directly beside the door (not diagonally)")
	var tile := map.get_cell(actor_cell)
	if tile == null:
		return _reject(&"out_of_range", "Stand directly beside the door")
	var direction := Vector3(step.x, 0.0, step.z)
	if not SurfaceNavigation._sweep_clear(map, tile.world_position, tile.world_position + direction * 0.1, true):
		return _reject(&"out_of_reach", "Something blocks the way to the door")
	if is_instance_valid(grid.get_unit_at(door.cell)):
		return _reject(&"door_occupied", "A unit is standing in the doorway")
	for unit: TacticalUnit in _units(grid):
		if unit == actor:
			continue
		if _unit_hits_leaf(map, door, grid, unit):
			return _reject(&"leaf_obstructed", "A unit is in the way of the door")
	# The operating unit steps clear of the swing as it moves the leaf: it is checked against where the leaf ends, and where the geometry around it changes.
	var after: Dictionary = door.cell_geometry.get(desired, {})
	for position: Vector3i in after.keys():
		var occupant := grid.get_unit_at(position)
		if is_instance_valid(occupant) and snapshot(map.cells[position]) != after[position]:
			return _reject(&"leaf_obstructed", "A unit is standing where the door would change the floor")
	for part: AABB in door.movement_parts.get(desired, []):
		if _circle_hits_box(Vector2(tile.world_position.x, tile.world_position.z), map.body_radius, part):
			return _reject(&"leaf_obstructed", "The door would swing into you; step back")
	return {"ok": true, "code": &"", "message": ""}


static func _reject(code: StringName, message: String) -> Dictionary:
	return {"ok": false, "code": code, "message": message}


static func _units(grid: GridManager) -> Array:
	var units: Array = []
	for cell: Vector3i in grid.occupancy_map.keys():
		var unit: TacticalUnit = grid.occupancy_map[cell]
		if is_instance_valid(unit) and not units.has(unit): units.append(unit)
	return units


## Whether a unit's body meets the leaf at any moment of its swing (the sector between the closed and the open pose, thickened by the leaf) or either end pose.
static func _unit_hits_leaf(map: MapData, door: DoorData, grid: GridManager, unit: TacticalUnit) -> bool:
	var tile := map.get_cell(grid.get_unit_grid(unit))
	if tile == null:
		return false
	var point := Vector2(tile.world_position.x, tile.world_position.z)
	for states in door.movement_parts.values():
		for part: AABB in states:
			if _circle_hits_box(point, map.body_radius, part):
				return true
	return _circle_hits_sector(point, map.body_radius + LEAF_HALF_THICKNESS, door.hinge, door.swing_radius, door.swing_from, door.swing_to)


static func _circle_hits_box(centre: Vector2, radius: float, box: AABB) -> bool:
	var nearest := Vector2(clampf(centre.x, box.position.x, box.end.x), clampf(centre.y, box.position.z, box.end.z))
	return centre.distance_to(nearest) <= radius


static func _circle_hits_sector(centre: Vector2, radius: float, hinge: Vector2, sector_radius: float, from_angle: float, to_angle: float) -> bool:
	if sector_radius <= 0.0:
		return false
	var offset := centre - hinge
	var distance := offset.length()
	# The sector runs the short way from the closed direction to the open one.
	var span := wrapf(to_angle - from_angle, -PI, PI)
	var low := from_angle if span >= 0.0 else from_angle + span
	span = absf(span)
	var angle := fposmod(atan2(offset.y, offset.x) - low, TAU)
	if angle <= span:
		return distance <= sector_radius + radius
	# Outside the angular range: the nearest part of the sector is one of its two straight edges.
	for edge in [low, low + span]:
		var end := hinge + Vector2(cos(edge), sin(edge)) * sector_radius
		if Geometry2D.get_closest_point_to_segment(centre, hinge, end).distance_to(centre) <= radius:
			return true
	return false


## The backup `rollback` needs: exactly what `apply` will touch.
static func _backup(map: MapData, door: DoorData) -> Dictionary:
	var cells := {}
	for position: Vector3i in door.cell_geometry[door.state].keys():
		cells[position] = snapshot(map.cells[position])
	var columns := {}
	for key: Vector2i in map.shot_columns.keys():
		columns[key] = (map.shot_columns[key] as Array).duplicate()
	return {"state": door.state, "cells": cells, "parts": map.movement_parts.duplicate(), "obstacles": map.shot_obstacles.duplicate(), "columns": columns}


## Moves the door to `state` in the map. Returns the backup (empty if the door cannot be moved). The map's movement graph is NOT rebuilt here (see apply_with_graph).
static func apply(map: MapData, door_id: StringName, state: StringName) -> Dictionary:
	var door: DoorData = map.doors.get(door_id)
	if door == null or not door.is_captured() or door.state == state or not door.cell_geometry.has(state):
		return {}
	for position: Vector3i in door.cell_geometry[state].keys():
		if not map.cells.has(position):
			return {}
	var backup := _backup(map, door)
	var old_state := door.state
	for position: Vector3i in door.cell_geometry[state].keys():
		write(map.cells[position], door.cell_geometry[state][position])
	for part: AABB in door.movement_parts.get(old_state, []):
		var index := map.movement_parts.find(part)
		if index >= 0: map.movement_parts.remove_at(index)
	for part: AABB in door.movement_parts.get(state, []):
		if not map.movement_parts.has(part): map.movement_parts.append(part)
	for obstacle: MapCellData in door.shot_obstacles.get(old_state, []):
		map.shot_obstacles.erase(obstacle)
		var column := Vector2i(obstacle.grid_position.x, obstacle.grid_position.z)
		if map.shot_columns.has(column): (map.shot_columns[column] as Array).erase(obstacle)
	for obstacle: MapCellData in door.shot_obstacles.get(state, []):
		map.shot_obstacles.append(obstacle)
		var column := Vector2i(obstacle.grid_position.x, obstacle.grid_position.z)
		if not map.shot_columns.has(column): map.shot_columns[column] = []
		(map.shot_columns[column] as Array).append(obstacle)
	SurfaceNavigation.refresh_movement_parts(map)
	map.rebuild_los_index()
	door.state = state
	return backup


static func rollback(map: MapData, door_id: StringName, backup: Dictionary) -> void:
	var door: DoorData = map.doors.get(door_id)
	if door == null or backup.is_empty():
		return
	for position: Vector3i in backup.cells.keys():
		write(map.cells[position], backup.cells[position])
	map.movement_parts.assign(backup.parts)
	map.shot_obstacles.assign(backup.obstacles)
	map.shot_columns.clear()
	for key: Vector2i in backup.columns.keys():
		map.shot_columns[key] = backup.columns[key]
	SurfaceNavigation.refresh_movement_parts(map)
	map.rebuild_los_index()
	door.state = backup.state


## The whole transition: the map change, then the movement graph rebuilt from the map (the existing builder), then a self-check that the result is the state asked for. On any failure the map is rolled back and
## the graph rebuilt from the restored map, and false is returned: the door is as it was.
static func apply_with_graph(map: MapData, pathfinder: Pathfinder, door_id: StringName, state: StringName) -> bool:
	var backup := apply(map, door_id, state)
	if backup.is_empty():
		return false
	var live_grid := pathfinder.live_grid
	MapGraphBuilder.build(map, pathfinder)
	pathfinder.live_grid = live_grid
	if fail_after_apply or not consistent(map, door_id):
		rollback(map, door_id, backup)
		MapGraphBuilder.build(map, pathfinder)
		pathfinder.live_grid = live_grid
		return false
	return true


## Every cell of the door's region holds the state's snapshot and the leaf's parts are in the map.
static func consistent(map: MapData, door_id: StringName) -> bool:
	var door: DoorData = map.doors.get(door_id)
	if door == null:
		return false
	for position: Vector3i in door.cell_geometry[door.state].keys():
		if snapshot(map.cells[position]) != door.cell_geometry[door.state][position]:
			return false
	for part: AABB in door.movement_parts.get(door.state, []):
		if not map.movement_parts.has(part):
			return false
	for part: AABB in door.movement_parts.get(DoorData.other(door.state), []):
		if map.movement_parts.has(part) and not (door.movement_parts.get(door.state, []) as Array).has(part):
			return false
	return true


## A short text for logs and tests: every door and its state.
static func states(map: MapData) -> String:
	var parts: Array[String] = []
	var ids := map.doors.keys()
	ids.sort()
	for id in ids:
		parts.append("%s=%s" % [id, (map.doors[id] as DoorData).state])
	return ",".join(parts)
