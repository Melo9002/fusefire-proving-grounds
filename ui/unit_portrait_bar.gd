class_name UnitPortraitBar
extends Control

@export var turn_manager: TurnManager
@export var battle_controller: BattleController
@export var portraits_container: HBoxContainer
@export var portrait_scene: PackedScene

var portraits: Array[UnitPortrait] = []

func _ready() -> void:
	battle_controller.units_registered.connect(_build_portraits)
	turn_manager.active_unit_changed.connect(_on_active_unit_changed)
	turn_manager.turn_phase_changed.connect(_on_turn_phase_changed)

func _build_portraits(player_units: Array[TacticalUnit]) -> void:
	for old_portrait in portraits:
		old_portrait.queue_free()
	portraits.clear()

	for unit in player_units:
		var portrait = portrait_scene.instantiate() as UnitPortrait
		portraits_container.add_child(portrait)
		portrait.setup(unit)
		portrait.unit_requested.connect(_on_unit_requested)
		portraits.append(portrait)

func _on_unit_requested(unit: TacticalUnit) -> void:
	turn_manager.select_player_unit(unit)

func _on_active_unit_changed(unit: TacticalUnit) -> void:
	for portrait in portraits:
		portrait.set_selected(portrait.represents(unit))

func _on_turn_phase_changed(phase: TurnManager.TurnPhase) -> void:
	visible = not battle_controller.replay_mode and phase != TurnManager.TurnPhase.TRANSITION
