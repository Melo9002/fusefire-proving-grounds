class_name UnitStats
extends Node
@export_group("Movement")
## Grid cells reachable by one Move action. This does not control animation speed.
@export_range(1, 30, 1, "suffix:cells") var speed: int = 5

signal hp_changed(current: int, max_hp: int)
signal ap_changed(current: int, effective_maximum: int)
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
## Normal configured AP before temporary capacity modifiers.
var _base_ap := 2
@export_range(0, 20, 1, "suffix:AP") var base_ap: int = 2:
	get:
		return _base_ap
	set(value):
		_apply_base_ap(value, false)
## Read-only compatibility name used by existing HUD and action code.
## Authored runtime capacity belongs to base_ap.
var max_ap: int:
	get:
		return effective_max_ap

var effective_max_ap: int:
	get:
		var modifier_total := 0
		for delta in _ap_modifiers.values():
			modifier_total += int(delta)
		return maxi(0, base_ap + modifier_total)

var activation_capacity_ap := 2
var spent_ap := 0
var current_ap: int:
	get:
		return maxi(0, activation_capacity_ap - spent_ap)

var _ap_modifiers: Dictionary = {}

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
	refresh_activation_ap()
	current_supply_points = max_supply_points

func has_enough_ap(amount: int) -> bool:
	return current_ap >= amount

func consume_ap(amount: int) -> bool:
	if amount < 0 or current_ap < amount:
		return false
	if amount == 0:
		return true
	spent_ap += amount
	ap_changed.emit(current_ap, effective_max_ap)
	return true

func spend_all_remaining_ap() -> int:
	var amount := current_ap
	if amount > 0:
		spent_ap += amount
		ap_changed.emit(current_ap, effective_max_ap)
	return amount

## Begins a legitimate activation budget. Modifiers persist; expenditure does not.
func refresh_activation_ap() -> void:
	var before_current := current_ap
	var before_capacity := activation_capacity_ap
	activation_capacity_ap = effective_max_ap
	spent_ap = 0
	if before_current != current_ap or before_capacity != activation_capacity_ap:
		ap_changed.emit(current_ap, effective_max_ap)

## Explicit fixture/debug setup. Gameplay must spend through consume_ap() or
## spend_all_remaining_ap(); this method never changes activation capacity.
func set_available_ap_for_setup(value: int) -> void:
	var before := current_ap
	var requested := clampi(value, 0, activation_capacity_ap)
	spent_ap = activation_capacity_ap - requested
	if before != current_ap:
		ap_changed.emit(current_ap, effective_max_ap)

func configure_base_ap(value: int, refresh_current_activation := false) -> void:
	_apply_base_ap(value, refresh_current_activation)

func _apply_base_ap(value: int, refresh_current_activation: bool) -> void:
	var before_current := current_ap
	var before_effective := effective_max_ap
	var normalized := maxi(0, value)
	if _base_ap != normalized:
		_base_ap = normalized
		_ratchet_activation_capacity()
	if refresh_current_activation:
		activation_capacity_ap = effective_max_ap
		spent_ap = 0
	if before_current != current_ap or before_effective != effective_max_ap:
		ap_changed.emit(current_ap, effective_max_ap)

func set_ap_modifier(source_id: StringName, delta: int) -> bool:
	if not _is_valid_ap_modifier_source(source_id):
		return false
	if delta == 0:
		return remove_ap_modifier(source_id)
	var before_current := current_ap
	var before_effective := effective_max_ap
	_ap_modifiers[source_id] = delta
	_ratchet_activation_capacity()
	if before_current != current_ap or before_effective != effective_max_ap:
		ap_changed.emit(current_ap, effective_max_ap)
	return true

func remove_ap_modifier(source_id: StringName) -> bool:
	if not _is_valid_ap_modifier_source(source_id) or not _ap_modifiers.has(source_id):
		return false
	var before_current := current_ap
	var before_effective := effective_max_ap
	_ap_modifiers.erase(source_id)
	_ratchet_activation_capacity()
	if before_current != current_ap or before_effective != effective_max_ap:
		ap_changed.emit(current_ap, effective_max_ap)
	return true

func has_ap_modifier(source_id: StringName) -> bool:
	return _ap_modifiers.has(source_id)

func get_ap_modifier(source_id: StringName) -> int:
	return int(_ap_modifiers.get(source_id, 0))

func get_ap_modifier_snapshot() -> Array[Dictionary]:
	var source_ids: Array[StringName] = []
	for source_id in _ap_modifiers.keys():
		source_ids.append(StringName(source_id))
	source_ids.sort()
	var snapshot: Array[Dictionary] = []
	for source_id in source_ids:
		snapshot.append({"source_id": source_id, "delta": int(_ap_modifiers[source_id])})
	return snapshot

func get_ap_snapshot() -> Dictionary:
	return {
		"base_ap": base_ap,
		"effective_max_ap": effective_max_ap,
		"activation_capacity_ap": activation_capacity_ap,
		"spent_ap": spent_ap,
		"current_ap": current_ap,
		"modifiers": get_ap_modifier_snapshot(),
	}

func _is_valid_ap_modifier_source(source_id: StringName) -> bool:
	return not String(source_id).strip_edges().is_empty()

func _ratchet_activation_capacity() -> void:
	activation_capacity_ap = mini(activation_capacity_ap, effective_max_ap)

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

func refresh_activation() -> void:
	refresh_activation_ap()
	reset_turn_statuses()
