class_name ReplayControls
extends Control

var replay_player: Node
var play_button: Button
var speed_button: OptionButton
var camera_button: OptionButton
var progress_label: Label

func setup(player: Node) -> void:
	replay_player = player
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_interface()
	player.playback_progressed.connect(_on_progressed)
	player.playback_finished.connect(_on_finished)

func _build_interface() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -74.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	play_button = Button.new()
	play_button.name = "ReplayPlayPauseButton"
	play_button.text = "PAUSE"
	play_button.pressed.connect(_toggle_pause)
	row.add_child(play_button)
	progress_label = Label.new()
	progress_label.name = "ReplayProgressLabel"
	progress_label.text = "ACTION 0 / %d" % replay_player.recording.actions.size()
	progress_label.custom_minimum_size.x = 150
	progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(progress_label)
	speed_button = OptionButton.new()
	speed_button.name = "ReplaySpeedButton"
	for label in ["0.5×", "1×", "2×", "4×"]:
		speed_button.add_item(label)
	speed_button.select(1)
	speed_button.item_selected.connect(_select_speed)
	row.add_child(speed_button)
	camera_button = OptionButton.new()
	camera_button.name = "ReplayCameraButton"
	camera_button.add_item("CAMERA: FREE")
	camera_button.add_item("CAMERA: FOLLOW ACTION")
	camera_button.add_item("CAMERA: CINEMATIC")
	camera_button.select(0)
	camera_button.item_selected.connect(_select_camera)
	row.add_child(camera_button)
	var setup_button := Button.new()
	setup_button.name = "ReplaySetupButton"
	setup_button.text = "RETURN TO SETUP"
	setup_button.pressed.connect(replay_player.level.return_to_match_setup)
	row.add_child(setup_button)

func _toggle_pause() -> void:
	replay_player.set_playback_paused(not replay_player.playback_paused)
	play_button.text = "PLAY" if replay_player.playback_paused else "PAUSE"

func _select_speed(index: int) -> void:
	var speeds := [0.5, 1.0, 2.0, 4.0]
	replay_player.set_playback_speed(speeds[index])

func _select_camera(index: int) -> void:
	replay_player.set_camera_mode(index as BattleReplayPlayer.CameraMode)

func _on_progressed(completed: int, total: int) -> void:
	progress_label.text = "ACTION %d / %d" % [completed, total]

func _on_finished(_success: bool) -> void:
	play_button.disabled = true
	play_button.text = "FINISHED"
