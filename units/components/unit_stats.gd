class_name UnitStats
extends Node
@export_group("Movement")
@export var speed: int = 5

signal hp_changed(current: int, max_hp: int)
signal ap_changed(current: int, max_ap: int)
signal status_changed
signal defeated

@export_group("Health")
@export var max_hp: int = 100:
	set(value):
		max_hp = max(1, value)
		current_hp = min(current_hp, max_hp)

var current_hp: int = 100:
	set(value):
		var clamped_val = clampi(value, 0, max_hp)
		if current_hp != clamped_val:
			current_hp = clamped_val
			hp_changed.emit(current_hp, max_hp)

@export_group("Action Points (AP)")
@export var max_ap: int = 2:
	set(value):
		max_ap = max(1, value)
		current_ap = min(current_ap, max_ap)

var current_ap: int = 2:
	set(value):
		var clamped_val = clampi(value, 0, max_ap)
		if current_ap != clamped_val:
			current_ap = clamped_val
			ap_changed.emit(current_ap, max_ap)

var is_defending: bool = false:
	set(value):
		if is_defending != value:
			is_defending = value
			status_changed.emit()

var is_defeated: bool = false

func _ready() -> void:
	current_hp = max_hp
	current_ap = max_ap

func has_enough_ap(amount: int) -> bool:
	return current_ap >= amount

func consume_ap(amount: int) -> void:
	current_ap -= amount

func reset_ap() -> void:
	current_ap = max_ap

func take_damage(amount: int) -> void:
	if is_defeated:
		return

	var final_damage = amount
	if is_defending:
		final_damage = int(amount * 0.5)

	current_hp -= final_damage
	print_rich("[color=orange][UnitStats][/color] %s took %d damage (HP: %d/%d)" % [get_parent().name, final_damage, current_hp, max_hp])
	if current_hp == 0:
		is_defeated = true
		defeated.emit()

func reset_turn_statuses() -> void:
	is_defending = false

func reset_turn() -> void:
	reset_ap()
	reset_turn_statuses()
