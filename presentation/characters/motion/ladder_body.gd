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
## How much smaller or larger this body is than the one the profile's authored numbers were tuned for (RigBones.body_ratio).
var ratio := 1.0


func leg_length() -> float:
	return thigh + shin


func arm_length() -> float:
	return upper_arm + forearm


## Approximate volumes for clearance planning, from the body's own proportions (the reference body's thigh is about 0.085 m in radius, and so on). Not a collision model.
func thigh_radius() -> float:
	return 0.085 * ratio


func shin_radius() -> float:
	return 0.060 * ratio


func knee_radius() -> float:
	return 0.070 * ratio


func torso_radius() -> float:
	return 0.115 * ratio


func hip_joint(hips: Vector3, side: int) -> Vector3:
	return hips + Vector3(hip_offset.x * (1.0 if side == 0 else -1.0), hip_offset.y, hip_offset.z)


func shoulder_joint(hips: Vector3, side: int) -> Vector3:
	return hips + Vector3(shoulder_offset.x * (1.0 if side == 0 else -1.0), shoulder_offset.y, shoulder_offset.z)
