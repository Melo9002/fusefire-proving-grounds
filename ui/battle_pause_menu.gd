class_name BattlePauseMenu
extends Control

const MATCH_SETUP_PATH := "res://ui/match_setup.tscn"
const ActionCameraDirectorData := preload("res://presentation/camera/action_camera_director.gd")

@export var debug_tools: DebugTools
var is_open := false
var action_camera_option: OptionButton
var confirmations_option: CheckButton
var movement_confirmation_option: CheckButton
var _replay_was_paused := false
var _save_replay_button: Button
var _replay_save_status: Label

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("battle_pause_menu")
	_build_interface()
	visible = false

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	var controller := get_node_or_null("../../../Systems/BattleController") as BattleController
	if controller and is_instance_valid(controller.action_confirmation) and controller.action_confirmation.visible: return
	if debug_tools and debug_tools.panel_open:
		debug_tools.set_panel_open(false)
	set_open(not is_open)
	get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	if is_open == open:
		return
	is_open = open
	visible = open
	var replay_player := _get_replay_player()
	if replay_player:
		if open:
			_replay_was_paused = replay_player.playback_paused
			replay_player.set_playback_paused(true)
		else:
			replay_player.set_playback_paused(_replay_was_paused)
	else:
		get_tree().paused = open
	if open:
		var recording := _get_current_recording()
		_save_replay_button.disabled = recording == null or not recording.is_playable()
		_replay_save_status.hide()
		var resume := get_node("Dimmer/Center/Panel/Margin/Options/ResumeButton") as Button
		resume.grab_focus()

func _return_to_setup() -> void:
	get_tree().paused = false
	var level := get_node_or_null("../../..") as BattleLevel
	if level: level.return_to_match_setup()
	else: get_tree().change_scene_to_file(MATCH_SETUP_PATH)

func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100

	var dimmer := ColorRect.new()
	dimmer.name = "Dimmer"
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.01, 0.015, 0.025, 0.78)
	add_child(dimmer)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.custom_minimum_size = Vector2(340, 0)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 24)
	panel.add_child(margin)

	var options := VBoxContainer.new()
	options.name = "Options"
	options.add_theme_constant_override("separation", 12)
	margin.add_child(options)

	var title := Label.new()
	title.text = "BATTLE PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	options.add_child(title)

	var camera_label := Label.new()
	camera_label.name = "ActionCameraLabel"
	camera_label.text = "ACTION CAMERA"
	options.add_child(camera_label)
	action_camera_option = OptionButton.new()
	action_camera_option.name = "ActionCameraOption"
	for label in ["Off", "Final Actions", "Combat Only", "All Actions"]:
		action_camera_option.add_item(label)
	options.add_child(action_camera_option)
	var battle_level := get_node_or_null("../../..") as BattleLevel
	if battle_level and battle_level.battle_controller.replay_mode:
		camera_label.hide()
		action_camera_option.hide()
	_bind_action_camera_option.call_deferred()

	BattleUXSettings.load_preferences()
	confirmations_option = CheckButton.new()
	confirmations_option.name = "ConfirmationsOption"
	confirmations_option.text = "Confirm important actions"
	confirmations_option.button_pressed = BattleUXSettings.confirm_actions
	confirmations_option.tooltip_text = "Confirm shots, Aim, Shield, Skip and ending a turn with unused AP. Guard keeps its existing preview/confirm step."
	confirmations_option.toggled.connect(func(enabled: bool):
		BattleUXSettings.confirm_actions = enabled
		if BattleUXSettings.save_preferences() != OK: push_warning("Could not save action confirmation preference; it still applies this session."))
	options.add_child(confirmations_option)
	movement_confirmation_option = CheckButton.new()
	movement_confirmation_option.name = "MovementConfirmationOption"
	movement_confirmation_option.text = "Confirm movement (two clicks)"
	movement_confirmation_option.button_pressed = BattleUXSettings.confirm_movement
	movement_confirmation_option.tooltip_text = "Off: hover the ghost, click once to move. On: review the chosen destination, then Confirm or Cancel."
	movement_confirmation_option.toggled.connect(func(enabled: bool):
		BattleUXSettings.confirm_movement = enabled
		if BattleUXSettings.save_preferences() != OK: push_warning("Could not save movement confirmation preference; it still applies this session."))
	options.add_child(movement_confirmation_option)
	if battle_level and battle_level.battle_controller.replay_mode:
		confirmations_option.hide()
		movement_confirmation_option.hide()

	var resume := Button.new()
	resume.name = "ResumeButton"
	resume.text = "RESUME"
	resume.pressed.connect(func(): set_open(false))
	options.add_child(resume)

	_save_replay_button = Button.new()
	_save_replay_button.name = "PauseSaveReplayButton"
	_save_replay_button.text = "SAVE REPLAY…"
	_save_replay_button.tooltip_text = "Save the recorded actions from this battle."
	_save_replay_button.pressed.connect(_save_replay)
	options.add_child(_save_replay_button)
	_replay_save_status = Label.new()
	_replay_save_status.hide()
	options.add_child(_replay_save_status)
	var setup := Button.new()
	setup.name = "SetupButton"
	setup.text = battle_level.return_button_text() if battle_level else "RETURN TO MATCH SETUP"
	setup.pressed.connect(_return_to_setup)
	options.add_child(setup)

	var hint := Label.new()
	hint.text = "Esc — Resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	options.add_child(hint)

func _bind_action_camera_option() -> void:
	if _get_replay_player():
		# Replay has its own Free/Follow/Cinematic selector in the playback bar.
		action_camera_option.hide()
		get_node("Dimmer/Center/Panel/Margin/Options/ActionCameraLabel").hide()
		return
	var director := get_node_or_null("../../../ActionCameraDirector") as ActionCameraDirector
	if not is_instance_valid(director):
		action_camera_option.disabled = true
		return
	action_camera_option.select(int(director.frequency))
	action_camera_option.item_selected.connect(_on_action_camera_selected)

func _on_action_camera_selected(index: int) -> void:
	var director := get_node_or_null("../../../ActionCameraDirector") as ActionCameraDirector
	if is_instance_valid(director):
		director.set_frequency(index as ActionCameraDirector.Frequency)

func _get_replay_player() -> BattleReplayPlayer:
	return get_node_or_null("../../../BattleReplayPlayer") as BattleReplayPlayer

func _get_current_recording() -> BattleReplayRecording:
	var level := get_node_or_null("../../..") as BattleLevel
	return level.get_replay_recording() if level else null

func _save_replay() -> void:
	var hud := get_node_or_null("../TurnHUDController") as TurnHUDController
	var recording := _get_current_recording()
	if hud and recording:
		hud.choose_replay_destination(recording, _replay_save_status)
