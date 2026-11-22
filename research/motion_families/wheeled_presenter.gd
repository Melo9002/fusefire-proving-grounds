class_name WheeledPresenter
extends MotionPresenter
## Task 13 example: a wheeled platform's presentation. It receives a MotionRequest and shows what the OBSERVED motion implies: the wheels spin by the distance the body actually travelled along its own forward axis
## (ground speed over radius), the front wheels steer by the curvature the body is actually following (its observed turn rate against its ground speed), and everything eases to rest when the platform stops. It decides nothing about travel: the
## authoritative transform and velocity come from the context, and this writes only to its own `visual` subtree. It has no one-shot actions (none are fabricated: a reaction request is refused) and no posture, aiming
## or traversal. Not here: vehicle physics, suspension, slip, tracks (a tracked platform would scroll a track from the same observed forward speed instead of spinning wheels).

var wheels: Array[Node3D] = []
var steer_pivots: Array[Node3D] = []
var wheel_radius := 0.3
## The distance between the axles (metres): with the observed turn rate and ground speed it gives the steering angle a bicycle-model body would need (a visual estimate, not a vehicle simulation).
var wheelbase := 1.4
var max_steer_degrees := 35.0
var steer_rate_degrees := 240.0
## Accumulated wheel rotation (radians), the current wheel angular rate (rad/s) and the front wheels' steering angle (radians, positive to the left).
var spin := 0.0
var spin_rate := 0.0
var steer := 0.0
var _last_yaw := NAN

func family() -> StringName:
	return &"wheeled"

func _capabilities() -> Array[StringName]:
	return [MOTION]

func _present(request: MotionRequest) -> void:
	var basis := request.transform.basis.orthonormalized()
	var forward := basis.z
	# Ground speed along the body's own forward axis, from the ACTUAL velocity (a slope's vertical part is included, since the wheel rolls along the surface).
	var along := request.velocity.dot(forward)
	spin_rate = along / maxf(wheel_radius, 0.01)
	spin = fposmod(spin + spin_rate * request.delta, TAU)
	for wheel in wheels:
		wheel.rotation.x = spin
	var yaw := atan2(forward.x, forward.z)
	var turn_rate := 0.0 if is_nan(_last_yaw) or request.delta <= 0.0 else angle_difference(_last_yaw, yaw) / request.delta
	_last_yaw = yaw
	var target := 0.0
	if absf(along) > 0.2:
		target = clampf(atan2(wheelbase * turn_rate, absf(along)) * signf(along), -deg_to_rad(max_steer_degrees), deg_to_rad(max_steer_degrees))
	steer = move_toward(steer, target, deg_to_rad(steer_rate_degrees) * request.delta)
	for pivot in steer_pivots:
		pivot.rotation.y = steer

func _snapshot_extra() -> Dictionary:
	return {"wheel_rate": spin_rate, "wheel_rpm": spin_rate / TAU * 60.0, "steer_deg": rad_to_deg(steer)}
