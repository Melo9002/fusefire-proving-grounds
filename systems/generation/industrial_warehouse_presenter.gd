class_name IndustrialWarehousePresenter
extends RefCounted

const Layout = preload("res://systems/generation/industrial_warehouse_layout_builder.gd")
const AssetPlacement = preload("res://presentation/environment_asset_placement.gd")
const INDUSTRIAL_ROOT := "res://art/environments/kenney/city_kit_industrial/models/"
const FACTORY_ROOT := "res://art/environments/kenney/factory_kit/models/"
const STEEL := Color("344952")
const SAFETY := Color("d6a94b")

static func build(data: MapData, parent: Node3D, cell_size: float) -> void:
	var site := Node3D.new()
	site.name = "IndustrialWarehouseAssets"
	parent.add_child(site)
	_surface(data, site, Rect2i(0, 0, 40, 30), Color("333e43"), cell_size)
	_surface(data, site, Rect2i(7, 3, 27, 25), Color("636e70"), cell_size, 0.004)
	_surface(data, site, Rect2i(11, 5, 18, 13), Color("949c96"), cell_size, 0.006)
	_surface(data, site, Rect2i(12, 6, 12, 11), Color("7c8985"), cell_size, 0.007)
	_surface(data, site, Rect2i(11, 18, 18, 2), Color("a09c85"), cell_size, 0.006)
	for z in range(1, 29, 3):
		for x in [3, 36]:
			_box(site, _world(data, Vector2(x, z)) + Vector3.UP * 0.008, Vector3(0.1, 0.001, 1.5) * cell_size, SAFETY)
	for x in range(12, 29):
		_box(site, _world(data, Vector2(x, 18)) + Vector3.UP * 0.008, Vector3(0.6, 0.001, 0.12) * cell_size, SAFETY)
	_outline(data, site, Layout.CRANE_FOOTPRINT, cell_size)
	for footprint in Layout.CONTAINER_SPECS:
		_outline(data, site, footprint, cell_size)
	for position in Layout.WALL_CELLS:
		_hide_tactical_block(parent, position)
		var wall := TacticalVisualOccluder.new()
		wall.name = "Wall_%d_%d" % [position.x, position.y]
		site.add_child(wall)
		var side := position.x == 11 or position.x == 28
		var center := _world(data, Vector2(position))
		var size := Vector3(0.86, Layout.WALL_HEIGHT, 1.0) if side else Vector3(1.0, Layout.WALL_HEIGHT, 0.86)
		_box(wall, center + Vector3.UP * Layout.WALL_HEIGHT * 0.5 * cell_size, size * cell_size, Color("8a9996"))
		size.y = 0.55
		_box(wall, center + Vector3.UP * 0.275 * cell_size, (size + Vector3(0.015, 0, 0.015)) * cell_size, STEEL)
		size.y = 0.12
		_box(wall, center + Vector3.UP * (Layout.WALL_HEIGHT - 0.03) * cell_size, (size + Vector3(0.035, 0, 0.035)) * cell_size, STEEL)
		if (position.x + position.y) % 3 == 0:
			_box(wall, center + Vector3.UP * Layout.WALL_HEIGHT * 0.5 * cell_size, Vector3(0.91 if side else 0.12, Layout.WALL_HEIGHT, 0.12 if side else 0.91) * cell_size, STEEL)
		wall.occlusion_bounds = AssetPlacement.mesh_bounds(wall)
	# Headers are overhead presentation; the ground openings remain unobstructed.
	_box(site, _world(data, Vector2(18.5, 17)) + Vector3.UP * 2.95 * cell_size, Vector3(4, 0.3, 0.86) * cell_size, SAFETY)
	_box(site, _world(data, Vector2(19, 5)) + Vector3.UP * 2.95 * cell_size, Vector3(3, 0.3, 0.86) * cell_size, STEEL)
	_box(site, _world(data, Vector2(11, 11.5)) + Vector3.UP * 2.95 * cell_size, Vector3(0.86, 0.3, 2) * cell_size, STEEL)
	_box(site, _world(data, Vector2(28, 12.5)) + Vector3.UP * 2.95 * cell_size, Vector3(0.86, 0.3, 2) * cell_size, STEEL)
	var sign := Label3D.new()
	sign.text = "DISPATCH / 01"
	sign.font_size = 48
	sign.pixel_size = 0.004 * cell_size
	sign.outline_size = 0
	sign.modulate = STEEL
	sign.position = _world(data, Vector2(18.5, 17.44)) + Vector3.UP * 2.95 * cell_size
	site.add_child(sign)
	for index in Layout.CONTAINER_SPECS.size():
		var footprint: Rect2i = Layout.CONTAINER_SPECS[index]
		var container := parent.get_node_or_null("Container_%d_%d" % [footprint.position.x, footprint.position.y]) as Node3D
		if container:
			container.visible = false
		_hide_footprint_blocks(parent, footprint)
		AssetPlacement.instantiate_fitted(site, INDUSTRIAL_ROOT + "shipping-container-%s.glb" % ["a", "b", "c"][index], _center(data, footprint), Vector3(4.8, Layout.CONTAINER_HEIGHT, 1.98) * cell_size, PI * 0.5)
	for position in Layout.MACHINE_CELLS:
		_hide_tactical_block(parent, position)
		var center := _world(data, Vector2(position))
		_box(site, center + Vector3.UP * 0.3 * cell_size, Vector3(0.94, 0.6, 0.94) * cell_size, STEEL)
		AssetPlacement.instantiate_fitted(site, FACTORY_ROOT + "machine.glb", center + Vector3.UP * 0.6 * cell_size, Vector3(0.94, 0.9, 0.94) * cell_size)
	for footprint in Layout.CONVEYOR_SPECS:
		_hide_footprint_blocks(parent, footprint)
		var center := _center(data, footprint)
		_box(site, center + Vector3.UP * 0.125 * cell_size, Vector3(1.95, 0.25, 0.9) * cell_size, STEEL)
		AssetPlacement.instantiate_fitted(site, FACTORY_ROOT + "conveyor-long.glb", center + Vector3.UP * 0.25 * cell_size, Vector3(2, 0.4, 1) * cell_size)
	_hide_footprint_blocks(parent, Layout.CRANE_FOOTPRINT)
	AssetPlacement.instantiate_fitted(site, FACTORY_ROOT + "crane.glb", _center(data, Layout.CRANE_FOOTPRINT), Vector3(2.9, 3.7, 3.9) * cell_size)
	for position in Layout.YARD_COVER:
		_hide_tactical_block(parent, position)
		var center := _world(data, Vector2(position))
		_box(site, center + Vector3.UP * 0.375 * cell_size, Vector3(0.94, 0.75, 0.94) * cell_size, Color("9b9d8d"))
		_box(site, center + Vector3.UP * 0.66 * cell_size, Vector3(0.95, 0.1, 0.95) * cell_size, SAFETY)
	# Keep the existing deck, rails and access gaps; do not put catwalk meshes on its walkable surface.
	var rect: Rect2i = Layout.PLATFORM_FOOTPRINT
	for position in [rect.position, Vector2i(rect.end.x - 1, rect.position.y), Vector2i(rect.position.x, rect.end.y - 1), rect.end - Vector2i.ONE]:
		_hide_tactical_block(parent, position)
		_box(site, _world(data, Vector2(position)) + Vector3.UP * cell_size, Vector3(0.9, 2, 0.9) * cell_size, STEEL)

	_build_roof(data, site, cell_size)

static func _build_roof(data: MapData, site: Node3D, cell_size: float) -> void:
	var roof := WarehouseRoofCutaway.new()
	roof.name = "WarehouseRoof"
	roof.position = _center(data, Layout.ROOF_FOOTPRINT)
	roof.interior_bounds = AABB(Vector3(-9, -0.1, -6.5) * cell_size, Vector3(18, 5.0, 13) * cell_size)
	roof.roof_bounds = AABB(Vector3(-9, 4.75, -6.5) * cell_size, Vector3(18, 0.3, 13) * cell_size)
	roof.surface_height = Layout.ROOF_LEVEL * cell_size
	site.add_child(roof)
	# A flat service roof matches the authoritative walkable plane exactly.
	var dimensions := Vector3(18, 0.25, 13) * cell_size
	var center := Vector3(0, 4.875, 0) * cell_size
	_box(roof, center, dimensions, STEEL)
	GeneratedTerrainPresenter._add_roof_collider(roof, dimensions, center)
	for z in range(-6, 7):
		_box(roof, Vector3(0, 5.004, z) * cell_size, Vector3(18, 0.006, 0.045) * cell_size, Color("63767a"))
static func _outline(data: MapData, site: Node3D, footprint: Rect2i, cell_size: float) -> void:
	var center := _center(data, footprint) + Vector3.UP * 0.008
	for side in [-1, 1]:
		_box(site, center + Vector3(side * footprint.size.x * 0.5, 0, 0) * cell_size, Vector3(0.06, 0.001, footprint.size.y) * cell_size, SAFETY)
		_box(site, center + Vector3(0, 0, side * footprint.size.y * 0.5) * cell_size, Vector3(footprint.size.x, 0.001, 0.06) * cell_size, SAFETY)

static func _world(data: MapData, position: Vector2) -> Vector3:
	var origin := data.get_cell(Vector3i.ZERO).world_position
	var step := data.get_cell(Vector3i.RIGHT).world_position.x - origin.x
	return origin + Vector3(position.x, 0, position.y) * step

static func _center(data: MapData, footprint: Rect2i) -> Vector3:
	return _world(data, Vector2(footprint.position) + Vector2(footprint.size - Vector2i.ONE) * 0.5)

static func _surface(data: MapData, parent: Node3D, footprint: Rect2i, color: Color, cell_size: float, height := 0.002) -> void:
	_box(parent, _center(data, footprint) + Vector3.UP * height, Vector3(footprint.size.x * cell_size, 0.001, footprint.size.y * cell_size), color)

static func _box(parent: Node3D, center: Vector3, size: Vector3, color: Color) -> void:
	var instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material = material
	instance.mesh = mesh
	instance.position = center
	parent.add_child(instance)

static func _hide_tactical_block(parent: Node3D, position: Vector2i) -> void:
	var block := parent.get_node_or_null("Cover_%d_0_%d" % [position.x, position.y]) as Node3D
	if block:
		block.visible = false

static func _hide_footprint_blocks(parent: Node3D, footprint: Rect2i) -> void:
	for x in range(footprint.position.x, footprint.end.x):
		for z in range(footprint.position.y, footprint.end.y):
			_hide_tactical_block(parent, Vector2i(x, z))





