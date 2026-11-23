class_name LadderClearance
extends RefCounted
## READ-ONLY diagnostic (nothing here drives or writes a pose): the climbing body measured against the ladder and its landing, from the FINAL skeleton pose (call sample() inside `skeleton_updated`).
## Everything is in the character's own frame (x = left, y = up from the floor under the root, z = forward toward the ladder), so a host's place and facing do not matter. The ladder is a LadderGeometry,
## the landing a LadderLanding; the limbs are approximate volumes (capsules with radii from the body's own proportions) and the sole is taken from joints, which is what "the knee goes through the rung" means to the eye.

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
		"toe": [_bone_local(b.left_toes) if b.left_toes != &"" else _bone_local(b.left_leg[2]), _bone_local(b.right_toes) if b.right_toes != &"" else _bone_local(b.right_leg[2])],
		"shoulder": [_bone_local(b.left_arm[0]), _bone_local(b.right_arm[0])],
		"elbow": [_bone_local(b.left_arm[1]), _bone_local(b.right_arm[1])],
		"wrist": [_bone_local(b.left_arm[2]), _bone_local(b.right_arm[2])],
	}


func arm_length(side: int) -> float:
	return rig.ladder_body().arm_length()


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


## The body against the DECK of a landing in the last sample: {knee, thigh, shin, sole} the deepest overlap of each with the deck solid (metres, 0 when clear), as the host's LadderLanding describes it
## and `climbed` places it in the character's frame (the ladder's bottom is `climbed` below the floor under the root). The sole is the heel (below the ankle by the ankle height) and the ball (below the
## toe bone by its own height): joint-based approximations of the sole, not the mesh. Names the worst part and side, so a failure says where.
func deck_clearance(landing: LadderLanding, geometry: LadderGeometry, climbed: float) -> Dictionary:
	var body := rig.ladder_body()
	var result := {"knee": 0.0, "thigh": 0.0, "shin": 0.0, "sole": 0.0, "worst": "", "side": -1}
	var up := Vector3(0.0, climbed, 0.0)   # character frame -> ladder frame
	for side in 2:
		var hip: Vector3 = (joints.hip[side] as Vector3) + up
		var knee: Vector3 = (joints.knee[side] as Vector3) + up
		var ankle: Vector3 = (joints.ankle[side] as Vector3) + up
		var toe: Vector3 = (joints.toe[side] as Vector3) + up
		var heel := Vector3(ankle.x, ankle.y - body.ankle_height, ankle.z)
		var ball := Vector3(toe.x, toe.y - body.toe_height, toe.z)
		var parts := {
			"knee": landing.penetration(knee, knee, body.knee_radius(), geometry),
			"thigh": landing.penetration(hip, knee, body.thigh_radius(), geometry),
			"shin": landing.penetration(knee, knee.lerp(ankle, 0.8), body.shin_radius(), geometry),
			"sole": landing.penetration(heel, ball, 0.0, geometry),
		}
		for part in parts:
			if parts[part] > result[part]:
				result[part] = parts[part]
		var side_worst := ""
		var side_depth := 0.0
		for part in parts:
			if parts[part] > side_depth:
				side_depth = parts[part]
				side_worst = part
		if side_depth > float(result.get("worst_depth", 0.0)):
			result["worst_depth"] = side_depth
			result["worst"] = side_worst
			result["side"] = side
	return result


## Distance between the two knees across the ladder (metres) in the last sample: how wide the legs are held.
func knee_spread() -> float:
	return absf((joints.knee[0] as Vector3).x - (joints.knee[1] as Vector3).x)


## A readable report of the last sample for a panel or a log: the landing status, where the body is, and which limb overlaps which bar or the deck, deepest first, with the side and phase.
func readout(landing_status: String, landing: LadderLanding, geometry: LadderGeometry, climbed: float, phase: float) -> String:
	if joints.is_empty():
		return "no sample yet"
	var lines: Array[String] = ["landing: %s" % landing_status, "climbed %.2f m   landing phase %s   knee spread %.0f cm" % [climbed, ("%.2f" % phase) if phase >= 0.0 else "-", knee_spread() * 100.0]]
	var bars := clearance(geometry, climbed)
	lines.append("ladder bars (mm into):  knee %.0f  thigh %.0f  shin %.0f  torso %.0f" % [bars.knee * 1000.0, bars.thigh * 1000.0, bars.shin * 1000.0, bars.torso * 1000.0])
	if landing != null:
		var deck := deck_clearance(landing, geometry, climbed)
		lines.append("deck (mm into):         knee %.0f  thigh %.0f  shin %.0f  sole %.0f%s" % [deck.knee * 1000.0, deck.thigh * 1000.0, deck.shin * 1000.0, deck.sole * 1000.0,
			("   worst: %s, %s side" % [deck.worst, "left" if deck.side == 0 else "right"]) if String(deck.worst) != "" else ""])
	lines.append("(approximate: capsules from joints; sole from the ankle and toe bones)")
	return "\n".join(lines)
