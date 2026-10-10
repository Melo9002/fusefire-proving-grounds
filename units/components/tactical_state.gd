class_name TacticalState
extends Node

signal changed

const AIM_ACCURACY_BONUS := 15

var is_aiming := false
var is_shielding := false
## Normalized X/Z grid direction selected when Shield Stance commits.
var shield_facing := Vector2.ZERO
var activation_round := -1
var activation_phase := -1


## Called by TurnManager before an actor may query actions. Re-selecting a
## player during the same faction phase is not a new activation.
func begin_activation(round_number: int, phase: int) -> bool:
	if activation_round == round_number and activation_phase == phase:
		return false
	activation_round = round_number
	activation_phase = phase
	var changed_state := clear_aim()
	changed_state = clear_shield() or changed_state
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
	changed.emit()
	return true

func clear_shield() -> bool:
	if not is_shielding and shield_facing.is_zero_approx():
		return false
	is_shielding = false
	shield_facing = Vector2.ZERO
	changed.emit()
	return true


func reset() -> void:
	is_aiming = false
	is_shielding = false
	shield_facing = Vector2.ZERO
	activation_round = -1
	activation_phase = -1
	changed.emit()
