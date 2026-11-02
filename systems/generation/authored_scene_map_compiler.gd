class_name AuthoredSceneMapCompiler
extends RefCounted
## Compiles explicit tactical metadata from an authored Godot scene into
## MapData. Imported visual geometry never becomes tactical authority.

static func compile(root: Node, data: MapData, cell_size: float, root_transform := Transform3D.IDENTITY) -> void:
	_compile_node(root, root_transform, data, cell_size)
	data.rebuild_los_index()

static func _compile_node(node: Node, parent_transform: Transform3D, data: MapData, unit: float) -> void:
	var transform := parent_transform
	if node is Node3D: transform *= node.transform
	if node.has_meta("solid_size"):
		_stamp_volume(data, transform, node.get_meta("solid_size"), node.get_meta("round_volume", false), unit)
	if node.has_meta("deck_rect"):
		var rect: Rect2i = node.get_meta("deck_rect")
		var level: int = node.get_meta("deck_level")
		data.elevation_labels[level] = "Maintenance walkway"
		for x in range(rect.position.x, rect.end.x):
			for z in range(rect.position.y, rect.end.y):
				var ground := data.get_cell(Vector3i(x, 0, z))
				if ground == null: continue
				data.add_cell(MapCellData.new(Vector3i(x, level, z), ground.world_position + Vector3.UP * level * unit))
				var slab := MapCellData.new(Vector3i(x, level - 1, z), ground.world_position + Vector3.UP * (level - 0.22) * unit)
				slab.walkable = false; slab.can_stop = false; slab.cover_height = 0.22 * unit; slab.blocks_line_of_sight = true
				data.add_cell(slab)
	if node.has_meta("ladder_bottom"):
		data.add_traversal_link(TraversalLinkData.new(node.get_meta("ladder_bottom"), node.get_meta("ladder_top"), true))
	if node.has_meta("faction"):
		var origin: Vector3i = node.get_meta("grid_origin")
		for offset in 5: data.add_spawn_cell(int(node.get_meta("faction")) as TacticalUnit.Faction, origin + Vector3i(0, 0, offset))
	for child in node.get_children(): _compile_node(child, transform, data, unit)

static func _stamp_volume(data: MapData, transform: Transform3D, dimensions: Vector3, round_volume: bool, unit: float) -> void:
	var bounds := transform * AABB(-dimensions * 0.5, dimensions)
	var lower := Vector2i(floori(bounds.position.x + data.map_size.x * 0.5), floori(bounds.position.z + data.map_size.y * 0.5))
	var upper := Vector2i(ceili(bounds.end.x + data.map_size.x * 0.5), ceili(bounds.end.z + data.map_size.y * 0.5))
	var inverse := transform.affine_inverse()
	for x in range(maxi(0, lower.x), mini(data.map_size.x, upper.x)):
		for z in range(maxi(0, lower.y), mini(data.map_size.y, upper.y)):
			var cell := data.get_cell(Vector3i(x, 0, z))
			var point := inverse * (cell.world_position / unit + Vector3.UP * transform.origin.y)
			if absf(point.x) >= dimensions.x * 0.5 + 0.5 or absf(point.z) >= dimensions.z * 0.5 + 0.5: continue
			if round_volume and pow(maxf(absf(point.x) - 0.5, 0.0) / (dimensions.x * 0.5), 2) + pow(maxf(absf(point.z) - 0.5, 0.0) / (dimensions.z * 0.5), 2) > 1.0: continue
			cell.can_stop = false
			cell.cover_height = maxf(cell.cover_height, bounds.end.y * unit)
			cell.cover_type = MapCellData.CoverType.FULL if cell.cover_height >= 1.2 * unit else MapCellData.CoverType.LOW
			cell.walkable = cell.cover_type == MapCellData.CoverType.LOW
			cell.blocks_line_of_sight = cell.cover_type == MapCellData.CoverType.FULL
