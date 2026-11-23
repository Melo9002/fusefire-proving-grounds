class_name LadderBody
extends RefCounted
## What the ladder planner needs to know about a body, measured once from its skeleton at rest (CharacterRig.ladder_body) instead of assumed from MIRA's authored metres. Plain data: the planner
## (TraversalSolver, LadderKneePlanner) stays a pure function of it. Lengths in metres as the character is shown; vectors in the character's frame (x = left, y = up, z = forward), for the LEFT side
## (the right side mirrors x).

## Leg segments (hip joint to knee, knee to ankle) and arm segments (shoulder to elbow, elbow to wrist).
var thigh := 0.38
var shin := 0.38
var upper_arm := 0.23
var forearm := 0.23
## The left hip and shoulder joints relative to the hips bone, at rest.
var hip_offset := Vector3(0.094, -0.056, 0.006)
var shoulder_offset := Vector3(0.13, 0.35, 0.05)
## The ankle's height above the sole, and how far the ball of the foot is ahead of the ankle.
var ankle_height := 0.09
var ball_length := 0.113
## Height of the toe (ball) bone above the sole at rest: the ball of the foot's sole is this far below it.
var toe_height := 0.04
## How far the boot reaches ahead of the ankle (toe tip), MEASURED from the mesh: with the foot on a rung the toes go this far past it, so a wall nearer than that to the rungs is a wall the boot is in.
var foot_forward := 0.22
## How far BELOW the ankle bone the lowest point of the boot is (sole thickness included), MEASURED from the mesh at rest: a foot standing on a rung puts this much under the ankle, not the bare ankle height.
var sole_below_ankle := -1.0
## How much smaller or larger this body is than the one the profile's authored numbers were tuned for (RigBones.body_ratio).
var ratio := 1.0


func leg_length() -> float:
	return thigh + shin


func arm_length() -> float:
	return upper_arm + forearm


## Approximate volumes for clearance planning, from the body's own proportions (the reference body's thigh is about 0.085 m in radius, and so on). Not a collision model.
## Limb volume radii: MEASURED from the character's own mesh by CharacterRig.ladder_body() (the 90th percentile of the skinned vertices' distance from the bone), so a body with armor thicker or thinner than the
## reference gets its own. The defaults are the reference body's, scaled, and are what a body without a mesh keeps.
var measured_thigh := -1.0
var measured_shin := -1.0
var measured_knee := -1.0

func thigh_radius() -> float:
	if measured_thigh > 0.0:
		return measured_thigh
	return 0.085 * ratio


func shin_radius() -> float:
	if measured_shin > 0.0:
		return measured_shin
	return 0.060 * ratio


func knee_radius() -> float:
	if measured_knee > 0.0:
		return measured_knee
	return 0.070 * ratio


func torso_radius() -> float:
	return 0.115 * ratio


func hip_joint(hips: Vector3, side: int) -> Vector3:
	return hips + Vector3(hip_offset.x * (1.0 if side == 0 else -1.0), hip_offset.y, hip_offset.z)


func shoulder_joint(hips: Vector3, side: int) -> Vector3:
	return hips + Vector3(shoulder_offset.x * (1.0 if side == 0 else -1.0), shoulder_offset.y, shoulder_offset.z)


## The shoulder joint for a pelvis `hips` when the trunk is leaned forward `lean_degrees` (what the profile requests; the spine shares it, so the shoulders move `LEAN_GAIN` of it: measured on both bodies).
const LEAN_GAIN := 0.68

func shoulder_leaned(hips: Vector3, side: int, lean_degrees: float) -> Vector3:
	var angle := deg_to_rad(lean_degrees * LEAN_GAIN)
	var rest := shoulder_offset
	return hips + Vector3(rest.x * (1.0 if side == 0 else -1.0), rest.y * cos(angle), rest.z + rest.y * sin(angle))


## The ankle-to-sole distance a foot on a rung needs: the measured one when the rig measured it, the bare ankle height otherwise.
func sole_depth() -> float:
	return sole_below_ankle if sole_below_ankle > 0.0 else ankle_height


## How far behind the rung's axis the ankle stands: the arch of the foot over the bar (`share` of the ankle-to-ball length) unless the SHIN would then cross the bar. The shin's measured radius, the rung's
## and a small margin put the ankle at least that far behind, so a thick-armored shin keeps off the rung it stands behind. A body-derived rule: no number belongs to one character.
func ankle_behind(rung_radius: float, share: float) -> float:
	return maxf(ball_length * share, shin_radius() + rung_radius + 0.01)
