class_name MotionRequest
extends RefCounted
## What a gameplay or exploration CONTEXT tells a presentation family about one entity's motion this frame: the cross-family boundary (Task 13). It describes motion and orientation requests; it does not say how a body
## achieves them (legs, wheels, rotors) and it grants the presentation no authority: every field is data the context already decided, and the authoritative transform is passed as a VALUE, so a presenter holds no
## reference through which it could move the entity.
##
## FRAME CONVENTIONS (the same as the humanoid presenter's, stated once). World space is Godot's: +Y up, right-handed. Yaw is a rotation about +Y in radians and +Z is forward at yaw zero (a heading of `atan2(x, z)`).
## For an entity's own frame, forward is its +Z, up its +Y and right its -X (Godot's basis.x is the entity's LEFT in this project's convention: the humanoid faces +Z with its right toward -X). Pitch is positive nose UP and
## bank (roll) is positive right side DOWN. Velocities are world metres per second, with the vertical component kept: a family that does not use it ignores it, the contract never discards it.

## The frame's length in seconds of presentation time, already scaled by the engine. A family advances its clock by exactly this, once per request.
var delta := 0.0
## The host's frame number for this request, or -1 when it has none. A family counts two requests with the same number as a duplicate advance of time (a diagnostic, not an error).
var frame_id := -1
## The entity's ACTUAL world velocity this frame (what really happened, as the authority resolved it).
var velocity := Vector3.ZERO
## What the context WANTED this frame when that differs from what happened (a blocked step, a slowed stair segment). Meaningful only when `has_intent`.
var intended_velocity := Vector3.ZERO
var has_intent := false
## The authoritative world transform of the entity, read-only to the presentation: used to relate requests to the entity's own frame. Never written back.
var transform := Transform3D.IDENTITY
## How the entity should be oriented. Reuses the existing vocabulary: FOLLOW_VELOCITY, FACE_POINT, FACE_YAW, HOLD (keep what you show). A family says whether it can honour a mode; it never invents one.
var facing_mode: PresentationTypes.FacingMode = PresentationTypes.FacingMode.HOLD
var facing_yaw := 0.0
var facing_point := Vector3.ZERO

static func make(p_delta: float, p_velocity: Vector3, p_transform := Transform3D.IDENTITY, p_frame_id := -1) -> MotionRequest:
	var request := MotionRequest.new()
	request.delta = p_delta
	request.velocity = p_velocity
	request.transform = p_transform
	request.frame_id = p_frame_id
	return request

func with_intent(wanted: Vector3) -> MotionRequest:
	intended_velocity = wanted
	has_intent = true
	return self

func facing_toward_velocity() -> MotionRequest:
	facing_mode = PresentationTypes.FacingMode.FOLLOW_VELOCITY
	return self

func facing_yaw_of(yaw: float) -> MotionRequest:
	facing_mode = PresentationTypes.FacingMode.FACE_YAW
	facing_yaw = yaw
	return self

func facing_world_point(point: Vector3) -> MotionRequest:
	facing_mode = PresentationTypes.FacingMode.FACE_POINT
	facing_point = point
	return self

func horizontal_velocity() -> Vector3:
	return Vector3(velocity.x, 0.0, velocity.z)

func horizontal_speed() -> float:
	return horizontal_velocity().length()

func vertical_speed() -> float:
	return velocity.y

func speed() -> float:
	return velocity.length()

func is_moving(threshold := 0.05) -> bool:
	return velocity.length() > threshold

## The yaw the request asks the entity to show, or NAN when it asks for none (HOLD, or FOLLOW_VELOCITY while there is no horizontal motion to follow).
func requested_yaw() -> float:
	match facing_mode:
		PresentationTypes.FacingMode.FACE_YAW:
			return facing_yaw
		PresentationTypes.FacingMode.FACE_POINT:
			var flat := facing_point - transform.origin
			flat.y = 0.0
			return atan2(flat.x, flat.z) if flat.length_squared() > 0.0001 else NAN
		PresentationTypes.FacingMode.FOLLOW_VELOCITY:
			var along := horizontal_velocity()
			return atan2(along.x, along.z) if along.length_squared() > 0.000001 else NAN
	return NAN
