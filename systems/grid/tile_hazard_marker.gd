@tool
class_name TileHazardMarker
extends Node3D

## Authored placement adapter. Runtime authority is copied into MapCellData.
@export var condition: ConditionDefinition = preload("res://units/conditions/jammed.tres")

func _ready() -> void:
	add_to_group("tile_hazards")
