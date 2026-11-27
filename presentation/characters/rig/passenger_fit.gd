class_name PassengerFit
extends RefCounted
## Fits a carried body to the carrier that carries it, from the two bodies' own measurements. The steady carry's pose table and anchor were tuned for a body carrying its own kind; another size changes what
## the numbers mean: a taller passenger's legs hang below the floor from a small carrier's shoulder, and a smaller one is held out of the carrier's reach. Nothing here knows a character by name: the fit is a
## small search over two anatomy-driven knobs, decided once per pairing and remembered.
##
##   tuck   how far the legs are drawn up (1 = the table's hanging legs, 0 = thighs raised and knees folded),
##   slide  how far the body is moved on the carrier's shoulders (a carrier-frame vector, metres), so the held limbs come into the carrier's reach,
##   grip   where along the held forearm and thigh the hands take hold (the wrist is the authored place; the elbow end is nearer).
##
## It chooses the least change that (a) keeps the whole body above the floor with a clearance, and (b) keeps both held contacts within a comfortable share of the carrier's arm length. A same-body pairing
## (the table's own case) is left exactly as authored. The search runs on the carrier's REST pose; the carry's own lean and bob are what the verification measures afterwards.

## The lowest part of the passenger stays at least this far above the floor under the carrier (metres, at the reference body's size; it scales with the carrier).
const FLOOR_CLEARANCE := 0.10
## Held contacts should sit inside this share of the carrier's arm length (a fully straight arm is not a hold), and not so close that the elbow folds hard against the chest.
const REACH_LIMIT := 0.82
const REACH_MINIMUM := 0.40
## Where along the wrist-bearing forearm and the held thigh the hand may take hold (the authored place first).
const GRIP_WRIST: Array[float] = [0.85, 0.65, 0.45, 0.25]
const GRIP_THIGH: Array[float] = [0.9, 0.7, 0.5]
const TUCK_STEPS := [1.0, 0.85, 0.7, 0.55, 0.4, 0.25, 0.0]
## How far the body may be moved along the carrier's x (toward its legs positive); y up and z forward are bounded inside the search.
const SLIDE_X := 0.30
const SLIDE_STEP := 0.02
## The legs at full tuck, in the pose table's own terms (degrees forward of straight down the body): thighs raised toward the body's own line and the knees bent the right way (the shank swings toward the back of the leg), so less of the leg hangs below the shoulder.
const TUCKED := {"thigh": 55.0, "shin": 15.0, "foot": 5.0}

static var _cache := {}


## The fit for `passenger` carried by `rig`: {pose: overrides for the pose table, slide: metres along the spine, tuck, lowest, reach: [right, left], fitted: false when left as authored}.
static func solve(rig: CharacterRig, passenger: Node3D, contacts: Array) -> Dictionary:
	var definition: PassengerDefinition = passenger.definition
	if definition == null or definition.is_same_body_as(rig):
		return {"fitted": false, "pose": {}, "slide": Vector3.ZERO, "tuck": 1.0, "fractions": {}}
	var key := "%s|%s" % [PassengerDefinition.from_rig(rig).character_id, definition.character_id]
	if _cache.has(key):
		return _cache[key]
	var result := _search(rig, passenger, contacts)
	_cache[key] = result
	return result


static func clear_cache() -> void:
	_cache.clear()


static func _search(rig: CharacterRig, passenger: Node3D, contacts: Array) -> Dictionary:
	var body := rig.ladder_body()
	var arm := body.arm_length()
	var carrier_basis := rig.character_root.global_basis.orthonormalized()
	var floor_y := rig.character_root.global_position.y
	var neck := rig.skeleton.global_transform * rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone(rig.neck_bone_name)).origin
	var anchor_origin := neck + carrier_basis * rig.passenger_anchor_from_neck
	var shoulders: Array[Vector3] = []
	for chain in [rig.right_arm_bones, rig.left_arm_bones]:
		shoulders.append(rig.skeleton.global_transform * rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone(chain[0])).origin)
	var clearance := FLOOR_CLEARANCE * body.ratio
	var authored := PassivePassengerPose.DEFAULTS.duplicate()
	authored.merge(rig.passenger_pose_overrides, true)
	# 1. The least tuck that keeps the body off the floor (the floor does not depend on the slide or on where the contacts are held).
	var tuck := TUCK_STEPS[-1]
	var pose := _tucked(authored, tuck)
	var lowest := -INF
	for candidate: float in TUCK_STEPS:
		var candidate_pose := _tucked(authored, candidate)
		var at := Transform3D(carrier_basis, anchor_origin)
		var trial: Dictionary = passenger.trial(candidate_pose, at, shoulders, contacts, carrier_basis)
		if float(trial.lowest) - floor_y >= clearance or candidate == TUCK_STEPS[-1]:
			tuck = candidate
			pose = candidate_pose
			lowest = float(trial.lowest) - floor_y
			break
	# 2. Where the body hangs on the shoulders, and where along the held limbs the hands take hold, so both contacts are inside the carrier's reach with the least change. Moving the whole body only translates every
	#    point, and a grip position only moves a point along its limb, so this is arithmetic on one posed trial.
	var base_trial: Dictionary = passenger.trial(pose, Transform3D(carrier_basis, anchor_origin), shoulders, contacts, carrier_basis)
	var limbs: Dictionary = base_trial.limbs
	var best := {}
	var best_cost := INF
	var scale := body.ratio
	for dx in range(-int(SLIDE_X / SLIDE_STEP), int(SLIDE_X / SLIDE_STEP) + 1):
		for dy in range(int(-0.06 / SLIDE_STEP), int(0.12 / SLIDE_STEP) + 1):
			for dz in range(int(-0.15 / SLIDE_STEP), int(0.05 / SLIDE_STEP) + 1):
				var slide := Vector3(dx, dy, dz) * SLIDE_STEP
				var shift := carrier_basis * slide
				if lowest + slide.y < clearance:
					continue
				for wrist: float in GRIP_WRIST:
					for thigh: float in GRIP_THIGH:
						var fractions := {&"wrist": wrist, &"thigh": thigh}
						var reach: Array[float] = [0.0, 0.0]
						for contact in limbs:
							var limb: Dictionary = limbs[contact]
							var point: Vector3 = (limb.start as Vector3).lerp(limb.end, float(fractions[contact])) + shift
							reach[int(limb.side)] = point.distance_to(shoulders[int(limb.side)]) / arm
						var cost := _cost(reach, slide, wrist, thigh)
						if cost < best_cost:
							best_cost = cost
							best = {"fitted": true, "pose": pose, "slide": slide, "tuck": tuck, "lowest": lowest + slide.y, "reach": reach, "cost": cost, "fractions": fractions}
	if best.is_empty():
		best = {"fitted": true, "pose": pose, "slide": Vector3.ZERO, "tuck": tuck, "lowest": lowest, "reach": [], "cost": INF, "fractions": {}}
	return best


## What the search minimises: the clearance shortfall and any arm overreach (heavily), then how much it had to change the authored carry (lightly), so a fit that works with no change is the one chosen.
static func _cost(reach: Array[float], slide: Vector3, wrist: float, thigh: float) -> float:
	var cost := 0.0
	for side in 2:
		cost += maxf(reach[side] - REACH_LIMIT, 0.0) * 30.0 + maxf(REACH_MINIMUM - reach[side], 0.0) * 6.0
	return cost + slide.length() * 1.0 + absf(wrist - GRIP_WRIST[0]) * 0.5 + absf(thigh - GRIP_THIGH[0]) * 0.5


## The pose table's leg values drawn toward the tucked limit by `1 - tuck`.
static func _tucked(params: Dictionary, tuck: float) -> Dictionary:
	var pose := params.duplicate(true)
	for key in TUCKED:
		pose[key] = lerpf(float(TUCKED[key]), float(params[key]), tuck)
	return pose
