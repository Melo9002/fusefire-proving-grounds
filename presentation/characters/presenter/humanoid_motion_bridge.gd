class_name HumanoidMotionBridge
extends MotionPresenter
## The humanoid family's side of the cross-family motion contract (Task 13): a thin, OPT-IN adapter that lets a context speak MotionRequest to the existing CharacterPresenter. It translates and delegates; it duplicates
## nothing. The humanoid runtime (CharacterRig, the presenter's gait, postures, holds, contacts) is unchanged and nothing in it knows this class, so a context that calls the presenter directly (every current host) pays
## nothing for the contract's existence.
##
## What a humanoid does with a request: its horizontal velocity feeds the gait and facing (the presenter flattens it, since a humanoid walks on the ground; the vertical component stays visible in the snapshot but is
## not presented); the facing modes map to the presenter's own face_yaw, face_point, hold_facing and follow-velocity; the presenter is ticked once, after the motion, exactly as a host does. A context that uses the bridge
## therefore does not also tick the presenter itself. Posture, aiming, traversal and the rest stay on the presenter's own API: this bridge only says (supports) that the family has them.

var _reaction: ActionHandle
var presenter: CharacterPresenter
## How fast the body turns toward its velocity (degrees per second), as in the hosts.
var turn_speed_degrees := 360.0

func _init(p_presenter: CharacterPresenter = null) -> void:
	presenter = p_presenter

func family() -> StringName:
	return &"humanoid"

func _capabilities() -> Array[StringName]:
	return [MOTION, FACING, REACTION, POSTURE, AIMING, TRAVERSAL]

func _present(request: MotionRequest) -> void:
	if not is_instance_valid(presenter.rig):
		presenter.tick(request.delta)
		return
	match request.facing_mode:
		PresentationTypes.FacingMode.HOLD:
			presenter.hold_facing()
		PresentationTypes.FacingMode.FACE_YAW:
			presenter.release_facing_hold()
			presenter.face_yaw(request.facing_yaw)
			presenter.hold_facing()   # an explicit facing wins over the velocity: the body moves without turning toward it
		PresentationTypes.FacingMode.FACE_POINT:
			presenter.release_facing_hold()
			presenter.face_point(request.facing_point)
			presenter.hold_facing()
		PresentationTypes.FacingMode.FOLLOW_VELOCITY:
			presenter.release_facing_hold()
	if request.horizontal_speed() > 0.05:
		presenter.report_velocity(request.velocity, request.delta, turn_speed_degrees)
	presenter.tick(request.delta)
	time = presenter.time   # the presenter's clock IS the humanoid's presentation time: the bridge keeps no second one

## A hit reaction is the presenter's own reaction-rank hold (its handle, its outcomes), not a second lifecycle: the same shape as the workbench's and the exploration host's reaction (the hit clip, then back to idle).
func request_action(action: StringName, seconds := 0.0) -> ActionHandle:
	if is_closed(): return ActionHandle.settled(PresentationTypes.Outcome.CANCELLED)
	if action != ACTION_REACTION or not is_instance_valid(presenter.rig):
		return super(action, seconds)
	var rig := presenter.rig
	var hold := presenter.begin_hold(seconds, func() -> void: rig.animation_controller.play(&"rifle_idle"), PresentationTypes.HOLD_REACTION)
	if not hold.is_done():
		rig.animation_controller.play(&"hit")
	_reaction = hold
	return hold

func _teardown() -> void:
	if _reaction != null and not _reaction.is_done():
		presenter.cancel_hold()
	_reaction = null

func _snapshot_extra() -> Dictionary:
	return {"time": presenter.time, "frames": presenter.tick_count, "presenter_speed": presenter.speed, "facing_yaw_deg": rad_to_deg(presenter.rig.global_rotation.y) if is_instance_valid(presenter.rig) else 0.0}
