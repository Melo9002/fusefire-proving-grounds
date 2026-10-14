class_name FlatMapGenerator
extends RefCounted

const RefineryLayout = preload("res://systems/generation/refinery_layout_builder.gd")
const IndustrialWarehouseLayout = preload("res://systems/generation/industrial_warehouse_layout_builder.gd")

const MAP_SIZES: Array[Vector2i] = [Vector2i(24, 20), Vector2i(32, 24), Vector2i(40, 30)]
const CONTAINER_HEIGHT := 2.0
const BUILDING_ROOF_LEVEL := 3

static func generate(width: int, depth: int, cell_size: float, map_seed: int, spawn_capacity: int = 5) -> MapData:
	var map_data := MapData.new()
	map_data.source_kind = "generated_flat"
	map_data.generation_seed = map_seed
	map_data.map_size = Vector2i(width, depth)
	var half_width := float(width) * cell_size * 0.5
	var half_depth := float(depth) * cell_size * 0.5
	for x in width:
		for z in depth:
			var cell_position := Vector3i(x, 0, z)
			var world_position := Vector3(
				float(x) * cell_size - half_width + cell_size * 0.5,
				0.0,
				float(z) * cell_size - half_depth + cell_size * 0.5
			)
			map_data.add_cell(MapCellData.new(cell_position, world_position))

	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	var available_rows: Array[int] = []
	for z in range(1, depth - 1):
		available_rows.append(z)
	_shuffle(available_rows, rng)
	var player_rows := available_rows.slice(0, spawn_capacity)
	_shuffle(available_rows, rng)
	var enemy_rows := available_rows.slice(0, spawn_capacity)
	_shuffle(available_rows, rng)
	var ally_rows := available_rows.slice(0, spawn_capacity)
	var player_x := 1
	var enemy_x := width - 2
	if rng.randi_range(0, 1) == 1:
		player_x = width - 2
		enemy_x = 1
	for row in player_rows:
		map_data.add_spawn_cell(TacticalUnit.Faction.PLAYER, Vector3i(player_x, 0, row))
	for row in enemy_rows:
		map_data.add_spawn_cell(TacticalUnit.Faction.ENEMY, Vector3i(enemy_x, 0, row))
	var ally_x := player_x + (1 if player_x < enemy_x else -1)
	for row in ally_rows:
		map_data.add_spawn_cell(TacticalUnit.Faction.ALLY, Vector3i(ally_x, 0, row))
	map_data.rebuild_los_index()
	return map_data

static func generate_with_cover(width: int, depth: int, cell_size: float, map_seed: int, spawn_capacity: int = 5, refinery: bool = false, industrial_warehouse: bool = false) -> MapData:
	var map_data := generate(width, depth, cell_size, map_seed, spawn_capacity)
	map_data.source_kind = "generated_cover"
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed ^ 0x5F3759DF
	var center_row := floori(float(depth) / 2.0)
	var anchors: Array[Vector3i] = []
	for x in range(5, width - 5):
		for z in range(2, depth - 2):
			anchors.append(Vector3i(x, 0, z))
	_shuffle_cells(anchors, rng)
	var building_cells := 0
	if industrial_warehouse:
		IndustrialWarehouseLayout.apply(map_data, cell_size)
	elif refinery:
		RefineryLayout.apply(map_data, cell_size)
	else:
		building_cells = _place_buildings(map_data, anchors, rng, width, depth, center_row, cell_size)
		GeneratedBuildingExpansion.apply(map_data, rng)
		GeneratedElevationPlacer.apply(map_data, rng, cell_size)
	var access_rng := RandomNumberGenerator.new()
	access_rng.seed = 2202
	GeneratedTraversalBuilder.apply(map_data, access_rng if refinery or industrial_warehouse else rng, cell_size)
	if refinery:
		map_data.source_kind = "generated_refinery"
	if industrial_warehouse:
		map_data.source_kind = IndustrialWarehouseLayout.SOURCE_KIND
		map_data.rebuild_los_index()
		return map_data
	var container_cells := _place_containers(map_data, anchors, rng, width, depth, center_row)

	var desired_cover := clampi(floori(float(width * depth) / 10.0), 12, anchors.size())
	var placed := building_cells + container_cells
	var templates := _formation_templates()
	var template_offset := rng.randi_range(0, templates.size() - 1)
	for anchor in anchors:
		if placed >= desired_cover:
			break
		var template: Array = templates[(template_offset + placed) % templates.size()]
		var rotation := rng.randi_range(0, 3)
		var formation := _rotated_formation(anchor, template, rotation)
		if not _can_place_formation(map_data, formation, width, depth, center_row):
			continue
		_apply_formation(map_data, formation)
		placed += formation.size()
	map_data.rebuild_los_index()
	return map_data

static func _formation_templates() -> Array[Array]:
	return [
		[[Vector2i(0, 0), MapCellData.CoverType.LOW], [Vector2i(1, 0), MapCellData.CoverType.FULL], [Vector2i(2, 0), MapCellData.CoverType.LOW]],
		[[Vector2i(0, 0), MapCellData.CoverType.FULL], [Vector2i(1, 0), MapCellData.CoverType.LOW], [Vector2i(0, 1), MapCellData.CoverType.LOW]],
		[[Vector2i(0, 0), MapCellData.CoverType.LOW], [Vector2i(1, 0), MapCellData.CoverType.LOW], [Vector2i(2, 0), MapCellData.CoverType.LOW]],
		[[Vector2i(0, 0), MapCellData.CoverType.LOW], [Vector2i(1, 0), MapCellData.CoverType.LOW], [Vector2i(2, 1), MapCellData.CoverType.FULL]],
	]

static func _rotated_formation(anchor: Vector3i, template: Array, rotation: int) -> Array:
	var formation: Array = []
	for member in template:
		var offset: Vector2i = member[0]
		for step in rotation:
			offset = Vector2i(-offset.y, offset.x)
		formation.append([anchor + Vector3i(offset.x, 0, offset.y), member[1]])
	return formation

static func _can_place_formation(map_data: MapData, formation: Array, width: int, depth: int, center_row: int) -> bool:
	for member in formation:
		var grid_position: Vector3i = member[0]
		for building in map_data.buildings:
			if building.reserved_area.has_point(Vector2i(grid_position.x, grid_position.z)):
				return false
		for platform in map_data.platforms:
			if platform.reserved_area.has_point(Vector2i(grid_position.x, grid_position.z)):
				return false
		for hill in map_data.hills:
			if hill.reserved_area.has_point(Vector2i(grid_position.x, grid_position.z)):
				return false
		if _is_generated_traversal_column(map_data, grid_position):
			return false
		for footprint in map_data.containers:
			if footprint.grow(1).has_point(Vector2i(grid_position.x, grid_position.z)):
				return false
		var cover_type: MapCellData.CoverType = member[1]
		if grid_position.x < 5 or grid_position.x >= width - 5 or grid_position.z < 2 or grid_position.z >= depth - 2:
			return false
		if absi(grid_position.z - center_row) <= 1:
			return false
		var cell := map_data.get_cell(grid_position)
		if not cell or not cell.walkable or cell.cover_type != MapCellData.CoverType.NONE:
			return false
		if cover_type == MapCellData.CoverType.FULL and _has_adjacent_full_cover(map_data, grid_position):
			return false
	return true

static func _place_containers(map_data: MapData, anchors: Array[Vector3i], rng: RandomNumberGenerator, width: int, depth: int, center_row: int) -> int:
	var desired := maxi(1, floori(float(width * depth) / 300.0))
	for anchor in anchors:
		if map_data.containers.size() >= desired:
			break
		var dimensions := Vector2i(3, 2) if rng.randi_range(0, 1) == 0 else Vector2i(2, 3)
		var footprint := Rect2i(Vector2i(anchor.x, anchor.z), dimensions)
		var clearance := footprint.grow(1)
		if clearance.position.x < 5 or clearance.end.x > width - 5 or clearance.position.y < 2 or clearance.end.y > depth - 2:
			continue
		if clearance.position.y <= center_row + 1 and clearance.end.y > center_row - 1:
			continue
		var overlaps := false
		for building in map_data.buildings:
			if building.reserved_area.intersects(clearance):
				overlaps = true
		for platform in map_data.platforms:
			if platform.reserved_area.intersects(clearance):
				overlaps = true
		for hill in map_data.hills:
			if hill.reserved_area.intersects(clearance):
				overlaps = true
		for existing in map_data.containers:
			if existing.grow(1).intersects(clearance):
				overlaps = true
		if overlaps:
			continue
		for x in range(clearance.position.x, clearance.end.x):
			for z in range(clearance.position.y, clearance.end.y):
				if _is_generated_traversal_column(map_data, Vector3i(x, 0, z)) or not map_data.get_cell(Vector3i(x, 0, z)).walkable:
					overlaps = true
		if overlaps:
			continue
		map_data.containers.append(footprint)
		for x in range(footprint.position.x, footprint.end.x):
			for z in range(footprint.position.y, footprint.end.y):
				var cell := map_data.get_cell(Vector3i(x, 0, z))
				cell.cover_type = MapCellData.CoverType.FULL
				cell.cover_height = CONTAINER_HEIGHT
				cell.blocks_line_of_sight = true
				cell.walkable = false
				cell.can_stop = false
	return map_data.containers.size() * 6

static func _place_buildings(map_data: MapData, anchors: Array[Vector3i], rng: RandomNumberGenerator, width: int, depth: int, center_row: int, cell_size: float) -> int:
	var desired := 2 if width * depth >= 1000 else 1
	for anchor in anchors:
		if map_data.buildings.size() >= desired:
			break
		var dimensions := Vector2i(4, 3) if rng.randi_range(0, 1) == 0 else Vector2i(3, 4)
		var footprint := Rect2i(Vector2i(anchor.x, anchor.z), dimensions)
		var clearance := footprint.grow(2)
		if clearance.position.x < 5 or clearance.end.x > width - 5 or clearance.position.y < 2 or clearance.end.y > depth - 2:
			continue
		if clearance.position.y <= center_row + 1 and clearance.end.y > center_row - 1:
			continue
		var overlaps_structure := false
		for existing in map_data.buildings:
			if existing.footprint.grow(2).intersects(clearance):
				overlaps_structure = true
		if overlaps_structure:
			continue
		var side := rng.randi_range(0, 3)
		var roof_2d := Vector2i.ZERO
		var ground_2d := Vector2i.ZERO
		match side:
			0:
				roof_2d = Vector2i(footprint.position.x, footprint.position.y + floori(float(footprint.size.y) / 2.0))
				ground_2d = roof_2d + Vector2i.LEFT
			1:
				roof_2d = Vector2i(footprint.end.x - 1, footprint.position.y + floori(float(footprint.size.y) / 2.0))
				ground_2d = roof_2d + Vector2i.RIGHT
			2:
				roof_2d = Vector2i(footprint.position.x + floori(float(footprint.size.x) / 2.0), footprint.position.y)
				ground_2d = roof_2d + Vector2i.UP
			_:
				roof_2d = Vector2i(footprint.position.x + floori(float(footprint.size.x) / 2.0), footprint.end.y - 1)
				ground_2d = roof_2d + Vector2i.DOWN
		var ground_cell := map_data.get_cell(Vector3i(ground_2d.x, 0, ground_2d.y))
		if not ground_cell or ground_cell.cover_type != MapCellData.CoverType.NONE:
			continue
		for existing in map_data.buildings:
			if existing.footprint.grow(1).has_point(ground_2d):
				overlaps_structure = true
		if overlaps_structure:
			continue
		var building := GeneratedBuildingData.new(
			footprint,
			BUILDING_ROOF_LEVEL,
			ground_cell.grid_position,
			Vector3i(roof_2d.x, BUILDING_ROOF_LEVEL, roof_2d.y)
		)
		map_data.buildings.append(building)
		for x in range(footprint.position.x, footprint.end.x):
			for z in range(footprint.position.y, footprint.end.y):
				var base := map_data.get_cell(Vector3i(x, 0, z))
				base.cover_type = MapCellData.CoverType.FULL
				base.cover_height = float(BUILDING_ROOF_LEVEL) * cell_size
				base.blocks_line_of_sight = true
				base.walkable = false
				base.can_stop = false
				var roof_position := base.world_position + Vector3.UP * float(BUILDING_ROOF_LEVEL) * cell_size
				map_data.add_cell(MapCellData.new(Vector3i(x, BUILDING_ROOF_LEVEL, z), roof_position))
		map_data.add_traversal_link(TraversalLinkData.new(building.ladder_ground_cell, building.ladder_roof_cell, true))
	return map_data.buildings.size() * 12

static func _apply_formation(map_data: MapData, formation: Array) -> void:
	for member in formation:
		var cell := map_data.get_cell(member[0])
		cell.cover_type = member[1]
		cell.can_stop = false
		if cell.cover_type == MapCellData.CoverType.FULL:
			cell.cover_height = 2.0
			cell.blocks_line_of_sight = true
			cell.walkable = false
		else:
			cell.cover_height = 1.0
			cell.walkable = true
			cell.movement_cost = 2

static func _shuffle(values: Array[int], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[swap_index]
		values[swap_index] = held

static func _shuffle_cells(values: Array[Vector3i], rng: RandomNumberGenerator) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index := rng.randi_range(0, index)
		var held := values[index]
		values[index] = values[swap_index]
		values[swap_index] = held

static func _has_adjacent_full_cover(map_data: MapData, grid_position: Vector3i) -> bool:
	for direction in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		var neighbor := map_data.get_cell(grid_position + direction)
		if neighbor and neighbor.cover_type == MapCellData.CoverType.FULL:
			return true
	return false

static func _is_generated_traversal_column(map_data: MapData, position: Vector3i) -> bool:
	var column := Vector2i(position.x, position.z)
	for traversal in map_data.generated_traversals:
		if Vector2i(traversal.from_cell.x, traversal.from_cell.z) == column or Vector2i(traversal.to_cell.x, traversal.to_cell.z) == column:
			return true
		for cell in traversal.path_cells:
			if Vector2i(cell.x, cell.z) == column:
				return true
	return false
