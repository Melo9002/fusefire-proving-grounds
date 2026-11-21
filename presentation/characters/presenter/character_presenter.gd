class_name CharacterPresenter
extends RefCounted
## The shared presentation state of one character (Task 04 contract, Task 07 package 2 foundation). It OWNS, for every context that drives a character:
##  * presentation time (`time`, advanced once per tick by the delta the engine hands the host: never scaled again),
##  * the reported velocity and the heading rate derived from it, and facing that follows the velocity,
##  * the "is it moving" decision that settles the gait to a stop,
##  * posture requests (`postures`, a PostureArbiter),
## and it exposes the persistent state as a PresentationIntent snapshot. It does NOT own animation mathematics: gait, cadence, bank and twist stay in CharacterRig, which this
## calls. It has no `_process`: the host node ticks it once per frame (see TRANSITION), so nothing can advance twice.
##
## TRANSITION (documented, not hidden): today UnitVisualAdapter and the workbench ARE the CharacterRig, so the presenter is a component of that node and bound to it, and the host
## calls `tick(delta)` from its own `_process`, in its existing order. When the rig is composed instead of inherited, the presenter becomes the node that ticks. Not yet owned
## here: attack/aim/cover/rescue sequencing, the traversal state, weapon readiness requests (the readiness object stays the rig's; the presenter only reads it), equipment changes.

var rig: CharacterRig
## Seconds of presentation time since the presenter was created. Read by attack timelines for their phase times.
var time := 0.0
## Frames on which tick() ran, and the engine frame of the latest tick: tests assert exactly one tick per frame.
var tick_count := 0
var last_tick_frame := -1
## The speed (m/s) and heading rate (rad/s) most recently reported; what the gait is fed while the character is moving.
var speed := 0.0
var heading_rate := 0.0
## The latest reported velocity, horizontal (world m/s); zero once the character settles.
var velocity := Vector3.ZERO
## Persistent posture requests: the cover policy (CONTEXT) and the rescue lift (ACTION) write here in production; tools write their own sources.
var postures := PostureArbiter.new()

var _age := 1.0
var _authority_known := false
var _authority_moving := false
var _scripted := false

## A character with no movement authority (tools, tests, a workbench) counts as moving for this long after its last report.
const UNAUTHORIZED_MOVING_SECONDS := 0.15

func _init(bound_rig: CharacterRig = null) -> void:
	rig = bound_rig

## The gameplay context's word for "this unit is moving right now" (a tactical unit knows when its route is being walked). Without it the presenter infers from reports.
func set_movement_authority(moving: bool) -> void:
	_authority_known = true
	_authority_moving = moving

func clear_movement_authority() -> void:
	_authority_known = false

## Scripted motion for a host that authors its own movement (the animation workbench's preview): the given speed and heading rate are fed to the gait EXACTLY as given every tick, including a
## heading rate while the speed is zero. It replaces the movement inference and any authority until cleared.
func set_scripted_motion(scripted_speed: float, scripted_heading_rate: float) -> void:
	_scripted = true
	speed = scripted_speed
	heading_rate = scripted_heading_rate

func clear_scripted_motion() -> void:
	_scripted = false

## The latest report of how the character is moving (world metres per second). Facing follows it: the character turns toward the velocity at `turn_speed_degrees`, and the heading rate
## that results (which banks the body into the turn) is remembered for the gait. A near-zero velocity changes nothing (the previous facing and report stand until tick() settles them).
func report_velocity(world_velocity: Vector3, delta: float, turn_speed_degrees: float) -> void:
	var flat := Vector3(world_velocity.x, 0.0, world_velocity.z)
	if flat.length_squared() < 0.000001 or not is_instance_valid(rig):
		return
	var desired_yaw := atan2(flat.x, flat.z)
	var yaw_before := rig.global_rotation.y
	rig.global_rotation.y = rotate_toward(rig.global_rotation.y, desired_yaw, deg_to_rad(turn_speed_degrees) * delta)
	speed = flat.length()
	velocity = flat
	_age = 0.0
	heading_rate = angle_difference(yaw_before, rig.global_rotation.y) / maxf(delta, 0.0001)

## Advances presentation by one frame. Call exactly once per frame, with the delta the engine gave the host's `_process` (already scaled by the engine; never scaled again).
## Feeds the rig's locomotion presentation unless something already fed it this frame (a tool or test driving the rig directly).
func tick(delta: float) -> void:
	time += delta
	tick_count += 1
	last_tick_frame = Engine.get_process_frames()
	if not is_instance_valid(rig) or rig.locomotion_fed_this_frame():
		return
	if _scripted:
		rig.update_locomotion_presentation(speed, heading_rate, delta)
		return
	_age += delta
	var moving := _authority_moving if _authority_known else _age < UNAUTHORIZED_MOVING_SECONDS
	rig.update_locomotion_presentation(speed if moving else 0.0, heading_rate if moving else 0.0, delta)
	if not moving:
		speed = 0.0
		heading_rate = 0.0
		velocity = Vector3.ZERO

## Resolves the persistent posture request (`postures`) and has the rig follow it for one frame. Call once per frame, after the host has set or released its requests. `drive_yaw` is false for a
## host that moves the body yaw itself. The rig does the posing; this only chooses what it should follow.
func apply_posture(delta: float, profile: CoverPostureProfile, drive_yaw := true) -> void:
	if is_instance_valid(rig):
		rig.apply_posture_target(postures.resolved_depth(), postures.resolved_yaw_offset(), delta, profile, drive_yaw, postures.resolved_kneel(), postures.resolved_exact())

## The persistent state as a snapshot. Velocity and yaw are derived from what the presenter reported and the rig shows, not stored twice; readiness is the rig's own WeaponReadiness.
func intent() -> PresentationIntent:
	var snapshot := PresentationIntent.new()
	if is_instance_valid(rig):
		snapshot.facing_yaw = rig.global_rotation.y
		snapshot.readiness = rig.readiness.requested()
		snapshot.equipment = PresentationTypes.EquipmentState.SLUNG if rig.is_weapon_stowed() else PresentationTypes.EquipmentState.HELD
	snapshot.velocity = velocity
	snapshot.facing_mode = PresentationTypes.FacingMode.FOLLOW_VELOCITY if speed > 0.0 else PresentationTypes.FacingMode.HOLD
	snapshot.posture = postures.resolved()
	snapshot.posture_yaw_offset = postures.resolved_yaw_offset()
	snapshot.posture_depth = postures.resolved_depth()
	return snapshot

## Releases everything the presenter holds: no posture request outlives the character.
func teardown() -> void:
	postures.teardown()
	speed = 0.0
	heading_rate = 0.0
	velocity = Vector3.ZERO
	_authority_known = false
	_scripted = false
