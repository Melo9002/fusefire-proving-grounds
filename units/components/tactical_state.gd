class_name TacticalState
extends Node

signal changed
## Presentation notice; expiry rules and authoritative state remain here.
signal stances_expired(names: PackedStringArray)

var is_aiming := false
var is_shielding := false
var is_overwatching := false
## Normalized world X/Z direction between supported standing points selected when Shield Stance commits.
var shield_facing := Vector2.ZERO
## Attacks the shield has covered in this stance; only counted for a capability with a capacity limit.
var shield_attacks_covered := 0
var activation_round := -1
var activation_phase := -1


## Called by TurnManager before an actor may query actions. Re-selecting a
## player during the same faction phase is not a new activation.
func begin_activation(round_number: int, phase: int) -> bool:
	if activation_round == round_number and activation_phase == phase:
		return false
	activation_round = round_number
	activation_phase = phase
	var expired := PackedStringArray()
	if is_aiming: expired.append("Aim")
	if is_shielding: expired.append("Shield")
	if is_overwatching: expired.append("Guard (unused)")
	var changed_state := clear_aim()
	changed_state = clear_shield() or changed_state
	changed_state = clear_overwatch() or changed_state
	if not expired.is_empty(): stances_expired.emit(expired)
	return changed_state


func establish_aim() -> bool:
	if is_aiming:
		return false
	is_aiming = true
	changed.emit()
	return true


func clear_aim() -> bool:
	if not is_aiming:
		return false
	is_aiming = false
	changed.emit()
	return true

func establish_shield(facing: Vector2) -> bool:
	if facing.is_zero_approx():
		return false
	is_shielding = true
	shield_facing = facing.normalized()
	shield_attacks_covered = 0
	changed.emit()
	return true

## Records one attack the shield covered; the count is part of the replayed state.
func note_shield_attack() -> void:
	shield_attacks_covered += 1
	changed.emit()

func clear_shield() -> bool:
	if not is_shielding and shield_facing.is_zero_approx():
		return false
	is_shielding = false
	shield_facing = Vector2.ZERO
	shield_attacks_covered = 0
	changed.emit()
	return true

func establish_overwatch() -> bool:
	if is_overwatching:
		return false
	is_overwatching = true
	changed.emit()
	return true

func clear_overwatch() -> bool:
	if not is_overwatching:
		return false
	is_overwatching = false
	changed.emit()
	return true


func reset() -> void:
	is_aiming = false
	is_shielding = false
	is_overwatching = false
	shield_facing = Vector2.ZERO
	shield_attacks_covered = 0
	activation_round = -1
	activation_phase = -1
	changed.emit()
