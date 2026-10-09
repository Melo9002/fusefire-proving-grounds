extends Control
class_name ActionHUDController

@export var battle_controller: BattleController

@export_group("Action Buttons")
@export var move_button: Button
@export var attack_button: Button
@export var end_unit_button: Button

var _tracked_stats: UnitStats

func _ready() -> void:
	if not battle_controller:
		push_error("ActionHUDController: Missing BattleController reference!")
		return
	if move_button:
		move_button.pressed.connect(_on_move_pressed)
	if attack_button:
		attack_button.pressed.connect(_on_attack_pressed)
	if end_unit_button:
		end_unit_button.pressed.connect(_on_end_unit_pressed)
	battle_controller.move_mode_toggled.connect(_on_move_mode_toggled)
	battle_controller.attack_mode_toggled.connect(_on_attack_mode_toggled)
	battle_controller.attack_preview_changed.connect(_on_attack_preview_changed)
	battle_controller.action_state_changed.connect(_on_action_state_changed)
	battle_controller.debug_enemy_control_changed.connect(_on_debug_enemy_control_changed)
	battle_controller.debug_player_ai_changed.connect(_on_debug_player_ai_changed)

	var turn_mgr = battle_controller.turn_manager
	if turn_mgr:
		turn_mgr.turn_phase_changed.connect(_on_turn_phase_changed)
		turn_mgr.active_unit_changed.connect(_on_active_unit_changed)
		if turn_mgr.active_unit:
			_on_active_unit_changed(turn_mgr.active_unit)

func _on_active_unit_changed(new_unit: TacticalUnit) -> void:
	# Stop observing the old unit before connecting the new selection.
	if is_instance_valid(_tracked_stats):
		if _tracked_stats.ap_changed.is_connected(_on_resource_changed):
			_tracked_stats.ap_changed.disconnect(_on_resource_changed)
	if is_instance_valid(new_unit) and new_unit.stats:
		_tracked_stats = new_unit.stats
		_tracked_stats.ap_changed.connect(_on_resource_changed)
	else:
		_tracked_stats = null

	_update_button_states()

func _on_resource_changed(_current: int, _max_val: int) -> void:
	_update_button_states()

func _on_move_pressed() -> void:
	battle_controller.toggle_move_mode()

func _on_attack_pressed() -> void:
	battle_controller.toggle_attack_mode()

func _on_end_unit_pressed() -> void:
	var active_unit = battle_controller.tactical_unit
	if not active_unit:
		return
	await battle_controller.try_end_unit_turn(active_unit, "Skipped manually by the player.")

func _on_action_state_changed(_is_busy: bool) -> void:
	_update_button_states()

func _on_move_mode_toggled(is_active: bool) -> void:
	if move_button:
		move_button.text = "Cancel Move" if is_active else "Move (1 AP)"

func _on_attack_mode_toggled(is_active: bool) -> void:
	if attack_button:
		attack_button.text = "Cancel Attack" if is_active else "Attack (1 AP)"

func _on_attack_preview_changed(text: String) -> void:
	if attack_button and battle_controller.is_attack_mode_active:
		attack_button.text = text if not text.is_empty() else "Cancel Attack"

func _on_turn_phase_changed(_new_phase: TurnManager.TurnPhase) -> void:
	visible = battle_controller.is_current_phase_manually_controlled()
	_update_button_states()

func _on_debug_enemy_control_changed(_enabled: bool) -> void:
	visible = battle_controller.is_current_phase_manually_controlled()
	_update_button_states()

func _on_debug_player_ai_changed(_enabled: bool) -> void:
	visible = battle_controller.is_current_phase_manually_controlled()
	_update_button_states()

func _update_button_states() -> void:
	var unit = battle_controller.tactical_unit if battle_controller else null
	var stats = unit.stats if (is_instance_valid(unit) and unit.stats) else null

	if not stats:
		_disable_all_buttons()
		return

	var has_ap = stats.current_ap >= 1 and not battle_controller.is_action_in_progress

	if move_button:
		move_button.disabled = not has_ap
	if attack_button:
		attack_button.disabled = not has_ap or unit.is_carrying_unit()
		attack_button.tooltip_text = "Cannot shoot while carrying a rescued unit" if unit.is_carrying_unit() else ""
	if end_unit_button:
		end_unit_button.disabled = not has_ap

func _disable_all_buttons() -> void:
	if move_button: move_button.disabled = true
	if attack_button: attack_button.disabled = true
	if end_unit_button: end_unit_button.disabled = true
