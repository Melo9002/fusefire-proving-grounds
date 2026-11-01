class_name Refinery2Layout
extends RefCounted

## One authored environment. Scene transforms and explicit tactical volumes are
## the source of truth; no asset calibration, recipe search or random scattering.
const SCENE := preload("res://art/environments/authored/refinery_2.tscn")
const SOURCE_KIND := "authored_refinery_2"

static func generate(map_seed: int, cell_size: float = 1.0) -> MapData:
	var scene := SCENE.instantiate() as Node3D
	var dimensions: Vector2i = scene.get_meta("map_size")
	var data := FlatMapGenerator.generate(dimensions.x, dimensions.y, cell_size, map_seed)
	data.source_kind = SOURCE_KIND
	data.zones.clear()
	_compile(scene, Transform3D.IDENTITY, data, cell_size)
	scene.free()
	data.rebuild_los_index()
	return data

static func _compile(node: Node, parent_transform: Transform3D, data: MapData, unit: float) -> void:
	var transform := parent_transform
	if node is Node3D:
		transform *= node.transform
	if node.has_meta("solid_size"):
		_stamp_volume(data, transform, node.get_meta("solid_size"), node.get_meta("round_volume", false), unit)
	if node.has_meta("deck_rect"):
		var rect: Rect2i = node.get_meta("deck_rect")
		var level: int = node.get_meta("deck_level")
		data.elevation_labels[level] = "Maintenance walkway"
		for x in range(rect.position.x, rect.end.x):
			for z in range(rect.position.y, rect.end.y):
				var ground := data.get_cell(Vector3i(x, 0, z))
				data.add_cell(MapCellData.new(Vector3i(x, level, z), ground.world_position + Vector3.UP * level * unit))
				var slab := MapCellData.new(Vector3i(x, level - 1, z), ground.world_position + Vector3.UP * (level - 0.22) * unit)
				slab.walkable = false
				slab.can_stop = false
				slab.cover_height = 0.22 * unit
				slab.blocks_line_of_sight = true
				data.add_cell(slab)
	if node.has_meta("ladder_bottom"):
		data.add_traversal_link(TraversalLinkData.new(node.get_meta("ladder_bottom"), node.get_meta("ladder_top"), true))
	if node.has_meta("faction"):
		var origin: Vector3i = node.get_meta("grid_origin")
		for offset in 5:
			data.add_spawn_cell(int(node.get_meta("faction")) as TacticalUnit.Faction, origin + Vector3i(0, 0, offset))
	for child in node.get_children():
		_compile(child, transform, data, unit)

static func _stamp_volume(data: MapData, transform: Transform3D, dimensions: Vector3, round_volume: bool, unit: float) -> void:
	var bounds := transform * AABB(-dimensions * 0.5, dimensions)
	# Authored solids stand on ground. Overhead pipes deliberately have no volume.
	var lower := Vector2i(floori(bounds.position.x + data.map_size.x * 0.5), floori(bounds.position.z + data.map_size.y * 0.5))
	var upper := Vector2i(ceili(bounds.end.x + data.map_size.x * 0.5), ceili(bounds.end.z + data.map_size.y * 0.5))
	var inverse := transform.affine_inverse()
	for x in range(maxi(0, lower.x), mini(data.map_size.x, upper.x)):
		for z in range(maxi(0, lower.y), mini(data.map_size.y, upper.y)):
			var cell := data.get_cell(Vector3i(x, 0, z))
			var point := inverse * (cell.world_position / unit + Vector3.UP * transform.origin.y)
			if absf(point.x) >= dimensions.x * 0.5 + 0.5 or absf(point.z) >= dimensions.z * 0.5 + 0.5:
				continue
			if round_volume and pow(maxf(absf(point.x) - 0.5, 0.0) / (dimensions.x * 0.5), 2) + pow(maxf(absf(point.z) - 0.5, 0.0) / (dimensions.z * 0.5), 2) > 1.0:
				continue
			cell.can_stop = false
			cell.cover_height = maxf(cell.cover_height, bounds.end.y * unit)
			cell.cover_type = MapCellData.CoverType.FULL if cell.cover_height >= 1.2 * unit else MapCellData.CoverType.LOW
			cell.walkable = cell.cover_type == MapCellData.CoverType.LOW
			cell.blocks_line_of_sight = cell.cover_type == MapCellData.CoverType.FULL

static func present(parent: Node3D, unit: float) -> void:
	var scene := SCENE.instantiate() as Node3D
	scene.scale = Vector3.ONE * unit
	# Reuse camera occlusion for tall imported scenery, without changing gameplay.
	for child in scene.get_children():
		var volume := child.get_node_or_null("TacticalVolume") as Node3D
		if volume == null:
			continue
		child.set_script(preload("res://presentation/overlays/tactical_visual_occluder.gd"))
		var size: Vector3 = volume.get_meta("solid_size")
		child.set("occlusion_bounds", AABB(volume.position - size * 0.5, size))
	parent.add_child(scene)
