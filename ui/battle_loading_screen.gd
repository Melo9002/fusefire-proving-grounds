class_name BattleLoadingScreen
extends Control
## Opaque battle-preparation transition. It reports real initialization stages;
## it does not own generation or hide initialization failures.

signal dismissed

var _stage: Label
var _detail: Label
var _progress: ProgressBar
var _back_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 1000

	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color(0.008, 0.012, 0.02, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620, 260)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.075, 0.98)
	style.border_color = Color(0.12, 0.65, 0.85, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 44)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_right", 44)
	margin.add_theme_constant_override("margin_bottom", 36)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 18)
	margin.add_child(column)

	var title := Label.new()
	title.text = "PREPARING BATTLEFIELD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	column.add_child(title)
	_stage = Label.new()
	_stage.text = "Reading battle configuration…"
	_stage.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stage.add_theme_font_size_override("font_size", 18)
	column.add_child(_stage)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.value = 0.02
	_progress.show_percentage = false
	_progress.custom_minimum_size.y = 14
	column.add_child(_progress)
	_detail = Label.new()
	_detail.text = "MapData remains authoritative while visuals and combatants are prepared."
	_detail.modulate = Color(0.68, 0.76, 0.84)
	_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_detail)
	_back_button = Button.new()
	_back_button.text = "BACK TO MATCH SETUP"
	_back_button.visible = false
	_back_button.pressed.connect(func(): dismissed.emit())
	column.add_child(_back_button)

func set_stage(label: String, progress: float) -> void:
	if not is_node_ready():
		await ready
	_stage.text = label
	_progress.value = clampf(progress, 0.0, 1.0)

func show_failure(errors: Array) -> void:
	if not is_node_ready():
		await ready
	_stage.text = "BATTLEFIELD PREPARATION FAILED"
	_progress.value = 0.0
	var messages: PackedStringArray = []
	for error in errors:
		messages.append("%s: %s" % [error.get("code", "INITIALIZATION_FAILED"), error.get("message", "Battle initialization failed")])
	_detail.text = "\n".join(messages) if not messages.is_empty() else "Battle initialization failed without a diagnostic."
	_detail.modulate = Color(1.0, 0.55, 0.48)
	_back_button.visible = true
