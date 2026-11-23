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


## ---- Mesh level: the legs' actual skinned surface (SkinnedSurface) against the bars and the deck, in the last sample's pose. This is the VISIBLE overlap (a vertex of the drawn surface inside a bar, or below
## the deck's top or beyond its face), as opposed to the capsule approximation above, which is conservative in some places and not enough in others (the armor's real radius is measured in `agent-comms`/the report).
var _surface: SkinnedSurface
var _surface_bones: Array[StringName] = []

## {rung, rail, deck: deepest vertex inside each kind (metres, 0 when none), where: a readable place for the worst ("shin_l vertex inside rung 12", "thigh_r vertex below the deck top"), bone: its bone name,
## points: how many vertices were tested}. Vertices of the hands and arms are not tested: a hand ON a bar is the contact, not a defect.
func mesh_clearance(landing: LadderLanding, geometry: LadderGeometry, climbed: float) -> Dictionary:
	if _surface == null:
		var b := rig.bones
		_surface_bones = [b.left_leg[0], b.left_leg[1], b.left_leg[2], b.right_leg[0], b.right_leg[1], b.right_leg[2]]
		for toe in [b.left_toes, b.right_toes]:
			if toe != &"" and skeleton.find_bone(toe) >= 0:
				_surface_bones.append(toe)
		_surface = SkinnedSurface.create(skeleton, _surface_bones)
	var result := {"rung": 0.0, "rail": 0.0, "deck": 0.0, "where": "", "bone": "", "points": _surface.size()}
	var worst := 0.0
	var points := _surface.points()
	var half := geometry.rail_half_span()
	for i in points.size():
		var local := rig.character_root.to_local(skeleton.global_transform * points[i])
		var p := local + Vector3(0.0, climbed, 0.0)   # the ladder's frame: y up from its bottom
		# Rungs near this height: the nearest one decides.
		var index := clampi(int(round((p.y - geometry.first_rung()) / geometry.spacing())), 0, geometry.rung_count() - 1)
		var rung_depth := geometry.rung_radius - LadderGeometry.segment_distance(p, Vector3(-half, geometry.rung_height(index), geometry.plane_ahead), Vector3(half, geometry.rung_height(index), geometry.plane_ahead))
		var rail_depth := -INF
		var rail_side := 0
		for side in [-1.0, 1.0]:
			var depth := geometry.rail_radius - LadderGeometry.segment_distance(p, Vector3(half * side, 0.0, geometry.plane_ahead), Vector3(half * side, geometry.rise, geometry.plane_ahead))
			if depth > rail_depth:
				rail_depth = depth
				rail_side = int(side)
		var deck_depth := 0.0
		var deck_part := ""
		if landing != null:
			deck_depth = landing.penetration(p, p, 0.0, geometry)
			if deck_depth > 0.0:
				var lip := geometry.plane_ahead + landing.lip_from_rungs
				deck_part = "below the deck top" if (geometry.rise - p.y) < (p.z - lip) else "beyond the deck face"
		var bone_name := String(skeleton.get_bone_name(_surface.bone_of(i)))
		if rung_depth > result.rung:
			result.rung = rung_depth
			if rung_depth > worst:
				worst = rung_depth
				result.where = "%s vertex inside rung %d" % [bone_name, index]
				result.bone = bone_name
		if rail_depth > result.rail:
			result.rail = rail_depth
			if rail_depth > worst:
				worst = rail_depth
				result.where = "%s vertex inside the %s rail" % [bone_name, "left" if rail_side > 0 else "right"]
				result.bone = bone_name
		if deck_depth > result.deck:
			result.deck = deck_depth
			if deck_depth > worst:
				worst = deck_depth
				result.where = "%s vertex %s" % [bone_name, deck_part]
				result.bone = bone_name
	return result


## For a PLANTED foot (on a rung): how far its lowest skinned vertex is from the top of that rung (metres; negative = the sole is inside the rung), over the rung's footprint (within 5 cm of the rung plane in
## z and 9 cm of the ankle in x). One value per side, NAN where the foot is not planted on a rung. This is what the "foot is on the rung" claim means at the surface.
func planted_sole_vs_rung(pose: LadderPose, geometry: LadderGeometry, climbed: float) -> Array[float]:
	var result: Array[float] = [NAN, NAN]
	if _surface == null:
		mesh_clearance(null, geometry, climbed)
	var points := _surface.points()
	for side in 2:
		if pose.foot_swing[side] != 0.0 or pose.foot_rung[side] < 0:
			continue
		var rung_top := geometry.rung_height(pose.foot_rung[side]) + geometry.rung_radius
		var ankle_x: float = (joints.ankle[side] as Vector3).x
		var lowest := INF
		for i in points.size():
			var local := rig.character_root.to_local(skeleton.global_transform * points[i])
			if absf(local.x - ankle_x) > 0.09 or absf(local.z - geometry.plane_ahead) > 0.05:
				continue
			lowest = minf(lowest, local.y + climbed)
		if lowest < INF:
			result[side] = lowest - rung_top
	return result
