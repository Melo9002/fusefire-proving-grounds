class_name TraversalPoseInput
extends RefCounted
## The traversal pose the body should show this frame (Task 07 package 4), as typed data: what TraversalPoseModifier applies to the pelvis and the leg IK. CharacterRig publishes it whenever
## the traversal or stair pose changes (the solved pose itself is TraversalSolver / StairFootPlanner output; the rig translates it), and the modifier reads nothing else of the rig.
## Ladder values are in the character's own frame (the modifier converts them with the character root of THIS pass); stair values are the planner's world-space results.

enum Mode { NONE, LADDER, STAIRS }

var mode: Mode = Mode.NONE
## False while a ladder traversal is active but its pose has not been solved yet (nothing to apply).
var solved := false
var weight := 0.0
## LADDER: the pelvis place and the two foot places, character space.
var hips_local := Vector3.ZERO
var feet_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## STAIRS: the pelvis height the legs allow, the two ankle targets (world), whether each foot is planted, and the profile that limits an unplanted ankle's reach.
var pelvis_height := 0.0
## The pelvis's sideways shift over the supporting foot (world, horizontal).
var pelvis_offset := Vector3.ZERO
## The smoothed floor under the pelvis (NAN: use the planner's height as it is).
var smooth_floor := NAN
var ankles_world: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var planted: Array[bool] = [false, false]
## How far each ankle is lifted above its flat-on-the-tread height (the heel coming up toward toe-off), metres.
var foot_lift: Array[float] = [0.0, 0.0]
var stair_profile: StairProfile

func clear() -> void:
	mode = Mode.NONE
	solved = false
	weight = 0.0
