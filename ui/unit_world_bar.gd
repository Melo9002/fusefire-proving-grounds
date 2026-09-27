class_name UnitWorldBar
extends Control

@export_group("UI References")
@export var hp_bar: ProgressBar
@export var ap_label: Label
@export var carry_label: Label
@export var extract_button: Button

@export_group("3D Tracking Settings")
@export var world_offset: Vector3 = Vector3(0, 2.2, 0)

var _target_unit: Node3D
var _stats: UnitStats
var _active_camera: Camera3D
var _objective_manager: ObjectiveManager
var _turn_manager: TurnManager
var _battle_controller: BattleController

## Project the unit's world position into the UI layer each frame.
func setup(unit: Node3D, stats: UnitStats, faction: int = 0) -> void:
	_target_unit = unit
	_stats = stats
	_objective_manager = get_tree().get_first_node_in_group("objective_manager") as ObjectiveManager
	_turn_manager = get_tree().get_first_node_in_group("turn_manager") as TurnManager
	if _turn_manager:
		_battle_controller = _turn_manager.get_parent().get_node_or_null("BattleController") as BattleController
	if extract_button and not extract_button.button_down.is_connected(_on_extract_pressed):
		# A world-space bar may shift during edge scrolling before mouse release.
		# Commit on button-down so a valid extraction click cannot be lost.
		extract_button.button_down.connect(_on_extract_pressed)
	if _turn_manager and not _turn_manager.active_unit_changed.is_connected(_on_active_unit_changed):
		_turn_manager.active_unit_changed.connect(_on_active_unit_changed)
	if _objective_manager:
		_objective_manager.objective_completed.connect(_on_objective_changed)
		_objective_manager.objective_failed.connect(_on_objective_changed)

	_apply_faction_style(faction)

	if _stats:
		if not _stats.hp_changed.is_connected(_on_hp_changed):
			_stats.hp_changed.connect(_on_hp_changed)
		if not _stats.ap_changed.is_connected(_on_ap_changed):
			_stats.ap_changed.connect(_on_ap_changed)

		_on_hp_changed(_stats.current_hp, _stats.max_hp)
		_on_ap_changed(_stats.current_ap, _stats.max_ap)
	_refresh_extract_button()

func _process(_delta: float) -> void:
	if _battle_controller and _battle_controller.replay_mode:
		hide()
		return
	if not is_instance_valid(_target_unit):
		queue_free()
		return
	if not _target_unit.visible:
		hide()
		return

	if not is_instance_valid(_active_camera):
		_active_camera = get_viewport().get_camera_3d()
		if not _active_camera:
			return

	var target_world_pos = _target_unit.global_position + world_offset

	if _active_camera.is_position_behind(target_world_pos):
		hide()
	else:
		show()
		var screen_pos = _active_camera.unproject_position(target_world_pos)
		global_position = screen_pos - (size * 0.5)
	_refresh_extract_button()
	_refresh_carry_label()

func _apply_faction_style(faction_id: int) -> void:
	var team_color: Color
	match faction_id:
		0: # PLAYER
			team_color = Color("3498db") # Tactical Blue
		1: # ENEMY
			team_color = Color("e74c3c") # Enemy Red
		2: # ALLY
			team_color = Color("2ecc71") # Ally Green
		_:
			team_color = Color("f1c40f") # Neutral Yellow

	if hp_bar:
		var border_style = StyleBoxFlat.new()
		border_style.bg_color = Color(0, 0, 0, 0.6)
		border_style.border_color = team_color
		border_style.set_border_width_all(2)
		border_style.set_corner_radius_all(3)
		hp_bar.add_theme_stylebox_override("background", border_style)

func _on_hp_changed(current: int, max_val: int) -> void:
	if hp_bar:
		hp_bar.max_value = max_val
		hp_bar.value = current

func _on_ap_changed(current: int, max_val: int) -> void:
	if ap_label:
		ap_label.text = "%d/%d AP" % [current, max_val]

func _on_active_unit_changed(_unit: TacticalUnit) -> void:
	_refresh_extract_button()

func _on_objective_changed(_state: MissionObjectiveState) -> void:
	_refresh_extract_button()

func _on_extract_pressed() -> void:
	if _objective_manager and is_instance_valid(_target_unit) and _target_unit is TacticalUnit:
		_objective_manager.try_extract(_target_unit as TacticalUnit)
	_refresh_extract_button()

func _refresh_extract_button() -> void:
	if extract_button:
		extract_button.visible = false
		extract_button.disabled = true
		if not is_instance_valid(_target_unit) or not _target_unit is TacticalUnit:
			return
		var player_controlled := _turn_manager != null and _turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN and _turn_manager.player_units.has(_target_unit as TacticalUnit)
		var manually_controlled_enemy := _turn_manager != null and _battle_controller != null \
			and _turn_manager.current_phase == TurnManager.TurnPhase.ENEMY_TURN \
			and _turn_manager.active_unit == _target_unit and _battle_controller.debug_enemy_control
		extract_button.visible = _objective_manager != null \
			and (player_controlled or manually_controlled_enemy) \
			and _objective_manager.can_extract(_target_unit as TacticalUnit)
		extract_button.disabled = not extract_button.visible

func _refresh_carry_label() -> void:
	if carry_label:
		carry_label.visible = _target_unit is TacticalUnit and (_target_unit as TacticalUnit).is_carrying_unit()
