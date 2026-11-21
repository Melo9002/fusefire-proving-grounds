class_name AimHold
extends RefCounted
## The presentation-only mirror of a committed Aim (Task 07 package 6): true while the sights should be up. It is PERSISTENT state, not an action: it never has a handle and is never "pending". The context
## says each frame whether the committed Aim is still held; after it ends the sights stay up for a grace period so the rifle does not dip while the attack camera moves in. The state machine lives here;
## what a transition DOES to the pose (which clip, which readiness) stays with the context. Weapon readiness itself (WeaponReadiness) is the rig's and is read, not copied, here.

enum Transition { NONE, ENGAGED, RELEASED }
## After the committed Aim ends, the sights stay up this long. A shot or any other action takes over sooner.
const RELEASE_GRACE := 1.0

var held := false
var release_left := 0.0

## The Aim action committed: sights up now.
func engage() -> void:
	held = true
	release_left = RELEASE_GRACE

## Drops the hold at once (a defeat, a teardown): nothing of it outlives the character.
func clear() -> void:
	held = false
	release_left = 0.0

## `committed`: the committed Aim is still held (and the unit is still, and not carrying). `settling_state`: the unit is in a quiet state a held Aim may change. Returns what changed.
func update(delta: float, committed: bool, settling_state: bool) -> Transition:
	if committed:
		release_left = RELEASE_GRACE
		if not held:
			held = true
			return Transition.ENGAGED
		return Transition.NONE
	if not held:
		return Transition.NONE
	release_left -= delta
	# Once the unit has moved on to a shot or any other action, the hold is simply over.
	if release_left <= 0.0 or not settling_state:
		held = false
		return Transition.RELEASED
	return Transition.NONE
