extends Node3D
class_name OverwatchRangeVisualizer

## Read-only presentation of the same range and line-of-sight cells used by the
## Attack preview. TacticalActionService still revalidates every real trigger.

@export var tile_layers: GroundTileLayers
@export var preview_color := Color(0.58, 0.24, 0.88, 0.28)
@export var committed_guard_color := Color(0.24, 0.08, 0.38, 0.42)
@export var enemy_guard_color := Color(0.86, 0.23, 0.13, 0.38)
@export_range(0.0, 0.3, 0.01) var tile_padding := 0.12

var displayed_cells: Array[Vector3i] = []
var preview_cells: Array[Vector3i] = []
var committed_cells: Array[Vector3i] = []
var enemy_cells: Array[Vector3i] = []

func show_cells(cells: Array[Vector3i]) -> void:
	show_ranges(cells, [])

func show_ranges(pending_cells: Array[Vector3i], active_cells: Array[Vector3i], hostile_cells: Array[Vector3i] = []) -> void:
	preview_cells.assign(pending_cells)
	committed_cells.assign(active_cells)
	enemy_cells.assign(hostile_cells)
	var combined := {}
	for cells in [preview_cells, committed_cells, enemy_cells]:
		for cell in cells:
			combined[cell] = true
	displayed_cells.assign(combined.keys())
	_sort_cells(preview_cells)
	_sort_cells(committed_cells)
	_sort_cells(enemy_cells)
	_sort_cells(displayed_cells)
	tile_layers.show_cells(GroundTileLayers.Layer.GUARD_PREVIEW, preview_cells, tile_padding, preview_color)
	tile_layers.show_cells(GroundTileLayers.Layer.GUARD_ACTIVE, committed_cells, tile_padding, committed_guard_color)
	tile_layers.show_cells(GroundTileLayers.Layer.ENEMY_GUARD, enemy_cells, tile_padding, enemy_guard_color)

func _sort_cells(cells: Array[Vector3i]) -> void:
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.x < b.x or (a.x == b.x and (a.z < b.z or (a.z == b.z and a.y < b.y))))

func clear() -> void:
	displayed_cells.clear()
	preview_cells.clear()
	committed_cells.clear()
	enemy_cells.clear()
	tile_layers.clear_layer(GroundTileLayers.Layer.GUARD_PREVIEW)
	tile_layers.clear_layer(GroundTileLayers.Layer.GUARD_ACTIVE)
	tile_layers.clear_layer(GroundTileLayers.Layer.ENEMY_GUARD)
