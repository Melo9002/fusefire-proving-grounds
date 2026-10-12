extends Control
class_name ActionHUDController

@export var battle_controller: BattleController

@export_group("Action Buttons")
@export var move_button: Button
@export var attack_button: Button
@export var reload_button: Button
@export var aim_button: Button
@export var shield_button: Button
@export var overwatch_button: Button
@export var interact_button: Button
@export var emergency_seal_button: Button
@export var end_unit_button: Button
@export var supply_points_label: Label
@export var tactical_state_label: Label

var _tracked_stats: UnitStats
var _tracked_tactical_state: TacticalState
var _tracked_conditions: ConditionComponent

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
	if shield_button:
		shield_button.pressed.connect(_on_shield_pressed)
	if overwatch_button:
		overwatch_button.pressed.connect(_on_overwatch_pressed)
	if interact_button:
		interact_button.pressed.connect(_on_interact_pressed)
	if emergency_seal_button:
		emergency_seal_button.pressed.connect(_on_emergency_seal_pressed)
	battle_controller.shield_mode_toggled.connect(_on_shield_mode_toggled)
	battle_controller.overwatch_mode_toggled.connect(_on_overwatch_mode_toggled)
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
	if is_instance_valid(_tracked_conditions) and _tracked_conditions.changed.is_connected(_update_button_states):
		_tracked_conditions.changed.disconnect(_update_button_states)
	_tracked_conditions = new_unit.conditions if is_instance_valid(new_unit) else null
	if is_instance_valid(_tracked_conditions): _tracked_conditions.changed.connect(_update_button_states)

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

func _on_shield_pressed() -> void:
	battle_controller.toggle_shield_mode()

func _on_overwatch_pressed() -> void:
	var active_unit := battle_controller.tactical_unit
	if not is_instance_valid(active_unit): return
	if battle_controller.is_overwatch_mode_active:
		await battle_controller.try_overwatch(active_unit)
	else:
		battle_controller.toggle_overwatch_mode()

func _on_interact_pressed() -> void:
	var active_unit := battle_controller.tactical_unit
	if not is_instance_valid(active_unit): return
	var query := battle_controller.query_terminal(active_unit)
	if query.legal_target_ids.is_empty(): return
	await battle_controller.try_terminal(active_unit, query.legal_target_ids[0])

func _on_emergency_seal_pressed() -> void:
	var active_unit := battle_controller.tactical_unit
	if is_instance_valid(active_unit): await battle_controller.try_emergency_seal(active_unit)

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

func _on_shield_mode_toggled(is_active: bool) -> void:
	if shield_button:
		shield_button.text = "Choose Threat" if is_active else "Shield (1 AP)"

func _on_overwatch_mode_toggled(_is_active: bool) -> void:
	_update_button_states()

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

	var move_query := battle_controller.query_move(unit)
	var attack_query := battle_controller.query_attack(unit)
	var wait_query := battle_controller.query_simple(&"wait", unit)
	var reload_query := battle_controller.query_reload(unit)
	var aim_query := battle_controller.query_aim(unit)
	var shield_query := battle_controller.query_shield(unit)
	var overwatch_query := battle_controller.query_overwatch(unit)
	var terminal_query := battle_controller.query_terminal(unit)
	var seal_query := battle_controller.query_simple(&"emergency_seal", unit)
	var attack_available := attack_query.is_legal() and attack_query.has_legal_targets() and not battle_controller.is_action_in_progress

	if move_button:
		move_button.disabled = not move_query.is_legal() or battle_controller.is_action_in_progress
		move_button.tooltip_text = "" if move_query.is_legal() else move_query.validation.message
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
	if shield_button:
		shield_button.visible = unit.shield_capability != null
		shield_button.disabled = not shield_query.is_legal() or not shield_query.has_legal_threats()
		shield_button.tooltip_text = "Choose a hostile to face; protects a %.0f° arc" % shield_query.protected_arc_degrees if shield_query.is_legal() else shield_query.reason()
		if not battle_controller.is_shield_mode_active: shield_button.text = "Shield (1 AP)"
	if overwatch_button:
		overwatch_button.disabled = not overwatch_query.is_legal()
		overwatch_button.tooltip_text = "Confirm Guard: reserve one reaction against movement or a direct attack, then end this unit's activation." if battle_controller.is_overwatch_mode_active else ("Preview the guarded area before reserving one reaction." if overwatch_query.is_legal() else overwatch_query.reason())
		overwatch_button.text = "CONFIRM GUARD" if battle_controller.is_overwatch_mode_active else "Guard"
	if interact_button:
		interact_button.visible = not terminal_query.candidate_results.is_empty() or not terminal_query.target_id.is_empty()
		interact_button.disabled = terminal_query.legal_target_ids.is_empty()
		interact_button.tooltip_text = "Activate the adjacent mission terminal" if not terminal_query.legal_target_ids.is_empty() else terminal_query.reason()
		interact_button.text = "Interact"
	if emergency_seal_button:
		emergency_seal_button.visible = unit.conditions != null and unit.conditions.has(&"leaking")
		emergency_seal_button.disabled = not seal_query.is_legal()
		emergency_seal_button.tooltip_text = "Remove Leaking; restores no HP" if seal_query.is_legal() else seal_query.reason()
		emergency_seal_button.text = "Seal (1 AP · %d)" % unit.emergency_seal_charges
	if supply_points_label:
		supply_points_label.text = "SP %d/%d" % [stats.current_supply_points, stats.max_supply_points]
	if tactical_state_label:
		var condition_text := ""
		if unit.conditions and not unit.conditions.active.is_empty():
			var condition_entries: Array[String] = []
			for instance: ConditionInstance in unit.conditions.active.values():
				condition_entries.append("%s %d" % [instance.definition.display_name.to_upper(), instance.remaining_beats])
			condition_entries.sort()
			condition_text = " · ".join(condition_entries)
		if unit.tactical_state and unit.tactical_state.is_overwatching:
			tactical_state_label.text = "GUARD" + (" · " + condition_text if not condition_text.is_empty() else "")
		elif unit.tactical_state and unit.tactical_state.is_shielding:
			tactical_state_label.text = "SHIELD %.0f°,%.0f°" % [unit.tactical_state.shield_facing.x, unit.tactical_state.shield_facing.y] + (" · " + condition_text if not condition_text.is_empty() else "")
		else:
			var aim_text := "AIMED +%d" % TacticalState.AIM_ACCURACY_BONUS if unit.tactical_state and unit.tactical_state.is_aiming else ""
			tactical_state_label.text = " · ".join([aim_text, condition_text].filter(func(value: String): return not value.is_empty()))
	if end_unit_button:
		end_unit_button.disabled = not wait_query.is_legal()
		end_unit_button.tooltip_text = "" if wait_query.is_legal() else wait_query.reason()

func _disable_all_buttons() -> void:
	if move_button: move_button.disabled = true
	if attack_button: attack_button.disabled = true
	if reload_button: reload_button.disabled = true
	if aim_button: aim_button.disabled = true
	if shield_button: shield_button.disabled = true
	if overwatch_button: overwatch_button.disabled = true
	if interact_button: interact_button.disabled = true
	if emergency_seal_button: emergency_seal_button.disabled = true
	if end_unit_button: end_unit_button.disabled = true
	if supply_points_label: supply_points_label.text = "SP —"
	if tactical_state_label: tactical_state_label.text = ""
