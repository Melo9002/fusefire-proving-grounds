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
## How far the knees are bent in the climbing carry, degrees (the carry's own is the first): more lifts the feet.
## The most the body may reach out sideways from the carrier's centre line in the climbing carry (metres, reference body): the rails' inner faces are 0.64 m apart and a limb has a radius.
const LATERAL_LIMIT := 0.24
## The climbing carry lifts the body clear of the floor by more than the ordinary carry needs: a passenger whose feet only just clear it reads as standing behind the carrier, not carried (metres, reference body).
const LADDER_CLEARANCE := 0.30
const LADDER_KNEE_BENDS: Array[float] = [60.0, 85.0, 110.0, 135.0]
## How far the thighs may be swung up toward the passenger's belly side, away from the ladder (degrees added to the hang), and how far ahead of the carrier's hips the legs may reach (metres, reference body).
const LADDER_THIGH_LIFTS: Array[float] = [0.0, 20.0, 40.0, 60.0]
## How far behind the rung plane every part of the passenger stays (a rung and a limb each have a radius, and the carrier's own body hugs the rungs).
const RUNG_MARGIN := 0.12
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


## The same question for the CLIMBING carry (LoadedClimbProfile): the body turned onto the back, the trunk leaned into the ladder. The search runs with the carrier's lean applied, because the passenger rides the
## chest and the lean lowers its legs and moves the supporting hand. Knobs: how far the knees are bent (the legs hang along the real down, so bending them lifts the feet), where the body hangs on the back (a
## carrier-frame vector) and where along the thigh the supporting hand holds. Returns {changed, pose, slide, fractions, lowest, reach}; `changed` is false when the authored climbing carry already clears the floor
## and keeps the hand in reach.
static func solve_ladder(rig: CharacterRig, passenger: Node3D, base_pose: Dictionary, orientation: Basis, contacts: Array) -> Dictionary:
	var definition: PassengerDefinition = passenger.definition
	var key := "ladder|%s|%s" % [PassengerDefinition.from_rig(rig).character_id, definition.character_id if definition != null else ""]
	if _cache.has(key):
		return _cache[key]
	var result := _search_ladder(rig, passenger, base_pose, orientation, contacts)
	_cache[key] = result
	return result


static func _search_ladder(rig: CharacterRig, passenger: Node3D, base_pose: Dictionary, orientation: Basis, contacts: Array) -> Dictionary:
	var profile := rig.loaded_climb_profile
	var body := rig.ladder_body()
	var ratio := body.ratio
	var arm := body.arm_length()
	var carrier_basis := rig.character_root.global_basis.orthonormalized()
	var floor_y := rig.character_root.global_position.y
	var hips := rig.skeleton.global_transform * rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone(rig.bones.hips)).origin
	var lean := Basis(carrier_basis.x, deg_to_rad(profile.climb_lean_degrees))
	# On the ladder the pelvis hangs back from the rungs where the plan puts it, not where the rest pose has it: the trunk, and the passenger on it, ride that.
	var plan := TraversalSolver.plan_ladder(rig.traversal_profile, LadderGeometry.for_rise(3.0), body)
	var pelvis := rig.character_root.to_global(plan.hips as Vector3)
	var plane_z := LadderGeometry.PLANE_AHEAD
	var neck := rig.skeleton.global_transform * rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone(rig.neck_bone_name)).origin
	var anchor_origin := neck + carrier_basis * (profile.anchor_from_neck * ratio)
	# The trunk leans about the hips: the anchor and the shoulders go with it, the floor does not.
	var leaned_anchor := Transform3D(lean * carrier_basis * orientation, pelvis + lean * (anchor_origin - hips))
	var shoulders: Array[Vector3] = []
	for chain in [rig.right_arm_bones, rig.left_arm_bones]:
		var shoulder: Vector3 = rig.skeleton.global_transform * rig.skeleton.get_bone_global_rest(rig.skeleton.find_bone(chain[0])).origin
		shoulders.append(pelvis + lean * (shoulder - hips))
	var clearance := LADDER_CLEARANCE * ratio
	var support := 0 if profile.free_hand == &"left" else 1
	var best := {}
	var best_cost := INF
	var centre_x := hips.dot(carrier_basis.x)
	for lift: float in LADDER_THIGH_LIFTS:
		for bend: float in LADDER_KNEE_BENDS:
			var pose := base_pose.duplicate()
			pose["thigh"] = float(base_pose.thigh) + lift
			pose["shin"] = float(pose.thigh) - bend
			pose["foot"] = float(pose.shin) - 16.0
			var trial: Dictionary = passenger.trial(pose, leaned_anchor, shoulders, contacts, carrier_basis * orientation)
			var limb: Dictionary = trial.limbs[&"thigh"]
			var lowest := float(trial.lowest) - floor_y
			# Sideways extent about the carrier's centre line (the body passes between the rails), and how far the legs reach ahead of the carrier's hips toward the rungs.
			var lowest_x := INF
			var highest_x := -INF
			var front := -INF
			for point: Vector3 in trial.points:
				var along := point.dot(carrier_basis.x)
				lowest_x = minf(lowest_x, along)
				highest_x = maxf(highest_x, along)
				front = maxf(front, rig.character_root.to_local(point).z)
			for dx in range(-int(0.20 / SLIDE_STEP), int(0.20 / SLIDE_STEP) + 1):
				for dy in range(int(-0.04 / SLIDE_STEP), int(0.16 / SLIDE_STEP) + 1):
					for dz in range(int(-0.30 / SLIDE_STEP), int(0.12 / SLIDE_STEP) + 1):
						var slide := Vector3(dx, dy, dz) * SLIDE_STEP
						var shift := lean * carrier_basis * slide
						var sideways := maxf(highest_x + shift.dot(carrier_basis.x) - centre_x, centre_x - (lowest_x + shift.dot(carrier_basis.x)))
						var ahead := front + shift.dot(carrier_basis.z) - (plane_z - RUNG_MARGIN * ratio)
						var body_cost := maxf(clearance - (lowest + shift.y), 0.0) * 40.0 + maxf(sideways - LATERAL_LIMIT * ratio, 0.0) * 30.0 + maxf(ahead, 0.0) * 40.0
						if body_cost >= best_cost:
							continue
						for thigh: float in GRIP_THIGH:
							var point: Vector3 = (limb.start as Vector3).lerp(limb.end, thigh) + shift
							var reach := point.distance_to(shoulders[support]) / arm
							var cost := body_cost + maxf(reach - REACH_LIMIT, 0.0) * 30.0 + maxf(REACH_MINIMUM - reach, 0.0) * 6.0
							cost += slide.length() * 1.0 + absf(thigh - GRIP_THIGH[0]) * 0.5 + (bend - LADDER_KNEE_BENDS[0]) * 0.01 + lift * 0.01
							if cost < best_cost:
								best_cost = cost
								best = {"changed": lift != 0.0 or bend != LADDER_KNEE_BENDS[0] or slide != Vector3.ZERO or thigh != GRIP_THIGH[0], "pose": {"thigh": pose.thigh, "shin": pose.shin, "foot": pose.foot}, "slide": slide,
									"fractions": {&"wrist": 0.85, &"thigh": thigh}, "lowest": lowest + shift.y, "reach": reach, "cost": cost, "bend": bend, "lift": lift}
	return best


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
