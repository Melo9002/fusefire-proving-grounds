class_name StairPose
extends RefCounted
## The solved feet and pelvis of a stair walk at one place along the stair (StairFootPlanner), as typed fields. The planner stays a set of pure functions returning dictionaries; the rig converts the result
## once, here. `s` is the body's distance along the stair from the lower cell centre; `step` is the tread interval the feet are planned at.

## One foot: where it is, whether it is planted, the hold it is between, how far through the swing, and the top of the tread it is on or heading for.
class Foot extends RefCounted:
	var position := Vector3.ZERO
	var planted := true
	var hold := 0
	var swing := 0.0
	var tread_top := 0.0

	static func from_planner(result: Dictionary) -> Foot:
		var foot := Foot.new()
		foot.position = result.get("position", Vector3.ZERO)
		foot.planted = bool(result.get("planted", true))
		foot.hold = int(result.get("hold", 0))
		foot.swing = float(result.get("swing", 0.0))
		foot.tread_top = float(result.get("tread_top", 0.0))
		return foot

var feet: Array[Foot] = []
## The pelvis height the planner chose, whether the feet could reach it, and the range it had to choose in.
var pelvis_height := 0.0
var pelvis_ok := true
var pelvis_low := 0.0
var pelvis_high := 0.0
var weight := 0.0
var s := 0.0
var step := 0
## The sideways shift of the pelvis over the supporting foot (world, horizontal); zero with the stance motion off.
var pelvis_offset := Vector3.ZERO

static func from_planner(foot_results: Array, pelvis: Dictionary, pose_weight: float, along: float, tread_step: int, shift := Vector3.ZERO) -> StairPose:
	var pose := StairPose.new()
	for result: Dictionary in foot_results:
		pose.feet.append(Foot.from_planner(result))
	pose.pelvis_height = float(pelvis.get("height", 0.0))
	pose.pelvis_ok = bool(pelvis.get("ok", true))
	pose.pelvis_low = float(pelvis.get("low", 0.0))
	pose.pelvis_high = float(pelvis.get("high", 0.0))
	pose.weight = pose_weight
	pose.s = along
	pose.step = tread_step
	pose.pelvis_offset = shift
	return pose
