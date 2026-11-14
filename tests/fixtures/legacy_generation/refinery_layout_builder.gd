class_name RefineryLayoutBuilder
extends RefCounted

const PLATFORM_SPECS := [
	[Rect2i(9, 4, 4, 3), 3],
	[Rect2i(9, 11, 4, 3), 3],
	[Rect2i(20, 6, 3, 4), 2],
	[Rect2i(20, 15, 3, 4), 2],
	# Tower caps share the vessel footprint and form the refinery's high ground.
	[Rect2i(15, 4, 3, 3), 6],
	[Rect2i(25, 17, 3, 3), 5],
]

const EQUIPMENT := [
	[Rect2i(15, 4, 3, 3), 6.0, "LEACH 01"],
	[Rect2i(25, 17, 3, 3), 5.0, "LEACH 02"],
	[Rect2i(23, 6, 3, 3), 4.5, "SEPARATION"],
	[Rect2i(23, 15, 3, 3), 4.5, "PRECIPITATION"],
	[Rect2i(14, 21, 3, 3), 2.5, "REAGENT A"],
	[Rect2i(19, 21, 3, 3), 2.5, "REAGENT B"],
]

static func apply(data: MapData, cell_size: float) -> void:
	for spec in EQUIPMENT:
		var footprint: Rect2i = spec[0]
		for x in range(footprint.position.x, footprint.end.x):
			for z in range(footprint.position.y, footprint.end.y):
				var cell := data.get_cell(Vector3i(x, 0, z))
				cell.walkable = false
				cell.can_stop = false
				cell.blocks_line_of_sight = true
				cell.cover_height = float(spec[1]) * cell_size
	for spec in PLATFORM_SPECS:
		_add_platform(data, spec[0], spec[1], cell_size)
	_add_bridge(data, Vector3i(11, 3, 6), Vector3i(11, 3, 11), cell_size)
	_add_bridge(data, Vector3i(21, 2, 9), Vector3i(21, 2, 15), cell_size)

static func _add_platform(data: MapData, footprint: Rect2i, level: int, cell_size: float) -> void:
	var platform := GeneratedPlatformData.new(footprint, level)
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			var ground := data.get_cell(Vector3i(x, 0, z))
			var position := Vector3i(x, level, z)
			data.add_cell(MapCellData.new(position, ground.world_position + Vector3.UP * level * cell_size))
			platform.cells.append(position)
	for corner in [footprint.position, Vector2i(footprint.end.x - 1, footprint.position.y), Vector2i(footprint.position.x, footprint.end.y - 1), footprint.end - Vector2i.ONE]:
		var base := data.get_cell(Vector3i(corner.x, 0, corner.y))
		base.walkable = false
		base.can_stop = false
	data.platforms.append(platform)

static func _add_bridge(data: MapData, start: Vector3i, finish: Vector3i, cell_size: float) -> void:
	var direction := Vector3i(signi(finish.x - start.x), 0, signi(finish.z - start.z))
	var path: Array[Vector3i] = [start]
	var cursor := start + direction
	while cursor != finish:
		var ground := data.get_cell(Vector3i(cursor.x, 0, cursor.z))
		data.add_cell(MapCellData.new(cursor, ground.world_position + Vector3.UP * cursor.y * cell_size))
		path.append(cursor)
		cursor += direction
	path.append(finish)
	data.generated_traversals.append(GeneratedTraversalData.new(GeneratedTraversalData.Kind.BRIDGE, start, finish, path))
