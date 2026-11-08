class_name GroundTileLayers
extends Node3D
## Composites ground fills by full tactical cell, including elevation.
## The shader projects each surviving tile onto the visible surface.

enum Layer { OBJECTIVE, GUARD_ACTIVE, RANGE, GUARD_PREVIEW, CURSOR, PATH }

const TileShader := preload("res://presentation/overlays/ground_tile_overlay.gdshader")

@export var grid_manager: GridManager

var _layers: Dictionary = {}
var _box_faces := BoxMesh.new().get_faces()

func show_cells(layer: Layer, cells: Array[Vector3i], padding: float, color: Color) -> void:
	var centers := {}
	for cell in cells:
		var data := grid_manager.get_cell_data(cell)
		centers[cell] = data.world_position if data else grid_manager.grid_to_world(cell)
	show_tiles(layer, centers, padding, color)

func show_tiles(layer: Layer, centers: Dictionary, padding: float, color: Color) -> void:
	if centers.is_empty():
		clear_layer(layer)
		return
	if not _layers.has(layer):
		var instance := MeshInstance3D.new()
		instance.name = Layer.keys()[layer]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = TileShader
		instance.material_override = material
		add_child(instance)
		_layers[layer] = {"instance": instance, "centers": {}, "rendered": {}, "half_size": Vector3.ZERO, "padding": 0.0}
	var state: Dictionary = _layers[layer]
	state.instance.material_override.set_shader_parameter(&"tint", color)
	var half_size := _half_size(padding)
	if state.centers == centers and state.half_size == half_size:
		return
	state.centers = centers
	state.padding = padding
	_refresh()

func clear_layer(layer: Layer) -> void:
	if _layers.has(layer) and not _layers[layer].centers.is_empty():
		_layers[layer].centers = {}
		_refresh()

func mesh_instance(layer: Layer) -> MeshInstance3D:
	return _layers[layer].instance if _layers.has(layer) else null

func _refresh() -> void:
	var claimed := {}
	for layer in range(Layer.PATH, Layer.OBJECTIVE - 1, -1):
		if not _layers.has(layer):
			continue
		var state: Dictionary = _layers[layer]
		var visible_tiles := {}
		for cell in state.centers:
			if not claimed.has(cell):
				visible_tiles[cell] = state.centers[cell]
				claimed[cell] = true
		var half_size := _half_size(state.padding)
		if state.rendered == visible_tiles and state.half_size == half_size:
			continue
		state.rendered = visible_tiles
		state.half_size = half_size
		state.instance.material_override.set_shader_parameter(&"tile_half_size", half_size)
		state.instance.mesh = _build_mesh(visible_tiles, half_size)

func _half_size(padding: float) -> Vector3:
	var half_width := grid_manager.cell_size * (1.0 - padding) * 0.5
	return Vector3(half_width, grid_manager.elevation_step * 0.49, half_width)

func _build_mesh(tiles: Dictionary, half_size: Vector3) -> ArrayMesh:
	if tiles.is_empty():
		return null
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for center: Vector3 in tiles.values():
		surface.set_uv(Vector2(center.x, center.z))
		surface.set_uv2(Vector2(center.y, 0.0))
		for vertex in _box_faces:
			surface.add_vertex(to_local(center + vertex * half_size * 2.0))
	return surface.commit()
