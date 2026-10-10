extends Control
class_name ActionHUDController

@export var battle_controller: BattleController

@export_group("Action Buttons")
@export var move_button: Button
@export var attack_button: Button
@export var reload_button: Button
@export var aim_button: Button
@export var end_unit_button: Button
@export var supply_points_label: Label
@export var tactical_state_label: Label

var _tracked_stats: UnitStats
var _tracked_tactical_state: TacticalState

func _ready() -> void:
	if not battle_controller:
		push_error("ActionHUDController: Missing BattleController reference!")
		return
	if move_button:
		move_button.pressed.connect(_on_move_pressed)
	if attack_button:
		attack_button.pressed.connect(_on_attack_pressed)
	if reload_button:
		reload_button.pressed.connect(_on_reload_pressed)
	if aim_button:
		aim_button.pressed.connect(_on_aim_pressed)
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
		if _tracked_stats.supply_points_changed.is_connected(_on_resource_changed):
			_tracked_stats.supply_points_changed.disconnect(_on_resource_changed)
	if is_instance_valid(new_unit) and new_unit.stats:
		_tracked_stats = new_unit.stats
		_tracked_stats.ap_changed.connect(_on_resource_changed)
		_tracked_stats.supply_points_changed.connect(_on_resource_changed)
	else:
		_tracked_stats = null
	if is_instance_valid(_tracked_tactical_state) and _tracked_tactical_state.changed.is_connected(_update_button_states):
		_tracked_tactical_state.changed.disconnect(_update_button_states)
	_tracked_tactical_state = new_unit.tactical_state if is_instance_valid(new_unit) else null
	if is_instance_valid(_tracked_tactical_state):
		_tracked_tactical_state.changed.connect(_update_button_states)

	_update_button_states()

func _on_resource_changed(_current: int, _max_val: int) -> void:
	_update_button_states()

func _on_move_pressed() -> void:
	battle_controller.toggle_move_mode()

func _on_attack_pressed() -> void:
	battle_controller.toggle_attack_mode()

func _on_reload_pressed() -> void:
	var active_unit := battle_controller.tactical_unit
	if is_instance_valid(active_unit):
		await battle_controller.try_reload(active_unit)

func _on_aim_pressed() -> void:
	var active_unit := battle_controller.tactical_unit
	if is_instance_valid(active_unit):
		await battle_controller.try_aim(active_unit)

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
	var attack_query := battle_controller.query_attack(unit)
	var wait_query := battle_controller.query_simple(&"wait", unit)
	var reload_query := battle_controller.query_reload(unit)
	var aim_query := battle_controller.query_aim(unit)
	var attack_available := attack_query.is_legal() and attack_query.has_legal_targets() and not battle_controller.is_action_in_progress

	if move_button:
		move_button.disabled = not has_ap
	if attack_button:
		attack_button.disabled = not attack_available
		if not attack_query.is_legal():
			attack_button.tooltip_text = attack_query.reason
		elif not attack_query.has_legal_targets():
			attack_button.tooltip_text = "No legal targets"
		else:
			attack_button.tooltip_text = ""
	if reload_button:
		reload_button.disabled = not reload_query.is_legal()
		reload_button.tooltip_text = "Restore SP to %d" % reload_query.max_supply_points if reload_query.is_legal() else reload_query.reason()
		reload_button.text = "Reload (1 AP)"
	if aim_button:
		aim_button.disabled = not aim_query.is_legal()
		aim_button.tooltip_text = "Prepare the next Attack (+%d accuracy)" % aim_query.accuracy_bonus if aim_query.is_legal() else aim_query.reason()
		aim_button.text = "Aim (1 AP)"
	if supply_points_label:
		supply_points_label.text = "SP %d/%d" % [stats.current_supply_points, stats.max_supply_points]
	if tactical_state_label:
		tactical_state_label.text = "AIMED +%d" % TacticalState.AIM_ACCURACY_BONUS if unit.tactical_state and unit.tactical_state.is_aiming else ""
	if end_unit_button:
		end_unit_button.disabled = not wait_query.is_legal()
		end_unit_button.tooltip_text = "" if wait_query.is_legal() else wait_query.reason()

func _disable_all_buttons() -> void:
	if move_button: move_button.disabled = true
	if attack_button: attack_button.disabled = true
	if reload_button: reload_button.disabled = true
	if aim_button: aim_button.disabled = true
	if end_unit_button: end_unit_button.disabled = true
	if supply_points_label: supply_points_label.text = "SP —"
	if tactical_state_label: tactical_state_label.text = ""
