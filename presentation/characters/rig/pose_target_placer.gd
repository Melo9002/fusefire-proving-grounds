class_name PoseTargetPlacer
extends RefCounted
## The operations the weapon-pose modifier asks the BODY to perform from inside a skeleton pass (Task 07 package 4). The modifier cannot place the hand and elbow targets itself, because the
## formulas depend on the rig's weapon, carry and torso state, but it is the only stage that knows the same-pass shoulder and chest poses (a node's `_process` runs before the modifiers, and
## outside the pass the shoulder can be 29 cm from where it ends up in a half-kneel). So the modifier owns WHEN and supplies the same-pass poses; the rig owns the formulas and the targets.
##
## This is the whole contract between them, as typed methods: nothing else of the rig is reachable from the modifier, and a test can substitute a fake. The base class does nothing and
## reports nothing active, so a modifier with a bare placer leaves the pose alone.

## True while the carried passenger's contacts own the wrists (the weapon targets are then not used).
func carrying() -> bool:
	return false

## True while a ladder's contacts hold the hands.
func holding_traversal() -> bool:
	return false

## Carry: places the hand targets on the passenger's contacts. `right_shoulder` and `left_shoulder` are world positions in THIS pass.
func place_carry_targets(_right_shoulder: Vector3, _left_shoulder: Vector3) -> void:
	pass

## The chest's orientation in the character-root frame, in THIS pass, and the pass's delta (the settled torso reference follows it).
func observe_torso_frame(_chest_in_root: Basis, _delta: float) -> void:
	pass

## The stock pocket, both hand targets and the elbow poles, from the right shoulder (world) of THIS pass.
func place_weapon_targets(_right_shoulder: Vector3) -> void:
	pass

## A ladder climbed: the hands go to its contacts over the weapon's targets.
func place_traversal_hand_targets() -> void:
	pass

## The elbow poles from the final shoulders and hand targets of this pass; `chest_world` is the chest's world orientation.
func guide_elbows(_right_shoulder: Vector3, _left_shoulder: Vector3, _chest_world: Basis, _carrying: bool) -> void:
	pass
