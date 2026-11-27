class_name LoadedLadderCarry
extends RefCounted
## The loaded-ladder presentation state of one climb: how far the carry has been transferred from the ordinary carry (0) to the climbing carry (1), where it is going, and the clock that moves it. It exists from
## `CharacterRig.begin_traversal(..., loaded_presentation = true)` until the ordinary carry is fully restored, which can be after the ladder itself has ended (the carrier walks on while the passenger settles).
##
## Everything here is a pure function of the clock the rig gives it (`advance`), so a fixed-step run repeats exactly. Nothing here knows a character; the numbers are LoadedClimbProfile's.

var profile: LoadedClimbProfile
## 0 = ordinary carry, 1 = climbing carry. Moves linearly toward `target` over the profile's transfer time; `eased` is what the presentation uses.
var blend := 0.0
var target := 1.0
## The ladder's last free-hand target in the carrier's frame, kept so the hand can return to the passenger after the ladder has ended.
var last_hand_local := Vector3.INF
var last_hand_weight := 0.0


func _init(climb_profile: LoadedClimbProfile) -> void:
	profile = climb_profile


func advance(delta: float) -> void:
	var step := delta / maxf(profile.transfer_seconds, 0.001)
	blend = move_toward(blend, target, step)


## The blend as the presentation reads it: eased at both ends, so the passenger and the hand start and stop gently.
func eased() -> float:
	return smoothstep(0.0, 1.0, blend)


## True when the climb may move the body: the passenger is in the climbing carry, or is on its way back (then the climb is already over its far end). False while the transfer into the climbing carry is still running.
func ready() -> bool:
	return blend >= 0.999 or target <= 0.5


## True once the ordinary carry is back (nothing left of the transfer).
func restored() -> bool:
	return blend <= 0.0001 and target <= 0.0001
