class_name AttackHost
extends RefCounted
## What an attack presentation needs from the body it is shown on (Task 07 package 6). The sequence owns WHEN things happen (raise, align, fire, recover, release); the host owns HOW the body
## does them: whether the weapon has reached its firing configuration, which clip plays, which readiness it holds. The base does nothing, so the sequence can be driven by a recording fake in tests
## and by any context (the tactical adapter today). No gameplay type appears here.

## False while the character cannot show a sequence at all (carrying, not processing, no muzzle): the shot is then shown at once.
func sequence_available() -> bool:
	return false

## True when, after that immediate shot, nothing will advance the sequence (carrying or not processing): it must release at once.
func immediate_release() -> bool:
	return true

func weapon_aligned() -> bool:
	return true

func alignment_error_degrees() -> float:
	return 0.0

func aim_blend() -> float:
	return 0.0

## The weapon blend the character is otherwise holding (what the release returns to).
func aim_target() -> float:
	return 0.0

func max_raise_wait_seconds() -> float:
	return 0.0

func recover_seconds() -> float:
	return 0.0

## The attack asks for the weapon up (a readiness request under AttackSequence.SOURCE) and starts whatever clip brings it there.
func begin_raise() -> void:
	pass

func release_aimed() -> void:
	pass

## Plays the shot's clip (muzzle flash, recoil and trigger follow from it).
func play_shot(_state: StringName) -> void:
	pass

## Back to what the character was doing before the shot (walking on, or its idle).
func resume_after_shot() -> void:
	pass

## The sequence ended, for any reason: forget what only an attack in progress needed (a cover firing plan).
func attack_ended() -> void:
	pass
