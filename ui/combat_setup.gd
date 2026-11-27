extends VBoxContainer

signal changed
signal preset_selected(pressure: bool)

var _engagement: ButtonGroup
var _contextual: CheckButton
var _guard: ButtonGroup

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_add_label("Engagement rules")
	_engagement = _choices(self, [
		["Legacy — Five-point targeting", CombatRules.EngagementPolicy.LEGACY],
		["Head/core — Central exposure", CombatRules.EngagementPolicy.HEAD_CORE],
		["Symmetrical — Mutual firing lanes", CombatRules.EngagementPolicy.SYMMETRIC],
		["Combined — Head/core and symmetry", CombatRules.EngagementPolicy.HEAD_CORE_SYMMETRIC],
	], CombatRules.EngagementPolicy.HEAD_CORE_SYMMETRIC)
	add_child(HSeparator.new())

	_contextual = CheckButton.new()
	_contextual.text = "Contextual firing"
	_contextual.button_pressed = true
	_contextual.toggled.connect(func(_enabled: bool): changed.emit())
	add_child(_contextual)

	_add_label("Guard minimum hit chance")
	_guard = _choices(_row(), [["First legal", 0], ["15%", 15], ["25%", 25]], 0)

	add_child(HSeparator.new())
	_add_label("Load a playtest preset")
	var presets := _row()
	for pressure in [false, true]:
		var button := Button.new()
		button.name = "PressurePreset" if pressure else "CrossfirePreset"
		button.text = "Freight Yard — Pressure" if pressure else "Service Depot — Crossfire"
		button.tooltip_text = "Fills in the scenario, forces and combat settings in this setup."
		button.pressed.connect(func(): preset_selected.emit(pressure))
		presets.add_child(button)

func engagement_policy() -> int:
	return _selected(_engagement)

func guard_minimum_chance() -> int:
	return _selected(_guard)

func contextual_enabled() -> bool:
	return not _contextual.disabled and _contextual.button_pressed

func set_contextual_supported(supported: bool) -> void:
	_contextual.disabled = not supported
	if not supported: _contextual.set_pressed_no_signal(false)
	_contextual.tooltip_text = ("Enable automatic side-step attacks when the geometry allows it."
		if supported else "Available on Service Depot, Depot Crossfire and Freight Yard.")

func apply_preset() -> void:
	for option in _engagement.get_buttons():
		if option.get_meta("value") == CombatRules.EngagementPolicy.SYMMETRIC: option.button_pressed = true
	for option in _guard.get_buttons():
		if option.get_meta("value") == 15: option.button_pressed = true
	_contextual.set_pressed_no_signal(true)

func _add_label(text: String) -> void:
	var label := Label.new()
	label.text = text
	add_child(label)

func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	return row

func _choices(parent: Container, choices: Array, default_value: int) -> ButtonGroup:
	var group := ButtonGroup.new()
	for choice in choices:
		var option := CheckBox.new()
		option.text = choice[0]
		option.set_meta("value", choice[1])
		option.button_group = group
		option.button_pressed = choice[1] == default_value
		parent.add_child(option)
	group.pressed.connect(func(_button: BaseButton): changed.emit())
	return group

func _selected(group: ButtonGroup) -> int:
	return int(group.get_pressed_button().get_meta("value"))
