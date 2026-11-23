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
static func plan(geometry: LadderGeometry, body: LadderBody, hip: Vector3, ankle: Vector3, side: int, floor_level: float, start_turn := PREFERRED_TURN) -> Dictionary:
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
		var candidate := at_turn(geometry, body, hip, ankle, side, floor_level, turn)
		if candidate.overlap < best_overlap:
			best_overlap = candidate.overlap
			best = candidate
			if best_overlap <= -MARGIN:
				break
	best["clear"] = best_overlap <= -MARGIN
	return best


## The knee for one given outward turn (degrees): {knee, pole, overlap, turn, reachable}.
static func at_turn(geometry: LadderGeometry, body: LadderBody, hip: Vector3, ankle: Vector3, side: int, floor_level: float, turn: float) -> Dictionary:
	var axis := ankle - hip
	var distance := axis.length()
	var reachable := distance <= body.thigh + body.shin - 0.002
	distance = clampf(distance, absf(body.thigh - body.shin) + 0.01, body.thigh + body.shin - 0.002)
	var down := axis.normalized() if axis.length() > 0.0001 else Vector3.DOWN
	# The knee's place along the hip-ankle line and how far it stands off it.
	var along := (body.thigh * body.thigh - body.shin * body.shin + distance * distance) / (2.0 * distance)
	var offset := sqrt(maxf(body.thigh * body.thigh - along * along, 0.0))
	var forward := Vector3(0.0, 0.0, 1.0)   # +z: toward the ladder
	var hinge := (forward - down * forward.dot(down)).normalized()
	var lateral := 1.0 if side == 0 else -1.0
	var direction := Basis(-down, deg_to_rad(turn) * lateral) * hinge
	var knee := hip + down * along + direction * offset
	var overlap := _overlap(geometry, body, hip, knee, ankle, floor_level)
	return {"knee": knee, "pole": hip + down * along + direction * (offset + 0.25), "turn": turn, "overlap": overlap, "reachable": reachable}


## The deepest overlap (metres, <= 0 = clear by that much) of the knee, thigh and shin volumes with the ladder.
static func _overlap(geometry: LadderGeometry, body: LadderBody, hip: Vector3, knee: Vector3, ankle: Vector3, floor_level: float) -> float:
	var worst := geometry.penetration(knee, knee, body.knee_radius(), floor_level)
	worst = maxf(worst, geometry.penetration(hip, knee, body.thigh_radius(), floor_level))
	worst = maxf(worst, geometry.penetration(knee, knee.lerp(ankle, SHIN_END), body.shin_radius(), floor_level))
	return worst
