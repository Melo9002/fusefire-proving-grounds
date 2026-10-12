extends Node
class_name TurnManager

enum TurnPhase { PLAYER_TURN, ALLY_TURN, ENEMY_TURN, TRANSITION }
enum BattleResult { ONGOING, VICTORY, DEFEAT }

signal turn_phase_changed(new_phase: TurnPhase)
signal active_unit_changed(unit: TacticalUnit)
## Presentation hint emitted from the same selection boundary used by battlefield
## clicks, portraits, automatic cycling, and phase starts. It never changes turn state.
signal selection_focus_requested(unit: TacticalUnit, force_recenter: bool)
signal round_started(round_number: int)
## Synchronous authoritative boundary at the end of the current shared round.
signal tactical_beat_ended(beat_number: int)
signal battle_ended(result: BattleResult)
signal player_actions_exhausted
signal turn_ended(record: Dictionary)

@export_group("Battle Roster")
@export var player_units: Array[TacticalUnit] = []
@export var allied_units: Array[TacticalUnit] = []
@export var enemy_units: Array[TacticalUnit] = []

var current_phase: TurnPhase = TurnPhase.TRANSITION
var active_unit: TacticalUnit
var active_unit_index: int = 0
var current_round: int = 0
var battle_result: BattleResult = BattleResult.ONGOING
var automatic_annihilation_results := true
## Optional presentation barrier supplied by the battle action service.
## Authoritative AP may already be committed, but selection waits until the
## action lifecycle has completed its blocking presentation.
var action_completion_barrier: Callable
## Optional read-only rule for a legal free objective action. Zero ordinary AP
## does not end an activation while this returns true.
var free_objective_action_available: Callable

func start_battle() -> void:
	battle_result = BattleResult.ONGOING
	for unit in player_units:
		var callback = _on_player_ap_changed.bind(unit)
		if is_instance_valid(unit) and unit.stats and not unit.stats.ap_changed.is_connected(callback):
			unit.stats.ap_changed.connect(callback)
	current_round = 1
	round_started.emit(current_round)
	_start_player_turn_phase()

## Players end their phase manually; each AI ends its own activation.
func end_current_turn() -> void:
	if get_tree().paused:
		return
	if action_completion_barrier.is_valid() and action_completion_barrier.call():
		print_rich("[color=yellow][TurnManager][/color] Cannot end turn: An action is still being presented.")
		return
	if battle_result != BattleResult.ONGOING or is_any_unit_moving():
		print_rich("[color=yellow][TurnManager][/color] Cannot end turn: Unit is still moving!")
		return

	print_rich("[color=yellow][TURN][/color] end_current_turn() called. Current Phase: ", current_phase)
	var turn_record := {
		"kind": "end_turn",
		"actor": String(active_unit.tactical_id) if is_instance_valid(active_unit) else "",
		"round": current_round,
		"phase": int(current_phase),
	}
	if current_phase == TurnPhase.PLAYER_TURN:
		_start_ally_turn_phase()
	elif current_phase == TurnPhase.ALLY_TURN:
		_advance_ally_unit_queue()
	elif current_phase == TurnPhase.ENEMY_TURN:
		_advance_enemy_unit_queue()
	turn_ended.emit(turn_record)

func select_player_unit(unit: TacticalUnit) -> bool:
	if current_phase != TurnPhase.PLAYER_TURN or battle_result != BattleResult.ONGOING or is_any_unit_moving():
		return false
	if not is_instance_valid(unit) or not player_units.has(unit):
		return false
	if not _is_activation_eligible(unit) or unit.is_moving:
		return false

	_set_active_unit(unit, true)
	return true

func advance_automated_player(finished_unit: TacticalUnit) -> void:
	if current_phase != TurnPhase.PLAYER_TURN or battle_result != BattleResult.ONGOING:
		return
	# AP exhaustion may already have selected the next unit.
	if active_unit != finished_unit:
		return
	var candidate := _find_next_eligible(player_units, player_units.find(finished_unit), true)
	if candidate:
		_set_active_unit(candidate)
		return
	var turn_record := {
		"kind": "end_turn",
		"actor": String(finished_unit.tactical_id) if is_instance_valid(finished_unit) else "",
		"round": current_round,
		"phase": int(current_phase),
	}
	_start_ally_turn_phase()
	turn_ended.emit(turn_record)

func can_unit_act(unit: TacticalUnit) -> bool:
	if battle_result != BattleResult.ONGOING or active_unit != unit or is_any_unit_moving():
		return false
	if not is_instance_valid(unit) or not unit.stats or unit.stats.is_defeated:
		return false
	if current_phase == TurnPhase.PLAYER_TURN:
		return player_units.has(unit)
	if current_phase == TurnPhase.ALLY_TURN:
		return allied_units.has(unit)
	if current_phase == TurnPhase.ENEMY_TURN:
		return enemy_units.has(unit)
	return false

func remove_unit(unit: TacticalUnit) -> void:
	var was_active := active_unit == unit
	var was_player := player_units.has(unit)
	var was_ally := allied_units.has(unit)
	var was_enemy := enemy_units.has(unit)
	if is_instance_valid(unit) and unit.tactical_state:
		unit.tactical_state.reset()
	player_units.erase(unit)
	allied_units.erase(unit)
	enemy_units.erase(unit)
	if was_active:
		active_unit = null
		active_unit_changed.emit(null)
	_check_battle_result()
	if was_active and battle_result == BattleResult.ONGOING:
		_continue_after_active_unit_removed.call_deferred(was_player, was_ally, was_enemy)

func _continue_after_active_unit_removed(was_player: bool, was_ally: bool, was_enemy: bool) -> void:
	while action_completion_barrier.is_valid() and action_completion_barrier.call():
		await get_tree().process_frame
	if battle_result != BattleResult.ONGOING or is_instance_valid(active_unit):
		return
	if current_phase == TurnPhase.PLAYER_TURN and was_player:
		var candidate := _find_next_eligible(player_units, -1, false)
		if candidate:
			_set_active_unit(candidate)
			return
		if player_units.is_empty():
			# Let the committing action capture its stable post-extraction state
			# before phase continuation. Replay verifies that committed fingerprint
			# immediately after submit returns.
			await get_tree().process_frame
			end_current_turn()
			return
		player_actions_exhausted.emit()
	elif current_phase == TurnPhase.ALLY_TURN and was_ally:
		active_unit_index -= 1
		_advance_ally_unit_queue()
	elif current_phase == TurnPhase.ENEMY_TURN and was_enemy:
		active_unit_index -= 1
		_advance_enemy_unit_queue()

func remove_extracted_unit(unit: TacticalUnit) -> void:
	if is_instance_valid(unit) and unit.tactical_state:
		unit.tactical_state.reset()
	var was_active := active_unit == unit
	var was_player := player_units.has(unit)
	var was_ally := allied_units.has(unit)
	var was_enemy := enemy_units.has(unit)
	player_units.erase(unit)
	allied_units.erase(unit)
	enemy_units.erase(unit)
	if not was_active:
		return
	active_unit = null
	active_unit_changed.emit(null)
	# Preserve the established same-phase selection boundary in the committed
	# extraction fingerprint. Only an empty roster needs barrier-aware phase
	# continuation.
	if current_phase == TurnPhase.PLAYER_TURN and was_player:
		var candidate := _find_next_eligible(player_units, -1, false)
		if candidate:
			_set_active_unit(candidate)
			return
	_continue_after_active_unit_removed.call_deferred(was_player, was_ally, was_enemy)

func is_any_unit_moving() -> bool:
	for unit in player_units + allied_units + enemy_units:
		if is_instance_valid(unit) and unit.is_moving:
			return true
	return false

func _on_player_ap_changed(current: int, _maximum: int, unit: TacticalUnit) -> void:
	if current == 0:
		# Extraction or defeat may free the unit before this deferred check executes.
		_advance_exhausted_unit_if_needed.call_deferred(unit.get_instance_id())

func _advance_exhausted_unit_if_needed(exhausted_unit_id: int) -> void:
	if get_tree().paused:
		await get_tree().create_timer(0.0, false).timeout
	while action_completion_barrier.is_valid() and action_completion_barrier.call():
		await get_tree().process_frame
	var exhausted_unit := instance_from_id(exhausted_unit_id) as TacticalUnit
	if not is_instance_valid(exhausted_unit):
		return
	if is_instance_valid(exhausted_unit) and exhausted_unit.is_moving:
		await exhausted_unit.movement_finished
	if current_phase != TurnPhase.PLAYER_TURN or active_unit != exhausted_unit:
		return
	if not is_instance_valid(exhausted_unit) or not exhausted_unit.stats or exhausted_unit.stats.current_ap > 0:
		return
	if _has_free_objective_action(exhausted_unit):
		return
	_advance_from_exhausted_player(exhausted_unit)

func complete_free_objective_action(unit: TacticalUnit) -> void:
	if is_instance_valid(unit) and unit.stats and unit.stats.current_ap <= 0:
		_advance_exhausted_unit_if_needed.call_deferred(unit.get_instance_id())

func _advance_from_exhausted_player(exhausted_unit: TacticalUnit) -> void:
	var candidate := _find_next_eligible(player_units, player_units.find(exhausted_unit), true)
	if candidate:
		_set_active_unit(candidate)
		return
	player_actions_exhausted.emit()

func _check_battle_result() -> void:
	if battle_result != BattleResult.ONGOING or not automatic_annihilation_results:
		return
	if enemy_units.is_empty():
		_finish_battle(BattleResult.VICTORY)
	elif player_units.is_empty():
		_finish_battle(BattleResult.DEFEAT)

func finish_battle(result: BattleResult) -> void:
	if battle_result == BattleResult.ONGOING:
		_finish_battle(result)

func _finish_battle(result: BattleResult) -> void:
	battle_result = result
	current_phase = TurnPhase.TRANSITION
	active_unit = null
	turn_phase_changed.emit(current_phase)
	active_unit_changed.emit(null)
	battle_ended.emit(result)

func _start_player_turn_phase() -> void:
	current_phase = TurnPhase.PLAYER_TURN
	_prioritize_carrier(player_units)
	_refresh_roster(player_units)

	if player_units.is_empty():
		_start_ally_turn_phase()
		return
	var candidate := _find_next_eligible(player_units, -1, false)
	if candidate:
		_set_active_unit(candidate)
	else:
		_clear_active_unit()
	turn_phase_changed.emit(current_phase)
	if not candidate:
		_emit_player_actions_exhausted.call_deferred()

func _start_enemy_turn_phase() -> void:
	current_phase = TurnPhase.ENEMY_TURN
	_refresh_roster(enemy_units)

	active_unit_index = -1
	var candidate := _find_next_eligible(enemy_units, active_unit_index, false)
	if candidate:
		active_unit_index = enemy_units.find(candidate)
		_set_active_unit(candidate)
		turn_phase_changed.emit(current_phase)
	else:
		_clear_active_unit()
		_end_round()

func _start_ally_turn_phase() -> void:
	if allied_units.is_empty():
		_start_enemy_turn_phase()
		return
	current_phase = TurnPhase.ALLY_TURN
	_prioritize_carrier(allied_units)
	_refresh_roster(allied_units)
	active_unit_index = -1
	var candidate := _find_next_eligible(allied_units, active_unit_index, false)
	if candidate:
		active_unit_index = allied_units.find(candidate)
		_set_active_unit(candidate)
		turn_phase_changed.emit(current_phase)
	else:
		_clear_active_unit()
		_start_enemy_turn_phase()

func _advance_ally_unit_queue() -> void:
	if battle_result != BattleResult.ONGOING:
		return
	var queue_index := allied_units.find(active_unit) if is_instance_valid(active_unit) else active_unit_index
	var candidate := _find_next_eligible(allied_units, queue_index, false)
	if candidate:
		active_unit_index = allied_units.find(candidate)
		_set_active_unit(candidate)
		return
	_clear_active_unit()
	_start_enemy_turn_phase()

func _advance_enemy_unit_queue() -> void:
	if battle_result != BattleResult.ONGOING:
		return
	var queue_index := enemy_units.find(active_unit) if is_instance_valid(active_unit) else active_unit_index
	var candidate := _find_next_eligible(enemy_units, queue_index, false)
	if candidate:
		active_unit_index = enemy_units.find(candidate)
		_set_active_unit(candidate)
		return
	_clear_active_unit()
	_end_round()

func _end_round() -> void:
	tactical_beat_ended.emit(current_round)
	if battle_result != BattleResult.ONGOING:
		return
	current_round += 1
	round_started.emit(current_round)
	_start_player_turn_phase()

func _set_active_unit(unit: TacticalUnit, force_camera_recenter := false) -> void:
	if is_instance_valid(unit) and unit.tactical_state:
		unit.tactical_state.begin_activation(current_round, int(current_phase))
	active_unit = unit
	active_unit_changed.emit(active_unit)
	selection_focus_requested.emit(active_unit, force_camera_recenter)

func _clear_active_unit() -> void:
	if active_unit == null:
		return
	active_unit = null
	active_unit_changed.emit(null)

func _emit_player_actions_exhausted() -> void:
	if current_phase == TurnPhase.PLAYER_TURN and battle_result == BattleResult.ONGOING \
	and not is_instance_valid(active_unit):
		player_actions_exhausted.emit()

func _refresh_roster(roster: Array[TacticalUnit]) -> void:
	for unit in roster:
		if is_instance_valid(unit) and unit.stats and not unit.stats.is_defeated:
			unit.stats.refresh_activation()

func _is_activation_eligible(unit: TacticalUnit) -> bool:
	return is_instance_valid(unit) and unit.stats and not unit.stats.is_defeated \
		and (unit.stats.current_ap > 0 or _has_free_objective_action(unit))

func _has_free_objective_action(unit: TacticalUnit) -> bool:
	return free_objective_action_available.is_valid() and free_objective_action_available.call(unit)

func _find_next_eligible(roster: Array[TacticalUnit], after_index: int, wrap: bool) -> TacticalUnit:
	if roster.is_empty():
		return null
	var checks := roster.size() if wrap else roster.size() - after_index - 1
	for offset in range(1, checks + 1):
		var index := after_index + offset
		if wrap:
			index %= roster.size()
		if index >= roster.size():
			break
		var candidate := roster[index]
		if _is_activation_eligible(candidate):
			return candidate
	return null

func _prioritize_carrier(roster: Array[TacticalUnit]) -> void:
	for index in roster.size():
		var candidate := roster[index]
		if is_instance_valid(candidate) and candidate.is_carrying_unit():
			if index > 0:
				roster.remove_at(index)
				roster.push_front(candidate)
			return
