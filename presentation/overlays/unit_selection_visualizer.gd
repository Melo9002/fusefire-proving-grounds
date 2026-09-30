class_name UnitSelectionVisualizer
extends Node

@export var turn_manager: TurnManager
@export var battle_controller: BattleController
@export var outline_color: Color = Color(0.35, 0.9, 1.0, 0.9)
@export_range(0.0, 0.2, 0.005) var outline_width: float = 0.035

var selected_unit: TacticalUnit
var _outline_material: StandardMaterial3D

func _ready() -> void:
	_outline_material = StandardMaterial3D.new()
	_outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_outline_material.albedo_color = outline_color
	_outline_material.cull_mode = BaseMaterial3D.CULL_FRONT
	_outline_material.grow = true
	_outline_material.grow_amount = outline_width
	turn_manager.active_unit_changed.connect(_on_active_unit_changed)
	battle_controller.debug_enemy_control_changed.connect(_on_debug_enemy_control_changed)
	battle_controller.debug_player_ai_changed.connect(_on_debug_player_ai_changed)

func _on_active_unit_changed(unit: TacticalUnit) -> void:
	_set_outline(selected_unit, false)
	selected_unit = null
	if battle_controller.is_current_phase_manually_controlled() and is_instance_valid(unit):
		selected_unit = unit
		_set_outline(selected_unit, true)

func _set_outline(unit, enabled: bool) -> void:
	if not is_instance_valid(unit):
		return
	for child in unit.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance = child as MeshInstance3D
		mesh_instance.material_overlay = _outline_material if enabled else null

func _on_debug_enemy_control_changed(_enabled: bool) -> void:
	_on_active_unit_changed(turn_manager.active_unit)

func _on_debug_player_ai_changed(_enabled: bool) -> void:
	_on_active_unit_changed(turn_manager.active_unit)
