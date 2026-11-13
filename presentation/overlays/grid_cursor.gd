extends Node3D
class_name GridCursor

@export var grid_manager: GridManager
@export var tile_layers: GroundTileLayers
@export var highlight_color := Color(1.0, 0.0, 0.0, 0.4)

var _hovered_cell: Array[Vector3i] = []

func _ready() -> void:
	visibility_changed.connect(_refresh)

func update_hover_position(raw_position: Vector3) -> void:
	var cell := grid_manager.world_to_grid(raw_position)
	if not _hovered_cell.is_empty() and cell == _hovered_cell[0]:
		return
	_hovered_cell.assign([cell])
	_refresh()

func clear_hover() -> void:
	if not _hovered_cell.is_empty():
		_hovered_cell.clear()
		_refresh()

func _refresh() -> void:
	if not is_instance_valid(tile_layers):
		return
	if is_visible_in_tree():
		tile_layers.show_cells(GroundTileLayers.Layer.CURSOR, _hovered_cell, 0.0, highlight_color)
	else:
		tile_layers.clear_layer(GroundTileLayers.Layer.CURSOR)
