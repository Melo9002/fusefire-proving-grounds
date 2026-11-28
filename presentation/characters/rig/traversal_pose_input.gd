class_name TraversalPoseInput
extends RefCounted
## The traversal pose the body should show this frame (Task 07 package 4), as typed data: what TraversalPoseModifier applies to the pelvis and the leg IK. CharacterRig publishes it whenever
## the traversal or stair pose changes (the solved pose itself is TraversalSolver / StairFootPlanner output; the rig translates it), and the modifier reads nothing else of the rig.
## Ladder values are in the character's own frame (the modifier converts them with the character root of THIS pass); stair values are the planner's world-space results.

enum Mode { NONE, LADDER, STAIRS, LOCAL_STEP, GROUND }

var mode: Mode = Mode.NONE
## False while a ladder traversal is active but its pose has not been solved yet (nothing to apply).
var solved := false
var weight := 0.0
## LADDER: seconds of the hand-over back to the animation still to run after the traversal ended mid-climb (0 = none). The rig starts it in `end_traversal`; the modifier counts it down while it scales `weight` by what is left, so the body
## eases out of the climbing pose instead of jumping (issue 67: 44 cm in one frame when a climb was interrupted).
var release_left := 0.0
var release_total := 0.0
## True from `end_traversal` until the ease-out is done; the rig's simulation clock advances it (CharacterRig.advance_traversal_release). `end_traversal` only starts it when a presenter is ticking.
var releasing := false
## The simulation's own delta of the last presenter tick and the frame it came in (CharacterRig.advance_traversal_release). The knee turn rate runs on it, not on the engine's frame time, so a fixed-step run is exactly repeatable (the modifier's own delta is real time).
var sim_delta := 0.0
var sim_frame := -100
## LADDER: the pelvis place and the two foot places, character space.
var hips_local := Vector3.ZERO
var feet_local: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
## LADDER: the ladder and the body the legs are planned against, and how far the floor is above the ladder's bottom (the knee planner needs them to keep the legs off the rungs).
var ladder_geometry: LadderGeometry
var ladder_body: LadderBody
var floor_level := 0.0
## The host's verified landing at the top (null: none): the deck is an obstacle for the legs.
var landing: LadderLanding
var deck_planted: Array[bool] = [false, false]
var deck_levelling: Array[float] = [0.0, 0.0]
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
## Requested visual pelvis drop; still bounded by the same planted legs.
var stair_crouch := 0.0

## GROUND: the host's way of asking what ground lies under a world point (Callable(Vector3) -> Dictionary {y, normal}, empty when there is none), whether the character stands on it, the ankle's height above the sole
## (the foot's own measure), and what the modifier solved this pass: the eased weight, each ankle's shift, the ground normal under each foot, the animated foot orientation to tilt from, and how far each foot is
## lifted off the ground by the gait (a planted foot is turned to the slope, a lifted one keeps the animation's pitch).
var ground_sampler := Callable()
var ground_contact := true
var ground_ankle_height := 0.08
var ground_weight := 0.0
var ground_shift: Array[float] = [0.0, 0.0]
var ground_normal: Array[Vector3] = [Vector3.UP, Vector3.UP]
var ground_pelvis := 0.0
var ground_lift: Array[float] = [0.0, 0.0]
var foot_world_basis: Array[Basis] = [Basis.IDENTITY, Basis.IDENTITY]


func clear() -> void:
	release_left = 0.0
	releasing = false
	mode = Mode.NONE
	solved = false
	weight = 0.0
