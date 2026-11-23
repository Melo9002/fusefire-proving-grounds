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
## The pose witness of the skeleton and the stamp of the last sample. The clearance samples ITSELF from the witness's `final_pose` (the one moment the skeleton's pose is final), so there is no entry point that
## reads a stale or base pose and calls it a measurement; `status()` says whether the last sample may be used now.
var witness: PoseWitness
var stamp := {}
## Emitted after each sample, inside the final-pose window (overlays draw from it).
signal sampled


func _init(character_rig: CharacterRig) -> void:
	rig = character_rig
	skeleton = rig.skeleton
	witness = PoseWitness.acquire(skeleton)
	witness.final_pose.connect(_on_final_pose)


func _on_final_pose() -> void:
	sample()
	sampled.emit()


## Stops sampling (disconnects from the witness). The witness itself stays: other tools share it.
func release() -> void:
	if witness != null and witness.final_pose.is_connected(_on_final_pose):
		witness.final_pose.disconnect(_on_final_pose)
		witness.release()


## FRESH when the last sample was taken inside the update the skeleton is at now; STALE, UNAVAILABLE otherwise. Every mesh and joint reading below is valid only while this is FRESH.
func status() -> Measurement.Status:
	return witness.judge(stamp).status


func status_reason() -> String:
	return witness.judge(stamp).reason


func _bone_local(bone: StringName) -> Vector3:
	var index := skeleton.find_bone(bone)
	var world: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
	return rig.character_root.to_local(world)


## Reads the joints now and stamps the sample. Called by the witness's `final_pose`; called from anywhere else the stamp says "not final" and `status()` reports STALE.
func sample() -> void:
	stamp = witness.stamp()
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
	# The skinned mesh must be posed from the modifiers' result, which only exists inside this signal.
	_ensure_surface()
	_surface.capture()


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
	_ensure_surface()
	var result := {"rung": 0.0, "rail": 0.0, "deck": 0.0, "where": "", "bone": "", "points": _surface.size(), "status": status()}
	var worst := 0.0
	var points := _final_points()
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
		_ensure_surface()
	var points := _final_points()
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


## Every skinned leg vertex that is inside a rung or a rail by more than `threshold` metres in the last sample, deepest first (at most `limit`): {bone, bar ("rung 10" / "left rail"), depth, point (character frame), index of the
## rung}. For a person to see WHERE the surface meets the bar, and for the workbench overlay.
func offenders(geometry: LadderGeometry, climbed: float, threshold := 0.005, limit := 12) -> Array[Dictionary]:
	if _surface == null:
		_ensure_surface()
	var found: Array[Dictionary] = []
	var points := _final_points()
	var half := geometry.rail_half_span()
	# One transform for every vertex (surface -> the character's frame), and an exact early-out: every bar lies in the plane z = plane_ahead, so a vertex farther from that plane than the thicker bar's radius cannot be
	# inside any bar (its distance to a bar is at least its distance to the plane). Most of the leg is, so this is the cost of the sample: about 14 ms before, 2.7 ms for the skinning alone after.
	var to_character := rig.character_root.global_transform.affine_inverse() * skeleton.global_transform
	var reach := maxf(geometry.rung_radius, geometry.rail_radius) - threshold
	for i in points.size():
		var local: Vector3 = to_character * points[i]
		if absf(local.z - geometry.plane_ahead) >= reach:
			continue
		var p := local + Vector3(0.0, climbed, 0.0)
		var index := clampi(int(round((p.y - geometry.first_rung()) / geometry.spacing())), 0, geometry.rung_count() - 1)
		var rung_depth := geometry.rung_radius - LadderGeometry.segment_distance(p, Vector3(-half, geometry.rung_height(index), geometry.plane_ahead), Vector3(half, geometry.rung_height(index), geometry.plane_ahead))
		if rung_depth > threshold:
			found.append({"bone": String(skeleton.get_bone_name(_surface.bone_of(i))), "bar": "rung %d" % index, "rung": index, "depth": rung_depth, "point": local})
		for side in [-1.0, 1.0]:
			var rail_depth := geometry.rail_radius - LadderGeometry.segment_distance(p, Vector3(half * side, 0.0, geometry.plane_ahead), Vector3(half * side, geometry.rise, geometry.plane_ahead))
			if rail_depth > threshold:
				found.append({"bone": String(skeleton.get_bone_name(_surface.bone_of(i))), "bar": "%s rail" % ("left" if side > 0.0 else "right"), "rung": -1, "depth": rail_depth, "point": local})
	found.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.depth) > float(b.depth))
	if found.size() > limit:
		found.resize(limit)
	return found


## The surface skinned with the captured final pose, or NOTHING when the last sample is not fresh (an empty list reads as "no overlap", so callers that need to tell clean from unknown ask `status()` or use
## `vertex_evidence()`).
func _final_points() -> Array[Vector3]:
	_ensure_surface()
	if status() != Measurement.Status.FRESH or not _surface.has_capture():
		var none: Array[Vector3] = []
		return none
	return _surface.points()


## The sampled-vertex measurement as an envelope: the number of leg vertices more than `threshold` inside a rung or rail, FRESH only when the pose it was skinned from is the current final one. A count of zero
## from a stale or missing sample is reported as that, never as zero.
func vertex_evidence(geometry: LadderGeometry, climbed: float, threshold := 0.003, scenario := "") -> Measurement:
	var verdict := witness.judge(stamp)
	var m: Measurement
	if verdict.status != Measurement.Status.FRESH:
		m = Measurement.missing(Measurement.Kind.VERTEX_OVERLAP, "leg vertices inside ladder bars", verdict.status, verdict.reason)
	else:
		_ensure_surface()
		if not _surface.has_capture():
			m = Measurement.missing(Measurement.Kind.VERTEX_OVERLAP, "leg vertices inside ladder bars", Measurement.Status.UNAVAILABLE, "the skinned surface has no captured pose")
		else:
			m = Measurement.make(Measurement.Kind.VERTEX_OVERLAP, "leg vertices inside ladder bars", offenders(geometry, climbed, threshold, 100000).size(), "vertices")
			m.status = Measurement.Status.FRESH
	m.pose = Measurement.Pose.FINAL
	m.space = "character"
	m.source = "LadderClearance.vertex_evidence"
	m.method = "SkinnedSurface (linear blend skinning, poses cached inside skeleton_updated) of the leg and toe bones; vertex tested against rung and rail cylinders"
	m.tolerance = threshold
	m.stamped(witness, stamp)
	if verdict.status != Measurement.Status.FRESH:
		m.status = verdict.status
		m.reason = verdict.reason
	return m.with_identity(rig, scenario)


## Full triangle-against-bar intersection of the leg mesh: NOT measured by ADDA. Asking says so (UNSUPPORTED) instead of letting a vertex count stand in for it.
func intersection_evidence() -> Measurement:
	return Measurement.missing(Measurement.Kind.MESH_INTERSECTION, "leg mesh intersecting ladder bars", Measurement.Status.UNSUPPORTED, "only sampled vertices are measured (vertex_evidence); no triangle test exists yet")


func _ensure_surface() -> void:
	if _surface != null:
		return
	var b := rig.bones
	_surface_bones = [b.left_leg[0], b.left_leg[1], b.left_leg[2], b.right_leg[0], b.right_leg[1], b.right_leg[2]]
	for toe in [b.left_toes, b.right_toes]:
		if toe != &"" and skeleton.find_bone(toe) >= 0:
			_surface_bones.append(toe)
	_surface = SkinnedSurface.create(skeleton, _surface_bones)
