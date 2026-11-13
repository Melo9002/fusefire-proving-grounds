extends Control
class_name TurnHUDController

@export var turn_manager: TurnManager
@export var battle_controller: BattleController
@export var objective_manager: ObjectiveManager
@export var turn_label: Label
@export var end_turn_button: Button
var replay_button: Button
var setup_button: Button
var save_replay_button: Button
var _save_dialog: FileDialog
var _save_dialog_holds_pause := false
var _paused_before_save_dialog := false
var _save_status: Label

func _ready() -> void:
	if not turn_manager or not battle_controller or not turn_label or not end_turn_button:
		push_error("TurnHUDController: Missing UI dependencies!")
		return
	turn_manager.turn_phase_changed.connect(_on_turn_phase_changed)
	turn_manager.battle_ended.connect(_on_battle_ended)
	turn_manager.player_actions_exhausted.connect(_on_player_actions_exhausted)
	battle_controller.debug_enemy_control_changed.connect(_on_debug_enemy_control_changed)
	battle_controller.debug_player_ai_changed.connect(_on_debug_player_ai_changed)
	battle_controller.action_state_changed.connect(_on_action_state_changed)
	end_turn_button.pressed.connect(_on_end_turn_pressed)
	_build_battle_end_buttons()

func _build_battle_end_buttons() -> void:
	var container := end_turn_button.get_parent()
	replay_button = Button.new()
	replay_button.name = "ReplayButton"
	replay_button.text = "REPLAY BATTLE"
	replay_button.visible = false
	replay_button.pressed.connect(_on_replay_pressed)
	container.add_child(replay_button)
	save_replay_button = Button.new()
	save_replay_button.name = "SaveReplayButton"
	save_replay_button.text = "SAVE REPLAY…"
	save_replay_button.visible = false
	save_replay_button.pressed.connect(_choose_replay_destination)
	container.add_child(save_replay_button)
	_save_status = Label.new()
	_save_status.name = "ReplaySaveStatus"
	_save_status.hide()
	container.add_child(_save_status)
	setup_button = Button.new()
	setup_button.name = "MatchSetupButton"
	setup_button.text = "RETURN TO MATCH SETUP"
	setup_button.visible = false
	setup_button.pressed.connect(_on_setup_pressed)
	container.add_child(setup_button)

func _on_turn_phase_changed(new_phase: TurnManager.TurnPhase) -> void:
	# Battle completion can occur while an action is still inside its presentation
	# barrier. Later busy-state refreshes must not replace the terminal result with
	# the underlying TRANSITION phase label.
	if turn_manager.battle_result != TurnManager.BattleResult.ONGOING:
		_show_battle_result(turn_manager.battle_result)
		return
	end_turn_button.show()
	if battle_controller.replay_mode and new_phase != TurnManager.TurnPhase.TRANSITION:
		turn_label.text = "REPLAY — ROUND %d" % turn_manager.current_round
		turn_label.modulate = Color(0.55, 0.86, 1.0)
		end_turn_button.disabled = true
		end_turn_button.text = "REPLAY IN PROGRESS"
		return
	match new_phase:
		TurnManager.TurnPhase.PLAYER_TURN:
			turn_label.text = "PLAYER TURN — AI" if battle_controller.debug_player_ai else "PLAYER TURN"
			turn_label.modulate = Color.GREEN
			end_turn_button.disabled = battle_controller.debug_player_ai
			end_turn_button.text = "End Turn"
			end_turn_button.modulate = Color.WHITE
		TurnManager.TurnPhase.ALLY_TURN:
			turn_label.text = "ALLY TURN — AI"
			turn_label.modulate = Color("2ecc71")
			end_turn_button.disabled = true
			end_turn_button.text = "Allies Acting"
		TurnManager.TurnPhase.ENEMY_TURN:
			turn_label.text = "ENEMY TURN — MANUAL" if battle_controller.debug_enemy_control else "ENEMY TURN"
			turn_label.modulate = Color.RED
			end_turn_button.disabled = not battle_controller.debug_enemy_control
			end_turn_button.text = "End Enemy Turn" if battle_controller.debug_enemy_control else "Enemies Acting"
			end_turn_button.modulate = Color.WHITE
		TurnManager.TurnPhase.TRANSITION:
			turn_label.text = "PHASE TRANSITION..."
			turn_label.modulate = Color.YELLOW
			end_turn_button.disabled = true

func _on_end_turn_pressed() -> void:
	print_rich("[color=cyan][UI][/color] End Turn button pressed!")
	if turn_manager:
		turn_manager.end_current_turn()

func _on_debug_enemy_control_changed(_enabled: bool) -> void:
	_on_turn_phase_changed(turn_manager.current_phase)

func _on_debug_player_ai_changed(_enabled: bool) -> void:
	_on_turn_phase_changed(turn_manager.current_phase)

func _on_action_state_changed(is_busy: bool) -> void:
	if is_busy:
		end_turn_button.disabled = true
		return
	_on_turn_phase_changed(turn_manager.current_phase)

func _on_battle_ended(result: TurnManager.BattleResult) -> void:
	_show_battle_result(result)

func _show_battle_result(result: TurnManager.BattleResult) -> void:
	end_turn_button.disabled = true
	end_turn_button.hide()
	if result == TurnManager.BattleResult.VICTORY:
		turn_label.text = "VICTORY"
		turn_label.modulate = Color.GREEN
	else:
		turn_label.text = "DEFEAT"
		turn_label.modulate = Color.RED
	if objective_manager and objective_manager.mission:
		turn_label.text += "\n" + objective_manager.get_result_report()
	if replay_button: replay_button.visible = true
	if save_replay_button: save_replay_button.visible = not battle_controller.replay_mode
	if setup_button: setup_button.visible = true

func _on_replay_pressed() -> void:
	var level := _find_battle_level()
	if level:
		level.replay_last_battle()

func _choose_replay_destination() -> void:
	if turn_manager.battle_result == TurnManager.BattleResult.ONGOING or battle_controller.replay_mode:
		return
	if not BattleReplaySession.has_recording():
		_show_save_status("No completed replay is available.", false)
		return
	if not _save_dialog:
		_save_dialog = FileDialog.new()
		_save_dialog.name = "SaveReplayDialog"
		_save_dialog.title = "Save FuseFire Replay"
		_save_dialog.transient = true
		_save_dialog.exclusive = true
		_save_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
		_save_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_save_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		_save_dialog.filters = PackedStringArray(["*.json ; FuseFire replay files"])
		_save_dialog.current_dir = OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
		_save_dialog.file_selected.connect(_save_replay_file)
		_save_dialog.visibility_changed.connect(_on_save_dialog_visibility_changed)
		add_child(_save_dialog)
	var recording: BattleReplayRecording = BattleReplaySession.last_recording
	var battlefield := String(recording.configuration.get("battlefield_id", "battle")).validate_filename()
	_save_dialog.current_file = "%s-%d.replay.json" % [battlefield, int(recording.configuration.get("seed", 0))]
	_save_dialog.popup_centered_ratio(0.75)

func _on_save_dialog_visibility_changed() -> void:
	if _save_dialog.visible:
		_paused_before_save_dialog = get_tree().paused
		_save_dialog_holds_pause = true
		get_tree().paused = true
	else:
		_release_save_dialog_pause()

func _exit_tree() -> void:
	_release_save_dialog_pause()

func _release_save_dialog_pause() -> void:
	if _save_dialog_holds_pause:
		_save_dialog_holds_pause = false
		get_tree().paused = _paused_before_save_dialog

func _save_replay_file(path: String) -> void:
	var result := BattleReplaySession.save_last(path)
	_show_save_status("Replay saved." if result == OK else "Save failed. %s" % error_string(result), result == OK)

func _show_save_status(message: String, success: bool) -> void:
	_save_status.text = message
	_save_status.modulate = Color("b9e8cf") if success else Color("ff9385")
	_save_status.show()

func _on_setup_pressed() -> void:
	var level := _find_battle_level()
	if level:
		level.return_to_match_setup()

func _find_battle_level() -> BattleLevel:
	var current: Node = battle_controller
	while current:
		if current is BattleLevel:
			return current as BattleLevel
		current = current.get_parent()
	return null

func _on_player_actions_exhausted() -> void:
	if turn_manager.battle_result != TurnManager.BattleResult.ONGOING:
		return
	end_turn_button.text = "END TURN — NO AP"
	end_turn_button.modulate = Color(1.0, 0.8, 0.2)
