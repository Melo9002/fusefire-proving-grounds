class_name UnitStats
extends Node
@export_group("Movement")
## Grid cells reachable by one Move action. This does not control animation speed.
@export_range(1, 30, 1, "suffix:cells") var speed: int = 5

signal hp_changed(current: int, max_hp: int)
signal ap_changed(current: int, max_ap: int)
signal supply_points_changed(current: int, maximum: int)
signal status_changed
signal defeated

@export_group("Health")
@export_range(1, 999, 1) var max_hp: int = 100:
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
@export_range(1, 20, 1) var max_ap: int = 2:
	set(value):
		max_ap = max(1, value)
		current_ap = min(current_ap, max_ap)

var current_ap: int = 2:
	set(value):
		var clamped_val = clampi(value, 0, max_ap)
		if current_ap != clamped_val:
			current_ap = clamped_val
			ap_changed.emit(current_ap, max_ap)

@export_group("Supply Points (SP)")
## Prototype attack supply capacity. This is intentionally unit-level until
## FuseFire has a concrete weapon/equipment model.
@export_range(1, 99, 1) var max_supply_points: int = 4:
	set(value):
		max_supply_points = max(1, value)
		current_supply_points = min(current_supply_points, max_supply_points)

var current_supply_points: int = 4:
	set(value):
		var clamped_value := clampi(value, 0, max_supply_points)
		if current_supply_points != clamped_value:
			current_supply_points = clamped_value
			supply_points_changed.emit(current_supply_points, max_supply_points)

var is_defending: bool = false:
	set(value):
		if is_defending != value:
			is_defending = value
			status_changed.emit()

var is_defeated: bool = false

func _ready() -> void:
	current_hp = max_hp
	current_ap = max_ap
	current_supply_points = max_supply_points

func has_enough_ap(amount: int) -> bool:
	return current_ap >= amount

func consume_ap(amount: int) -> void:
	current_ap -= amount

func reset_ap() -> void:
	current_ap = max_ap

func has_supply_points(amount: int) -> bool:
	return current_supply_points >= amount

func consume_supply_points(amount: int) -> void:
	current_supply_points -= amount

func reload_supply_points() -> int:
	var restored := max_supply_points - current_supply_points
	current_supply_points = max_supply_points
	return restored

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
