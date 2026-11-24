class_name LadderKneePlanner
extends RefCounted
## Where a climber's knee goes. The leg IK bends the knee toward a pole, so the pole decides whether a knee clears the rungs; a pole set by a fixed offset from the foot (the old behaviour: 0.55 m
## ahead of it) puts the knee through the ladder. This plans the knee from the ACTUAL hip and ankle and the body's own leg: a pure function, the same inputs give the same knee.
##
## The knee hinges forward of the leg; turning the thigh outward about the hip-ankle axis (a frog-leg stance) moves it sideways. Among the turns the hip allows, the planner takes the one nearest the
## turn it is asked to start from (the preferred stance, or the one the leg had a moment ago: a leg does not change its stance for no reason) whose leg volumes (knee, thigh, shin) clear every rung and
## rail, and returns the knee for it. If none clears, it returns the least overlap and says so (`clear` false).

## The preferred outward turn of the thigh, and the range the hip allows (degrees, outward positive).
const PREFERRED_TURN := 25.0
const MIN_TURN := -15.0
const MAX_TURN := 55.0
const STEP := 5.0
## Free gap wanted between a limb's surface and the bars (metres); a plan with less is not clear.
const MARGIN := 0.004
## The shin's volume ends this far down toward the ankle: the foot is ON a rung, so the last part of the shin is meant to be at it.
const SHIN_END := 0.8


## `hip` and `ankle` in the character's frame, `side` 0 = left, `floor_level` how far the character's floor is above the ladder's bottom, `start_turn` the turn to look around first.
## Returns {knee, pole, clear, overlap (<= 0 clear, else metres inside), turn (degrees), reachable}.
static func plan(geometry: LadderGeometry, body: LadderBody, hip: Vector3, ankle: Vector3, side: int, floor_level: float, start_turn := PREFERRED_TURN, landing: LadderLanding = null) -> Dictionary:
	var start := clampf(start_turn, MIN_TURN, MAX_TURN)
	var best := {}
	var best_overlap := INF
	# Candidate turns ordered by closeness to where the search starts.
	var turns: Array[float] = [start]
	var step := STEP
	while start + step <= MAX_TURN or start - step >= MIN_TURN:
		if start + step <= MAX_TURN:
			turns.append(start + step)
		if start - step >= MIN_TURN:
			turns.append(start - step)
		step += STEP
	for turn in turns:
		var candidate := at_turn(geometry, body, hip, ankle, side, floor_level, turn, landing)
		if candidate.overlap < best_overlap:
			best_overlap = candidate.overlap
			best = candidate
			if best_overlap <= -MARGIN:
				break
	best["clear"] = best_overlap <= -MARGIN
	return best


## The knee for one given outward turn (degrees): {knee, pole, overlap, turn, reachable}.
static func at_turn(geometry: LadderGeometry, body: LadderBody, hip: Vector3, ankle: Vector3, side: int, floor_level: float, turn: float, landing: LadderLanding = null) -> Dictionary:
	var axis := ankle - hip
	var distance := axis.length()
	var reachable := distance <= body.thigh + body.shin - 0.002
	distance = clampf(distance, absf(body.thigh - body.shin) + 0.01, body.thigh + body.shin - 0.002)
	var down := axis.normalized() if axis.length() > 0.0001 else Vector3.DOWN
	# The knee's place along the hip-ankle line and how far it stands off it.
	var along := (body.thigh * body.thigh - body.shin * body.shin + distance * distance) / (2.0 * distance)
	var offset := sqrt(maxf(body.thigh * body.thigh - along * along, 0.0))
	# The knee hinges forward, perpendicular to the leg in the body's sagittal plane: leg axis x lateral axis. (It was "toward the ladder (+z) minus its part along the leg", which collapses and
	# flips to the other side when the hip-ankle line itself turns toward +z, a foot reaching up and in front during a step: the knee pole jumped 0.9 m in two frames and the shin with it, 17 times
	# in one landing run. For a leg with no sideways lean the two are the same direction.)
	var hinge := down.cross(Vector3.RIGHT)
	hinge = hinge.normalized() if hinge.length() > 0.0001 else Vector3(0.0, 0.0, 1.0)
	var lateral := 1.0 if side == 0 else -1.0
	var direction := Basis(-down, deg_to_rad(turn) * lateral) * hinge
	var knee := hip + down * along + direction * offset
	var overlap := _overlap(geometry, body, hip, knee, ankle, floor_level, landing)
	return {"knee": knee, "pole": hip + down * along + direction * (offset + 0.25), "turn": turn, "overlap": overlap, "reachable": reachable}


## The deepest overlap (metres, <= 0 = clear by that much) of the knee, thigh and shin volumes with the ladder.
static func _overlap(geometry: LadderGeometry, body: LadderBody, hip: Vector3, knee: Vector3, ankle: Vector3, floor_level: float, landing: LadderLanding = null) -> float:
	var worst := geometry.penetration(knee, knee, body.knee_radius(), floor_level)
	worst = maxf(worst, geometry.penetration(hip, knee, body.thigh_radius(), floor_level))
	worst = maxf(worst, geometry.penetration(knee, knee.lerp(ankle, SHIN_END), body.shin_radius(), floor_level))
	# The deck and its face are obstacles too, once the host described a landing (character frame in, ladder frame for the deck: the floor level lifts y).
	if landing != null:
		var up := Vector3(0.0, floor_level, 0.0)
		var deck := landing.penetration(knee + up, knee + up, body.knee_radius(), geometry)
		deck = maxf(deck, landing.penetration(hip + up, knee + up, body.thigh_radius(), geometry))
		deck = maxf(deck, landing.penetration(knee + up, knee.lerp(ankle, SHIN_END) + up, body.shin_radius(), geometry))
		# A volume inside the deck is that much "inside" (positive); clear of it contributes nothing, so the rung and rail clearance (<= 0) still decides.
		if deck > 0.0:
			worst = maxf(worst, deck)
	return worst
