class_name BattlePauseMenu
extends Control

const MATCH_SETUP_PATH := "res://ui/match_setup.tscn"
const ActionCameraDirectorData := preload("res://systems/camera/action_camera_director.gd")

@export var debug_tools: DebugTools
var is_open := false
var action_camera_option: OptionButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("battle_pause_menu")
	_build_interface()
	visible = false

func _unhandled_key_input(event: InputEvent) -> void:
	if not event.pressed or event.echo or event.keycode != KEY_ESCAPE:
		return
	if debug_tools and debug_tools.panel_open:
		debug_tools.set_panel_open(false)
	set_open(not is_open)
	get_viewport().set_input_as_handled()

func set_open(open: bool) -> void:
	is_open = open
	visible = open
	get_tree().paused = open
	if open:
		var resume := get_node("Dimmer/Center/Panel/Margin/Options/ResumeButton") as Button
		resume.grab_focus()

func _return_to_setup() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MATCH_SETUP_PATH)

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
	camera_label.text = "ACTION CAMERA"
	options.add_child(camera_label)
	action_camera_option = OptionButton.new()
	action_camera_option.name = "ActionCameraOption"
	for label in ["Off", "Final Actions", "Combat Only", "All Actions"]:
		action_camera_option.add_item(label)
	options.add_child(action_camera_option)
	_bind_action_camera_option.call_deferred()

	var resume := Button.new()
	resume.name = "ResumeButton"
	resume.text = "RESUME"
	resume.pressed.connect(func(): set_open(false))
	options.add_child(resume)

	var setup := Button.new()
	setup.name = "SetupButton"
	setup.text = "RETURN TO MATCH SETUP"
	setup.pressed.connect(_return_to_setup)
	options.add_child(setup)

	var hint := Label.new()
	hint.text = "Esc — Resume"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.65, 0.7, 0.78))
	options.add_child(hint)

func _bind_action_camera_option() -> void:
	var director := get_tree().get_first_node_in_group("action_camera_director")
	if not director:
		action_camera_option.disabled = true
		return
	action_camera_option.select(int(director.frequency))
	action_camera_option.item_selected.connect(func(index: int): director.set_frequency(index))
