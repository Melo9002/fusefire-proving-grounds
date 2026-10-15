class_name IndustrialWarehouseLayoutBuilder
extends RefCounted

const SOURCE_KIND := "generated_industrial_warehouse"
const WALL_HEIGHT := 5.0
const ROOF_FOOTPRINT := Rect2i(11, 5, 18, 13)
const ROOF_LEVEL := 5
const ROOF_LADDER_BOTTOM := Vector3i(29, 0, 10)
const ROOF_LADDER_TOP := Vector3i(28, ROOF_LEVEL, 10)
const LOW_COVER_HEIGHT := 0.75
const PLATFORM_FOOTPRINT := Rect2i(24, 7, 3, 8)
const PLATFORM_LEVEL := 2
const CONTAINER_HEIGHT := 1.87

# The open south doors face a loading yard; the west service entrance gives
# attackers a second route through the warehouse instead of one choke point.
const WALL_CELLS: Array[Vector2i] = [
	Vector2i(11, 5), Vector2i(12, 5), Vector2i(13, 5), Vector2i(14, 5), Vector2i(15, 5), Vector2i(16, 5), Vector2i(17, 5),
	Vector2i(21, 5), Vector2i(22, 5), Vector2i(23, 5), Vector2i(24, 5), Vector2i(25, 5), Vector2i(26, 5), Vector2i(27, 5), Vector2i(28, 5),
	Vector2i(11, 6), Vector2i(11, 7), Vector2i(11, 8), Vector2i(11, 9), Vector2i(11, 10), Vector2i(11, 13), Vector2i(11, 14), Vector2i(11, 15), Vector2i(11, 16), Vector2i(11, 17),
	Vector2i(28, 6), Vector2i(28, 7), Vector2i(28, 8), Vector2i(28, 9), Vector2i(28, 10), Vector2i(28, 11), Vector2i(28, 14), Vector2i(28, 15), Vector2i(28, 16), Vector2i(28, 17),
	Vector2i(12, 17), Vector2i(13, 17), Vector2i(14, 17), Vector2i(15, 17), Vector2i(16, 17),
	Vector2i(21, 17), Vector2i(22, 17), Vector2i(23, 17), Vector2i(24, 17), Vector2i(25, 17), Vector2i(26, 17), Vector2i(27, 17),
]

const CONTAINER_SPECS: Array[Rect2i] = [
	Rect2i(12, 21, 5, 2),
	Rect2i(18, 25, 5, 2),
	Rect2i(27, 21, 5, 2),
]

const CONVEYOR_SPECS: Array[Rect2i] = [
	Rect2i(16, 11, 2, 1),
	Rect2i(19, 11, 2, 1),
]

const CRANE_FOOTPRINT := Rect2i(21, 19, 3, 4)

const MACHINE_CELLS: Array[Vector2i] = [
	Vector2i(15, 9), Vector2i(16, 9), Vector2i(15, 13),
	Vector2i(20, 9), Vector2i(20, 13), Vector2i(23, 11),
]

const YARD_COVER: Array[Vector2i] = [
	Vector2i(9, 21), Vector2i(9, 22), Vector2i(10, 22),
	Vector2i(32, 19), Vector2i(32, 20), Vector2i(31, 19),
	Vector2i(17, 26), Vector2i(23, 27),
]

static func apply(data: MapData, cell_size: float) -> void:
	data.source_kind = SOURCE_KIND
	data.elevation_labels[PLATFORM_LEVEL] = "Walkway"
	data.elevation_labels[ROOF_LEVEL] = "Roof"
	for position in WALL_CELLS:
		_set_full_cover(data, position, WALL_HEIGHT * cell_size)
	for footprint in CONTAINER_SPECS:
		data.containers.append(footprint)
		for x in range(footprint.position.x, footprint.end.x):
			for z in range(footprint.position.y, footprint.end.y):
				_set_full_cover(data, Vector2i(x, z), CONTAINER_HEIGHT * cell_size)
	for position in MACHINE_CELLS:
		_set_full_cover(data, position, 1.5 * cell_size)
	for footprint in CONVEYOR_SPECS:
		_set_footprint_full_cover(data, footprint, 0.65 * cell_size)
	_set_footprint_full_cover(data, CRANE_FOOTPRINT, 3.7 * cell_size)
	for position in YARD_COVER:
		_set_low_cover(data, position, LOW_COVER_HEIGHT * cell_size)
	_add_platform(data, cell_size)
	_add_roof(data, cell_size)

static func _add_roof(data: MapData, cell_size: float) -> void:
	for x in range(ROOF_FOOTPRINT.position.x, ROOF_FOOTPRINT.end.x):
		for z in range(ROOF_FOOTPRINT.position.y, ROOF_FOOTPRINT.end.y):
			var ground := data.get_cell(Vector3i(x, 0, z))
			data.add_cell(MapCellData.new(Vector3i(x, ROOF_LEVEL, z), ground.world_position + Vector3.UP * ROOF_LEVEL * cell_size))
			# A thin non-walkable ceiling slab blocks shots through the roof without
			# filling the occupied room below. Its separate level is never a destination.
			var slab := MapCellData.new(Vector3i(x, ROOF_LEVEL - 1, z), ground.world_position + Vector3.UP * (ROOF_LEVEL - 0.25) * cell_size)
			slab.walkable = false
			slab.can_stop = false
			slab.cover_height = 0.25 * cell_size
			slab.blocks_line_of_sight = true
			data.add_cell(slab)
	data.add_traversal_link(TraversalLinkData.new(ROOF_LADDER_BOTTOM, ROOF_LADDER_TOP, true))
	data.generated_traversals.append(GeneratedTraversalData.new(GeneratedTraversalData.Kind.LADDER, ROOF_LADDER_BOTTOM, ROOF_LADDER_TOP))

static func _set_footprint_full_cover(data: MapData, footprint: Rect2i, height: float) -> void:
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			_set_full_cover(data, Vector2i(x, z), height)

static func _set_full_cover(data: MapData, position: Vector2i, height: float) -> void:
	var cell := data.get_cell(Vector3i(position.x, 0, position.y))
	if not cell:
		return
	cell.cover_type = MapCellData.CoverType.FULL
	cell.cover_height = height
	cell.blocks_line_of_sight = true
	cell.walkable = false
	cell.can_stop = false

static func _set_low_cover(data: MapData, position: Vector2i, height: float) -> void:
	var cell := data.get_cell(Vector3i(position.x, 0, position.y))
	if not cell:
		return
	cell.cover_type = MapCellData.CoverType.LOW
	cell.cover_height = height
	cell.walkable = true
	cell.can_stop = false

static func _add_platform(data: MapData, cell_size: float) -> void:
	var platform := GeneratedPlatformData.new(PLATFORM_FOOTPRINT, PLATFORM_LEVEL)
	for x in range(PLATFORM_FOOTPRINT.position.x, PLATFORM_FOOTPRINT.end.x):
		for z in range(PLATFORM_FOOTPRINT.position.y, PLATFORM_FOOTPRINT.end.y):
			var ground := data.get_cell(Vector3i(x, 0, z))
			var position := Vector3i(x, PLATFORM_LEVEL, z)
			data.add_cell(MapCellData.new(position, ground.world_position + Vector3.UP * PLATFORM_LEVEL * cell_size))
			platform.cells.append(position)
	for corner in [PLATFORM_FOOTPRINT.position, Vector2i(PLATFORM_FOOTPRINT.end.x - 1, PLATFORM_FOOTPRINT.position.y), Vector2i(PLATFORM_FOOTPRINT.position.x, PLATFORM_FOOTPRINT.end.y - 1), PLATFORM_FOOTPRINT.end - Vector2i.ONE]:
		_set_full_cover(data, corner, float(PLATFORM_LEVEL) * cell_size)
	data.platforms.append(platform)

