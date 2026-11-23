class_name LadderMetrics
extends RefCounted
## Measurements of a climbing body against the ladder, read from the FINAL skeleton pose (sample inside `skeleton_updated`). Everything is in the character's own frame (x = left, y = up
## from the floor under the root, z = forward toward the ladder), so a host's place and facing do not matter. The ladder is a LadderGeometry; the limbs are approximate volumes (capsules
## and spheres with radii taken from the body's own proportions), which is what "the knee goes through the rung" means to the eye.

## Arm radii as a fraction of the reference leg length (the leg volumes come from LadderBody).
const UPPER_ARM_RADIUS := 0.045 / 0.762
const FOREARM_RADIUS := 0.038 / 0.762

var rig: CharacterRig
var skeleton: Skeleton3D
## Last sample (filled by sample()): joint positions in the character frame.
var joints := {}


func _init(character_rig: CharacterRig) -> void:
	rig = character_rig
	skeleton = rig.skeleton


func _bone_local(bone: StringName) -> Vector3:
	var index := skeleton.find_bone(bone)
	var world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
	return rig.character_root.to_local(world)


## Reads the joints now. Call from a `skeleton_updated` handler (or right after the frame the pose was evaluated in).
func sample() -> void:
	var b := rig.bones
	joints = {
		"hips": _bone_local(b.hips), "spine": _bone_local(b.spine), "chest": _bone_local(b.chest if b.chest != &"" else b.spine), "head": _bone_local(b.head),
		"hip": [_bone_local(b.left_leg[0]), _bone_local(b.right_leg[0])],
		"knee": [_bone_local(b.left_leg[1]), _bone_local(b.right_leg[1])],
		"ankle": [_bone_local(b.left_leg[2]), _bone_local(b.right_leg[2])],
		"shoulder": [_bone_local(b.left_arm[0]), _bone_local(b.right_arm[0])],
		"elbow": [_bone_local(b.left_arm[1]), _bone_local(b.right_arm[1])],
		"wrist": [_bone_local(b.left_arm[2]), _bone_local(b.right_arm[2])],
	}


func arm_length(side: int) -> float:
	return rig._arm_length(1 - side)   # side 0 is the ladder's left


## The body's volumes against the ladder in the last sample: {knee, shin, thigh, torso, upper_arm, forearm}, the deepest overlap of each with a rung or a rail (metres, 0 when clear). The part of the
## shin and the forearm that is meant to touch a rung (the foot's and the hand's) is left out: the volumes end at 80% of the limb.
func clearance(ladder: LadderGeometry, climbed: float) -> Dictionary:
	var body := rig.ladder_body()
	var result := {"knee": 0.0, "shin": 0.0, "thigh": 0.0, "torso": 0.0, "upper_arm": 0.0, "forearm": 0.0}
	for side in 2:
		var hip: Vector3 = joints.hip[side]
		var knee: Vector3 = joints.knee[side]
		var ankle: Vector3 = joints.ankle[side]
		result.knee = maxf(result.knee, ladder.penetration(knee, knee, body.knee_radius(), climbed))
		result.thigh = maxf(result.thigh, ladder.penetration(hip, knee, body.thigh_radius(), climbed))
		result.shin = maxf(result.shin, ladder.penetration(knee, knee.lerp(ankle, 0.8), body.shin_radius(), climbed))
		var shoulder: Vector3 = joints.shoulder[side]
		var elbow: Vector3 = joints.elbow[side]
		var wrist: Vector3 = joints.wrist[side]
		result.upper_arm = maxf(result.upper_arm, ladder.penetration(shoulder, elbow, UPPER_ARM_RADIUS * body.ratio * 0.762, climbed))
		result.forearm = maxf(result.forearm, ladder.penetration(elbow, elbow.lerp(wrist, 0.8), FOREARM_RADIUS * body.ratio * 0.762, climbed))
	result.torso = ladder.penetration(joints.hips, joints.chest, body.torso_radius(), climbed)
	return result
