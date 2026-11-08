extends Node3D
class_name PathVisualizer

@export var grid_manager: GridManager
@export var tile_layers: GroundTileLayers
@export_range(0.0, 0.3, 0.01) var tile_padding: float = 0.08
@export var range_color := Color(0.55, 0.32, 0.0, 0.65)
@export var path_color := Color(0, 0.5, 1, 0.5)

func draw_range_zone(grid_positions: Array[Vector3i], color: Color = range_color) -> void:
	tile_layers.show_cells(GroundTileLayers.Layer.RANGE, grid_positions, tile_padding, color)

func draw_path(path_vectors: PackedVector3Array, color: Color = path_color) -> void:
	var centers := {}
	for center in path_vectors:
		var cell := grid_manager.world_to_grid(center)
		centers[cell] = center
	tile_layers.show_tiles(GroundTileLayers.Layer.PATH, centers, tile_padding, color)

func clear_range_zone() -> void:
	tile_layers.clear_layer(GroundTileLayers.Layer.RANGE)

func clear_path() -> void:
	tile_layers.clear_layer(GroundTileLayers.Layer.PATH)
