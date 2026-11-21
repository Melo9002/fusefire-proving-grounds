class_name WeaponPoseBinding
extends RefCounted
## What WeaponPoseModifier is wired to, once, when the rig builds it (Task 07 package 4): the skeleton and the bones it reads, the handful of nodes it adjusts, the live limits of the support
## arm, and the PoseTargetPlacer through which it asks the body to place targets. Wiring, not per-frame data: nothing here changes while the character plays except the shared `settings`
## object (the rig's inspector values live in it, so tuning one changes the modifier's behaviour at once, with no copying and no lookup by name).
##
## Stable skeletal facts (bone names, later measurements from the resolved rig profile) belong here; per-frame values never do.

var skeleton: Skeleton3D
var right_shoulder_bone: StringName
## Upper arm, forearm and hand of the SUPPORT (left) arm.
var left_arm_bones: Array[StringName] = []
var chest_bone: StringName
var character_root: Node3D
var arm_ik: TwoBoneIK3D
var support_target: Node3D
var crouch: CoverCrouchModifier
var settings: WeaponPoseSettings
var placer: PoseTargetPlacer
