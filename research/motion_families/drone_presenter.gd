class_name DronePresenter
extends MotionPresenter
## Task 13 example: a flying drone's presentation. It uses the FULL 3D velocity (it climbs and descends: the vertical speed drives the rotors and is never flattened), shows an orientation request independently of the
## travel direction (a visual yaw offset from the authoritative heading), leans into the horizontal travel (pitch for forward speed, bank for sideways speed) with eased rates, hovers with a small bob when nearly still
## and returns to neutral when the motion stops. It has one one-shot action, a hit reaction (a decaying wobble), through the shared ActionHandle lifecycle; crouching and ladders are not supported and are refused.
##
## AUTHORITY. Yaw offset, tilt and bob are written to the presentation's own `visual` nodes only. The entity's authoritative transform is the context's: it arrives as a value and is never written. Nothing here is flight
## mechanics (no thrust, no controller): it only shows a body that the context already moved.

## `visual` is the root of the presentation (a child of the entity); `tilt_pivot` is the body that pitches and banks under it; `rotors` spin about their own Y.
var visual: Node3D
var tilt_pivot: Node3D
var rotors: Array[Node3D] = []
var max_tilt_degrees := 24.0
var tilt_degrees_per_mps := 4.0
var tilt_rate_degrees := 140.0
var yaw_rate_degrees := 200.0
var rotor_idle_rev_per_second := 18.0
var rotor_climb_rev_per_second := 6.0
const HOVER_SPEED := 0.2
const HOVER_BOB := 0.03

## The presented state: the visual yaw OFFSET from the authoritative heading, pitch (positive nose up) and bank (positive right side down), in radians, and the rotor rate in revolutions per second.
var yaw_offset := 0.0
var pitch := 0.0
var bank := 0.0
var rotor_rate := 0.0
var _rotor_phase := 0.0
var _wobble_age := -1.0
const WOBBLE_DEGREES := 14.0
const WOBBLE_HZ := 7.0
const WOBBLE_DECAY := 5.0

func family() -> StringName:
	return &"drone"

func _capabilities() -> Array[StringName]:
	return [MOTION, FACING, REACTION]

func _present(request: MotionRequest) -> void:
	var dt := request.delta
	var basis := request.transform.basis.orthonormalized()
	var authority_yaw := atan2(basis.z.x, basis.z.z)
	# Orientation: independent of where the drone is going. A request with no yaw to show keeps what is shown.
	var wanted := request.requested_yaw()
	if not is_nan(wanted):
		var goal := angle_difference(authority_yaw, wanted)
		yaw_offset = rotate_toward(yaw_offset, goal, deg_to_rad(yaw_rate_degrees) * dt)
	# Lean into the horizontal travel, in the drone's own (visual) frame.
	var shown_yaw := authority_yaw + yaw_offset
	var forward := Vector3(sin(shown_yaw), 0.0, cos(shown_yaw))
	var left := Vector3(cos(shown_yaw), 0.0, -sin(shown_yaw))
	var horizontal := request.horizontal_velocity()
	var limit := deg_to_rad(max_tilt_degrees)
	var pitch_goal := clampf(-horizontal.dot(forward) * deg_to_rad(tilt_degrees_per_mps), -limit, limit)   # travelling forward lowers the nose
	var bank_goal := clampf(-horizontal.dot(left) * deg_to_rad(tilt_degrees_per_mps), -limit, limit)      # travelling left lowers the left side
	var step := deg_to_rad(tilt_rate_degrees) * dt
	pitch = move_toward(pitch, pitch_goal, step)
	bank = move_toward(bank, bank_goal, step)
	var wobble := 0.0
	if _wobble_age >= 0.0:
		_wobble_age += dt
		wobble = deg_to_rad(WOBBLE_DEGREES) * exp(-WOBBLE_DECAY * _wobble_age) * sin(TAU * WOBBLE_HZ * _wobble_age)
	if is_instance_valid(visual):
		visual.rotation.y = yaw_offset
		var hovering := request.velocity.length() < HOVER_SPEED
		visual.position.y = sin(TAU * 0.8 * time) * HOVER_BOB if hovering else 0.0
	if is_instance_valid(tilt_pivot):
		tilt_pivot.rotation.x = -pitch   # nose up is positive pitch; a positive rotation about X lowers the nose
		tilt_pivot.rotation.z = bank + wobble
	# Rotors: faster when climbing, slower when descending, from the vertical velocity the context supplied.
	rotor_rate = maxf(rotor_idle_rev_per_second + request.vertical_speed() * rotor_climb_rev_per_second, 2.0)
	_rotor_phase = fposmod(_rotor_phase + rotor_rate * TAU * dt, TAU)
	for index in rotors.size():
		rotors[index].rotation.y = _rotor_phase * (1.0 if index % 2 == 0 else -1.0)

func _begin_action(action: StringName, _seconds: float) -> void:
	if action == ACTION_REACTION:
		_wobble_age = 0.0

func _end_action(_outcome: PresentationTypes.Outcome) -> void:
	_wobble_age = -1.0

## Returns the presentation to its neutral state (level, facing the entity's own heading, no bob). The entity itself is untouched.
func _teardown() -> void:
	reset_neutral()

func reset_neutral() -> void:
	yaw_offset = 0.0
	pitch = 0.0
	bank = 0.0
	_wobble_age = -1.0
	if is_instance_valid(visual):
		visual.rotation.y = 0.0
		visual.position.y = 0.0
	if is_instance_valid(tilt_pivot):
		tilt_pivot.rotation = Vector3.ZERO

func _snapshot_extra() -> Dictionary:
	return {"yaw_offset_deg": rad_to_deg(yaw_offset), "pitch_deg": rad_to_deg(pitch), "bank_deg": rad_to_deg(bank), "rotor_rps": rotor_rate}
