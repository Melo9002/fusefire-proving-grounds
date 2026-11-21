class_name LadderPose
extends RefCounted
## The solved pose of a ladder climb at one height (TraversalSolver.ladder_pose), as typed fields. The solver stays a pure function that returns a dictionary (its hash is what the determinism tests compare);
## the rig converts that result once, here, so nothing downstream indexes a dictionary by name. Positions are in the character root's frame.

## How much of the pose applies: 0 is the ordinary standing or walking pose, 1 fully on the ladder.
var weight := 0.0
var on_ladder := false
var hips := Vector3.ZERO
var lean_degrees := 0.0
var twist_degrees := 0.0
var head_pitch_degrees := 0.0
var hands: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var feet: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## How much each hand holds (the hands let go of the ladder before the body does).
var hand_weight: Array[float] = [0.0, 0.0]
## The rung index each limb is on (-1 is the deck handhold), and how far it is toward the next (0 planted, 1 mid-way).
var hand_rung: Array[int] = [-1, -1]
var foot_rung: Array[int] = [-1, -1]
var hand_swing: Array[float] = [0.0, 0.0]
var foot_swing: Array[float] = [0.0, 0.0]
var hand_deck: Array[float] = [0.0, 0.0]

static func from_solver(result: Dictionary) -> LadderPose:
	var pose := LadderPose.new()
	pose.weight = float(result.get("weight", 0.0))
	pose.on_ladder = bool(result.get("on_ladder", pose.weight > 0.0))
	pose.hips = result.get("hips", Vector3.ZERO)
	pose.lean_degrees = float(result.get("lean_degrees", 0.0))
	pose.twist_degrees = float(result.get("twist_degrees", 0.0))
	pose.head_pitch_degrees = float(result.get("head_pitch_degrees", 0.0))
	for side in 2:
		pose.hands[side] = (result.get("hands", pose.hands) as Array)[side]
		pose.feet[side] = (result.get("feet", pose.feet) as Array)[side]
		pose.hand_weight[side] = float((result.get("hand_weight", pose.hand_weight) as Array)[side])
		pose.hand_rung[side] = int((result.get("hand_rung", pose.hand_rung) as Array)[side])
		pose.foot_rung[side] = int((result.get("foot_rung", pose.foot_rung) as Array)[side])
		pose.hand_swing[side] = float((result.get("hand_swing", pose.hand_swing) as Array)[side])
		pose.foot_swing[side] = float((result.get("foot_swing", pose.foot_swing) as Array)[side])
		pose.hand_deck[side] = float((result.get("hand_deck", pose.hand_deck) as Array)[side])
	return pose
