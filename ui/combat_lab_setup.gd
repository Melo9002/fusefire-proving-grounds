extends VBoxContainer

signal changed

const LAUNCHER := "res://docs/quality/evidence/combat-policy-05/play_comparison.gd"
const MODE_ARGS := ["legacy", "head-core", "symmetric", "combined"]

var _engagement: ButtonGroup
var _contextual: CheckButton
var _guard: ButtonGroup
var _commander: ButtonGroup
var _battlefield: ButtonGroup
var _copy: Button

func _ready() -> void:
	add_theme_constant_override("separation", 8)
	_add_label("Engagement rules")
	_engagement = _choices(self, [
		["Legacy — Five-point targeting", CombatRules.EngagementPolicy.LEGACY],
		["Head/core — Central exposure", CombatRules.EngagementPolicy.HEAD_CORE],
		["Symmetrical — Mutual firing lanes", CombatRules.EngagementPolicy.SYMMETRIC],
		["Combined — Head/core and symmetry", CombatRules.EngagementPolicy.HEAD_CORE_SYMMETRIC],
	], CombatRules.EngagementPolicy.SYMMETRIC)
	add_child(HSeparator.new())

	_contextual = CheckButton.new()
	_contextual.text = "Contextual firing"
	_contextual.tooltip_text = "Enable automatic side-step attacks when the geometry allows it."
	_contextual.button_pressed = true
	_contextual.toggled.connect(func(_enabled: bool): changed.emit())
	add_child(_contextual)

	_add_label("Guard minimum hit chance")
	_guard = _choices(_row(), [["First legal", 0], ["15%", 15], ["25%", 25]], 15)

	_add_label("Enemy commander")
	_commander = _choices(_row(), [["Default", AICommanderPolicy.Profile.DEFAULT],
		["Cautious", AICommanderPolicy.Profile.CAUTIOUS]], AICommanderPolicy.Profile.CAUTIOUS)

	_add_label("Battlefield")
	_battlefield = _choices(self, [["Service Depot — Crossfire", 0], ["Freight Yard — Pressure", 1]], 0)
	add_child(HSeparator.new())

	_copy = Button.new()
	_copy.text = "Copy launch command"
	_copy.pressed.connect(_copy_command)
	add_child(_copy)

func build_configuration() -> BattleConfiguration:
	var config := BattleConfiguration.new()
	var pressure := _selected(_battlefield) == 1
	var ordinary := _selected(_commander) == AICommanderPolicy.Profile.DEFAULT
	config.configure_comparison(pressure, 2, ordinary)
	config.engagement_policy = _selected(_engagement)
	config.contextual_firing_disabled = not _contextual.button_pressed
	config.guard_minimum_chance = _selected(_guard)
	return config

func launch_command() -> String:
	var config := build_configuration()
	var project_path := ProjectSettings.globalize_path("res://").trim_suffix("/").replace("'", "''")
	var args := PackedStringArray([MODE_ARGS[config.engagement_policy]])
	if config.contextual_firing_disabled: args.append("no-context")
	if config.guard_minimum_chance > 0: args.append("guard=%d" % config.guard_minimum_chance)
	if config.enemy_commander == AICommanderPolicy.Profile.DEFAULT: args.append("ordinary")
	if config.battlefield_id == BattlefieldCatalog.CONTEXTUAL_FREIGHT: args.append("pressure")
	return "godot_console --path '%s' --script %s -- %s" % [project_path, LAUNCHER, " ".join(args)]

func _copy_command() -> void:
	DisplayServer.clipboard_set(launch_command())
	_copy.text = "Command copied"
	await get_tree().create_timer(1.2).timeout
	_copy.text = "Copy launch command"

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
