class_name UnitPortrait
extends Button

enum DisplayState { READY, SELECTED, EXHAUSTED, DEAD }

signal unit_requested(unit: TacticalUnit)

## The callsign: the heading that tells two soldiers apart.
@export var title_label: Label
## The role (archetype), beneath it.
@export var name_label: Label
@export var hp_label: Label
@export var ap_label: Label
@export var state_label: Label

var unit: TacticalUnit
var display_state: DisplayState = DisplayState.READY
var _is_selected: bool = false
var _is_dead: bool = false

func _ready() -> void:
	pressed.connect(_on_pressed)

func setup(target: TacticalUnit) -> void:
	unit = target
	# The heading is optional: a card built without one (older scenes, tests) still works.
	if title_label:
		title_label.text = target.get_display_name().to_upper()
	if name_label:
		name_label.text = TacticalArchetypeCatalog.resolve_or_generic(target.archetype_id, false).display_name
	target.stats.hp_changed.connect(_on_hp_changed)
	target.stats.ap_changed.connect(_on_ap_changed)
	target.defeated.connect(_on_unit_defeated)
	_on_hp_changed(target.stats.current_hp, target.stats.max_hp)
	_on_ap_changed(target.stats.current_ap, target.stats.max_ap)

func set_selected(value: bool) -> void:
	_is_selected = value
	_refresh_state()

func represents(candidate: TacticalUnit) -> bool:
	return is_instance_valid(unit) and unit == candidate

func _on_pressed() -> void:
	if is_instance_valid(unit) and not _is_dead:
		unit_requested.emit(unit)

func _on_hp_changed(current: int, maximum: int) -> void:
	hp_label.text = "HP  %d / %d" % [current, maximum]

func _on_ap_changed(current: int, maximum: int) -> void:
	ap_label.text = "AP  %d / %d" % [current, maximum]
	_refresh_state()

func _on_unit_defeated(_defeated_unit: TacticalUnit) -> void:
	_is_dead = true
	_is_selected = false
	unit = null
	_refresh_state()

func _refresh_state() -> void:
	if _is_dead:
		display_state = DisplayState.DEAD
		state_label.text = "DEAD"
		disabled = true
		modulate = Color(0.55, 0.3, 0.3)
	elif not is_instance_valid(unit) or unit.stats.current_ap <= 0:
		display_state = DisplayState.EXHAUSTED
		state_label.text = "EXHAUSTED"
		disabled = true
		modulate = Color(0.5, 0.5, 0.55)
	elif _is_selected:
		display_state = DisplayState.SELECTED
		state_label.text = "SELECTED"
		disabled = false
		modulate = Color(0.45, 0.9, 1.0)
	else:
		display_state = DisplayState.READY
		state_label.text = "READY"
		disabled = false
		modulate = Color.WHITE
