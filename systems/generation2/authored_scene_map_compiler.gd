class_name AuthoredSceneMapCompiler
extends RefCounted
## Compiles explicit tactical metadata from an authored Godot scene into
## MapData. Editor-derived mesh parts use this same saved-metadata path;
## battle compilation never infers solids from rendering geometry.

const ShapeRules = preload("res://systems/generation2/tactical_shape_rules.gd")
const SHAPE_REVISION := ShapeRules.REVISION

static func is_active_solid(node: Node, revision := SHAPE_REVISION) -> bool:
	return ShapeRules.is_active_solid(node, revision)

static func compile(root: Node, data: MapData, cell_size: float, root_transform := Transform3D.IDENTITY, precise_shot_bounds := true, shape_revision := SHAPE_REVISION) -> void:
	var retired := retired_metadata(root)
	for issue in retired: data.generation_errors.append({"code": "RETIRED_ABSOLUTE_TACTICAL_METADATA", "detail": issue})
	if not retired.is_empty(): return
	if shape_revision >= 5 and bool(root.get_meta("surface_placement_enabled", false)):
		data.surface_placement_enabled = true
	# Establish every walkable surface before any object can stamp onto it.
	_compile_surfaces(root, root_transform, data, cell_size)
	_compile_contents(root, root_transform, data, cell_size, precise_shot_bounds, shape_revision)
	data.rebuild_los_index()

static func _compile_surfaces(node: Node, parent_transform: Transform3D, data: MapData, unit: float) -> void:
	var transform := parent_transform
	if node is Node3D: transform *= node.transform
	if node.has_meta("deck_local_rect"):
		var level := int(node.get_meta("deck_level"))
		data.elevation_labels[level] = String(node.get_meta("deck_label", "Maintenance walkway"))
		_stamp_local_deck(data, transform, node.get_meta("deck_local_rect"), level, unit)
	if node is ElevationPath:
		for step: Vector3i in node.get_cells():
			_stamp_local_deck(data, transform, Rect2i(step.x, step.z, 1, 1), step.y, unit, false)
			if node.blocks_ground:
				var ground := data.get_cell(_local_cell_to_grid(transform, Vector3i(step.x, 0, step.z), data, unit))
				if ground:
					ground.walkable = false
					ground.can_stop = false
					ground.cover_type = MapCellData.CoverType.FULL
					ground.cover_height = step.y * unit
					ground.blocks_line_of_sight = true
	for child in node.get_children():
		_compile_surfaces(child, transform, data, unit)

static func _compile_contents(node: Node, parent_transform: Transform3D, data: MapData, unit: float, precise_shot_bounds: bool, shape_revision: int) -> void:
	var transform := parent_transform
	if node is Node3D: transform *= node.transform
	if is_active_solid(node, shape_revision):
		# The pilot consumes existing part boxes automatically; ordinary assets
		# do not need a new per-asset flag to participate.
		var use_precise_bounds := precise_shot_bounds and (data.surface_placement_enabled or bool(node.get_meta("precise_shot_bounds", false)))
		_stamp_volume(data, transform, node.get_meta("solid_size"), node.get_meta("round_volume", false), unit, int(node.get_meta("movement_cost", 1)), use_precise_bounds, shape_revision >= 3, maxf(0.0, float(node.get_meta("standing_clearance", 0.0))), shape_revision >= 4)
	if node.has_meta("objective_zone_id"):
		var cells: Array[Vector3i] = []
		for local_cell: Vector3i in node.get_meta("objective_local_cells", []):
			cells.append(_local_cell_to_grid(transform, local_cell, data, unit))
		data.set_objective_zone(node.get_meta("objective_zone_id"), cells)
	if node.has_meta("deployment_faction"):
		var faction := int(node.get_meta("deployment_faction")) as TacticalUnit.Faction
		data.zones.erase(StringName("deployment_%d" % faction))
		for local_cell: Vector3i in node.get_meta("deployment_local_cells", []):
			data.add_spawn_cell(faction, _local_cell_to_grid(transform, local_cell, data, unit))
	if node.has_meta("ladder_local_bottom"):
		var bottom := _local_cell_to_grid(transform, node.get_meta("ladder_local_bottom"), data, unit)
		var top := _local_cell_to_grid(transform, node.get_meta("ladder_local_top"), data, unit)
		data.add_traversal_link(TraversalLinkData.new(bottom, top, true))
	for child in node.get_children():
		_compile_contents(child, transform, data, unit, precise_shot_bounds, shape_revision)

static func _stamp_local_deck(data: MapData, transform: Transform3D, rect: Rect2i, level: int, unit: float, include_slab := true) -> void:
	for x in range(rect.position.x, rect.end.x):
		for z in range(rect.position.y, rect.end.y):
			var position := _local_cell_to_grid(transform, Vector3i(x, level, z), data, unit)
			var ground := data.get_cell(Vector3i(position.x, 0, position.z))
			if ground == null: continue
			data.add_cell(MapCellData.new(position, ground.world_position + Vector3.UP * level * unit))
			if not include_slab: continue
			var slab := MapCellData.new(position - Vector3i.UP, ground.world_position + Vector3.UP * (level - 0.22) * unit)
			slab.support_surface = false
			slab.walkable = false; slab.can_stop = false; slab.cover_height = 0.22 * unit; slab.blocks_line_of_sight = true
			if data.surface_placement_enabled:
				data.movement_parts.append(AABB(slab.world_position - Vector3(unit * 0.5, 0, unit * 0.5), Vector3(unit, 0.22 * unit, unit)))
			data.add_cell(slab)

static func _local_cell_to_grid(transform: Transform3D, local: Vector3i, data: MapData, unit: float) -> Vector3i:
	var world := transform * Vector3(local)
	return Vector3i(roundi(world.x / unit + data.map_size.x * 0.5 - 0.5), roundi(world.y / unit), roundi(world.z / unit + data.map_size.y * 0.5 - 0.5))

static func _stamp_volume(data: MapData, transform: Transform3D, dimensions: Vector3, round_volume: bool, unit: float, movement_cost: int, precise_shot_bounds: bool, separate_parts := true, standing_clearance := 0.0, index_raised_shots := false) -> void:
	var bounds := transform * AABB(-dimensions * 0.5, dimensions)
	var world_units := data.surface_placement_enabled
	var coordinate_unit := unit if world_units else 1.0
	var shot_bounds := bounds if world_units else AABB(bounds.position * unit, bounds.size * unit)
	if data.surface_placement_enabled and not data.movement_parts.has(shot_bounds): data.movement_parts.append(shot_bounds)
	var lower := Vector2i(floori(bounds.position.x / coordinate_unit + data.map_size.x * 0.5), floori(bounds.position.z / coordinate_unit + data.map_size.y * 0.5))
	var upper := Vector2i(ceili(bounds.end.x / coordinate_unit + data.map_size.x * 0.5), ceili(bounds.end.z / coordinate_unit + data.map_size.y * 0.5))
	var inverse := transform.affine_inverse()
	var cell_margin := Vector2(0.5, 0.5)
	if standing_clearance > 0.0 or world_units:
		# Convert a grid cell's horizontal half-extents into the part's local
		# space. A fixed local margin would lose tiny scaled objects entirely.
		cell_margin = Vector2(absf(inverse.basis.x.x) + absf(inverse.basis.z.x), absf(inverse.basis.x.z) + absf(inverse.basis.z.z)) * 0.5 * coordinate_unit
	for x in range(maxi(0, lower.x), mini(data.map_size.x, upper.x)):
		for z in range(maxi(0, lower.y), mini(data.map_size.y, upper.y)):
			var covered_from_bottom := false
			for cell: MapCellData in data.columns.get(Vector2i(x, z), []):
				var height := cell.world_position.y if world_units else float(cell.grid_position.y)
				# New mesh-derived parts reserve a standing body's clearance below
				# their visible bottom. Shot geometry remains the actual part bounds.
				# Existing authored/historical shapes retain zero clearance by default.
				if height + standing_clearance * coordinate_unit < bounds.position.y - 0.001 or height >= bounds.end.y:
					continue
				var point := inverse * (cell.world_position if world_units else cell.world_position / unit)
				if absf(point.x) >= dimensions.x * 0.5 + cell_margin.x or absf(point.z) >= dimensions.z * 0.5 + cell_margin.y: continue
				if round_volume and pow(maxf(absf(point.x) - 0.5, 0.0) / (dimensions.x * 0.5), 2) + pow(maxf(absf(point.z) - 0.5, 0.0) / (dimensions.z * 0.5), 2) > 1.0: continue
				if data.surface_placement_enabled:
					if precise_shot_bounds and not round_volume:
						cell.surface_candidate = cell.surface_candidate or (cell.walkable and cell.can_stop)
					else: cell.surface_forbidden = true
				if height <= bounds.position.y + 0.001: covered_from_bottom = true
				cell.can_stop = false
				# Overlapping solids retain the conservative cell contract.
				if separate_parts and precise_shot_bounds and not round_volume and (cell.cover_height <= 0.0 or not cell.authored_shot_parts.is_empty()):
					cell.authored_shot_parts.append(shot_bounds)
					cell.authored_shot_bounds = shot_bounds if cell.authored_shot_parts.size() == 1 else cell.authored_shot_bounds.merge(shot_bounds)
				else:
					cell.authored_shot_parts.clear()
					cell.authored_shot_bounds = shot_bounds if precise_shot_bounds and not round_volume and cell.cover_height <= 0.0 else AABB()
				cell.cover_height = maxf(cell.cover_height, (bounds.end.y - height) * (1.0 if world_units else unit))
				cell.cover_type = MapCellData.CoverType.FULL if cell.cover_height >= 1.2 * unit else MapCellData.CoverType.LOW
				cell.walkable = cell.cover_type == MapCellData.CoverType.LOW
				cell.blocks_line_of_sight = cell.cover_type == MapCellData.CoverType.FULL
				if cell.walkable:
					cell.movement_cost = maxi(cell.movement_cost, movement_cost)
			if index_raised_shots and precise_shot_bounds and not round_volume and (not covered_from_bottom or data.surface_placement_enabled):
				# Keep the full raised part even when no standing cell can index it.
				# This is shot data only: do not create a floor or reserve ground.
				var position := Vector3((x - data.map_size.x * 0.5 + 0.5) * unit, shot_bounds.position.y, (z - data.map_size.y * 0.5 + 0.5) * unit)
				var obstacle := MapCellData.new(Vector3i(x, floori(bounds.position.y / coordinate_unit), z), position)
				obstacle.walkable = false
				obstacle.can_stop = false
				obstacle.cover_height = shot_bounds.size.y
				obstacle.blocks_line_of_sight = true
				obstacle.authored_shot_bounds = shot_bounds
				obstacle.cover_type = MapCellData.CoverType.FULL if shot_bounds.size.y >= unit * 1.2 else MapCellData.CoverType.LOW
				data.add_shot_obstacle(obstacle)

## The retired refinery recipe was the only known producer. Never silently
## ignore an old export: local coordinates are now the supported scene contract.
static func retired_metadata(root: Node) -> PackedStringArray:
	var failures := PackedStringArray()
	for key in ["deck_rect", "ladder_bottom", "ladder_top", "grid_origin", "faction"]:
		if root.has_meta(key): failures.append("%s uses retired metadata %s; use local deck, ladder or deployment metadata." % [root.name, key])
	for child in root.get_children(): failures.append_array(retired_metadata(child))
	return failures
