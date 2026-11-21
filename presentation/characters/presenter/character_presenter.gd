class_name CharacterPresenter
extends RefCounted
## The shared presentation state of one character (Task 04 contract, Task 07 package 2 foundation). It OWNS, for every context that drives a character:
##  * presentation time (`time`, advanced once per tick by the delta the engine hands the host: never scaled again),
##  * the reported velocity and the heading rate derived from it, and facing that follows the velocity,
##  * the "is it moving" decision that settles the gait to a stop,
##  * posture requests (`postures`, a PostureArbiter),
## the attack lifecycle (`attack`), the persistent aim hold (`aim`), the timed hold of a finite state such as a hit (`begin_hold`), the defeat (`begin_defeat`) and the advance of the rescue clock, all
## settled through ActionHandles and all advanced here, once per frame, and it exposes the persistent state as a PresentationIntent snapshot. It does NOT own animation mathematics: gait, cadence, bank and twist stay in CharacterRig, which this
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
## The attack lifecycle (RAISE, ALIGN, FIRE, RECOVER, RELEASE): the only clock of an attack. The context supplies an AttackHost; the sequence settles an AttackHandle.
var attack := AttackSequence.new()
## The committed Aim's persistent mirror (never a handle).
var aim := AimHold.new()

## How the character's yaw is being decided (the vocabulary of the Task 04 contract). FOLLOW_VELOCITY while it walks, FACE_POINT / FACE_YAW after a facing request, FACE_YAW with `authority_yaw` set when gameplay
## supplied the value, HOLD while facing is held. A request of any kind replaces the previous one.
var facing_mode := PresentationTypes.FacingMode.HOLD
## The latest yaw gameplay authority supplied (radians, the rig node's yaw), valid while `has_authority_yaw`.
var authority_yaw := 0.0
var has_authority_yaw := false
var _facing_hold := false
## The committed Aim, as the context reports it (typed input; this presenter never reads a tactical type), and the clip states in which a held Aim may re-settle the pose.
var aim_committed := false
var aim_settling_states: Array[StringName] = []
## The held Aim engaged or ended. `settling` says the character was in a quiet state a held Aim may change; the context re-settles its pose then.
signal aim_hold_changed(transition: AimHold.Transition, settling: bool)

## A rescue pickup that has to wait for its carrier to arrive (the lift is shown on arrival), with the handle reserved for it.
class PendingPickup extends RefCounted:
	var world := Vector3.INF
	var lying_basis: Variant = null
	var handle: ActionHandle
var _pending_pickup: PendingPickup

var _removal_left := -1.0
var _removal_handle: ActionHandle
var _removal_armed_frame := -1
var _hold_left := -1.0
var _hold_due: Callable
var _hold_handle: ActionHandle
var _hold_armed_frame := -1
var _defeat_left := -1.0
var _defeat_handle: ActionHandle
var _defeat_armed_frame := -1
var _actions_frame := -1

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
	speed = flat.length()
	velocity = flat
	_age = 0.0
	if _facing_hold:
		heading_rate = 0.0   # facing is held: the character still moves, it does not turn toward its velocity
		return
	var desired_yaw := atan2(flat.x, flat.z)
	var yaw_before := rig.global_rotation.y
	rig.global_rotation.y = rotate_toward(rig.global_rotation.y, desired_yaw, deg_to_rad(turn_speed_degrees) * delta)
	facing_mode = PresentationTypes.FacingMode.FOLLOW_VELOCITY
	has_authority_yaw = false
	heading_rate = angle_difference(yaw_before, rig.global_rotation.y) / maxf(delta, 0.0001)

## FACING. A change of facing that arrives at once (a shot's target, a cover pose's wall, a committed direction): the node turns now, and the body either absorbs the change into its cover yaw (`absorb_into_cover`,
## which the context decides: the unit is in cover and standing still) so nothing snaps, or shows the hips catching up (`begin_turn`, past one degree). `yaw` is the node's own yaw (radians about the vertical,
## +Z forward). The rig applies; nothing else writes facing.
func face_yaw(yaw: float, absorb_into_cover := false, show_turn := true) -> void:
	if not is_instance_valid(rig):
		return
	var before := rig.rotation.y
	rig.apply_facing_yaw(yaw)
	var change := angle_difference(before, rig.rotation.y)
	if absorb_into_cover:
		rig.absorb_facing_change(change)
	elif show_turn and absf(change) > deg_to_rad(1.0):
		rig.begin_turn(change)
	facing_mode = PresentationTypes.FacingMode.HOLD if _facing_hold else PresentationTypes.FacingMode.FACE_YAW
	has_authority_yaw = false

## Faces a world point (horizontally). A point on the character's own vertical axis changes nothing.
func face_point(world_point: Vector3, absorb_into_cover := false) -> void:
	if not is_instance_valid(rig):
		return
	var flat := world_point - rig.global_position
	flat.y = 0.0
	if flat.length_squared() <= 0.0001:
		return
	face_yaw(atan2(flat.x, flat.z), absorb_into_cover)
	facing_mode = PresentationTypes.FacingMode.HOLD if _facing_hold else PresentationTypes.FacingMode.FACE_POINT

## A facing that gameplay authority committed (an explicit direction a rule depends on): shown exactly as supplied, and reported as such (`has_authority_yaw`, `authority_yaw`, FACE_YAW). The presenter never
## derives it and never changes it; a later facing request of any kind replaces it, exactly as a later visual facing replaces any other.
func face_authoritative(yaw: float, absorb_into_cover := false) -> void:
	face_yaw(yaw, absorb_into_cover)
	authority_yaw = yaw
	has_authority_yaw = true

## Eased turn of the node toward `yaw` at `degrees_per_second` (a ladder's heading). Call every frame it should turn.
func turn_toward_yaw(yaw: float, degrees_per_second: float, delta: float) -> void:
	if not is_instance_valid(rig):
		return
	rig.apply_facing_yaw(rotate_toward(rig.rotation.y, yaw, deg_to_rad(degrees_per_second) * delta))
	facing_mode = PresentationTypes.FacingMode.FACE_YAW
	has_authority_yaw = false

## Eased turn of the VISUAL ROOT toward `yaw` (an authored preview turn in the workbench): returns the heading rate this frame, which the caller feeds to the gait as scripted motion.
func turn_root_toward(yaw: float, degrees_per_second: float, delta: float) -> float:
	if not is_instance_valid(rig) or not is_instance_valid(rig.character_root):
		return 0.0
	var before := rig.character_root.rotation.y
	rig.apply_root_yaw(rotate_toward(before, yaw, deg_to_rad(degrees_per_second) * delta))
	return angle_difference(before, rig.character_root.rotation.y) / maxf(delta, 0.0001)

## Keeps the facing where it is: the character still moves, it does not turn toward its velocity, until the hold is released.
func hold_facing() -> void:
	_facing_hold = true
	facing_mode = PresentationTypes.FacingMode.HOLD

func release_facing_hold() -> void:
	_facing_hold = false

func is_facing_held() -> bool:
	return _facing_hold

## The direction the character faces now (horizontal, unit length), for a reader that must not reach into the rig (a replay camera's focus point). Read-only.
func facing_direction() -> Vector3:
	if not is_instance_valid(rig):
		return Vector3.FORWARD
	var forward := rig.global_basis.z
	forward.y = 0.0
	return forward.normalized() if forward.length_squared() > 0.000001 else Vector3.FORWARD

## Advances presentation by one frame. Call exactly once per frame, with the delta the engine gave the host's `_process` (already scaled by the engine; never scaled again).
## Feeds the rig's locomotion presentation unless something already fed it this frame (a tool or test driving the rig directly).
func tick(delta: float) -> void:
	time += delta
	tick_count += 1
	last_tick_frame = Engine.get_process_frames()
	_advance_timed_states(delta)
	_advance_aim_hold(delta)
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

## Starts a finite state that holds for `seconds` of presentation time and then runs `due` (a hit reaction returning to idle, a pickup's clip returning to idle). It replaces a scene-tree timer: the
## countdown runs in tick(), so it follows the engine's own delta and pauses with the character. One hold at a time: a new one (or cancel_hold) ends the previous with INTERRUPTED. The handle
## settles COMPLETED after `due` has run, INTERRUPTED if the hold was superseded or the character removed.
func begin_hold(seconds: float, due: Callable) -> ActionHandle:
	cancel_hold()
	_hold_left = maxf(seconds, 0.0)
	_hold_due = due
	_hold_armed_frame = Engine.get_process_frames()
	_hold_handle = ActionHandle.new()
	return _hold_handle

## Ends a running hold (a newer presentation took over). A no-op when none runs.
func cancel_hold() -> void:
	var handle := _hold_handle
	_hold_handle = null
	_hold_left = -1.0
	_hold_due = Callable()
	if handle != null:
		handle.settle(PresentationTypes.Outcome.INTERRUPTED)

func is_holding() -> bool:
	return _hold_handle != null

## A defeat: the one-shot defeat clip runs for `seconds` and its end state stays. Everything else the character was presenting is ended by the caller (see UnitVisualAdapter.present_defeat); this only
## settles the defeat itself. A repeated request while the clip is still running is the same defeat (the same handle, no restart).
func begin_defeat(seconds: float) -> ActionHandle:
	if _defeat_handle != null:
		return _defeat_handle   # the same defeat, running or finished: a repeat never restarts it
	_defeat_left = maxf(seconds, 0.0)
	_defeat_armed_frame = Engine.get_process_frames()
	_defeat_handle = ActionHandle.new()
	return _defeat_handle

## True from the first defeat request on: defeat is terminal (Task 04 precedence: it outranks every other presentation request, which are then refused).
func is_defeated() -> bool:
	return _defeat_handle != null

## True while the defeat clip is still running.
func is_defeating() -> bool:
	return _defeat_handle != null and not _defeat_handle.is_done()

## The tactical layer removes a defeated character once its defeat has been readable. The handle settles when the defeat clip has finished AND at least `minimum_seconds` of presentation time have passed since
## this request, whichever is later; INTERRUPTED if the character is removed first. One request at a time (a repeat returns the same handle).
func removal_handle(minimum_seconds: float) -> ActionHandle:
	if _removal_handle != null:
		return _removal_handle
	_removal_left = maxf(minimum_seconds, 0.0)
	_removal_armed_frame = Engine.get_process_frames()
	_removal_handle = ActionHandle.new()
	return _removal_handle

## PENDING PICKUP. A rescue decided while the carrier's body is still walking to the rescued character is held here until the carrier arrives, with the handle reserved for it (the rig settles that handle once
## the lift runs). `arrive_pickup` hands the held request to `begin` (the context starts the lift) and forgets it. Cancelling it, a defeat or a teardown settles the reserved handle: nothing waits forever.
func hold_pickup(world: Vector3, lying_basis: Variant) -> ActionHandle:
	if _pending_pickup != null and not _pending_pickup.handle.is_done():
		_pending_pickup.world = world
		_pending_pickup.lying_basis = lying_basis
		return _pending_pickup.handle
	var pending := PendingPickup.new()
	pending.world = world
	pending.lying_basis = lying_basis
	pending.handle = rig.reserve_rescue_handle()
	pending.handle.finished.connect(_on_pending_pickup_settled.bind(pending), CONNECT_ONE_SHOT)
	_pending_pickup = pending
	return pending.handle

func has_pending_pickup() -> bool:
	return _pending_pickup != null

## The carrier arrived: the held pickup is handed to `begin(world, lying_basis)` and forgotten (the lift it starts takes the reserved handle over). Returns false when nothing was held.
func arrive_pickup(begin: Callable) -> bool:
	var pending := _pending_pickup
	if pending == null:
		return false
	_pending_pickup = null
	begin.call(pending.world, pending.lying_basis)
	return true

## The held pickup will not happen (the carrier fell, boarded, was freed, the requester cancelled): it is forgotten and its handle is settled with `outcome` unless a lift already took it over.
func cancel_pending_pickup(outcome: PresentationTypes.Outcome) -> void:
	var pending := _pending_pickup
	_pending_pickup = null
	if pending != null and not pending.handle.is_done() and not (is_instance_valid(rig) and rig.interaction_active()):
		pending.handle.settle(outcome)

func _on_pending_pickup_settled(outcome: PresentationTypes.Outcome, pending: PendingPickup) -> void:
	if pending == _pending_pickup and outcome == PresentationTypes.Outcome.CANCELLED:
		_pending_pickup = null   # the requester withdrew it: it is not started on arrival

## The committed Aim's per-frame progression: the context reports whether the Aim is still committed (`aim_committed`), and the hold engages, stays through its grace period and releases here. It reads the
## character's current clip state to know whether a quiet pose may be re-settled; what a transition does to the pose is the context's (`aim_hold_changed`).
func _advance_aim_hold(delta: float) -> void:
	var controller: Object = rig.animation_controller if is_instance_valid(rig) else null
	var settling: bool = controller != null and is_instance_valid(controller) and StringName(controller.current_state) in aim_settling_states
	var transition := aim.update(delta, aim_committed, settling)
	if transition != AimHold.Transition.NONE:
		aim_hold_changed.emit(transition, settling)

## A timed state counts down from the FRAME AFTER it was begun, as the scene-tree timers it replaces did: the frame it starts in is not part of its time, whichever node began it.
func _advance_timed_states(delta: float) -> void:
	var frame := Engine.get_process_frames()
	if _hold_handle != null and frame != _hold_armed_frame:
		_hold_left -= delta
		if _hold_left <= 0.0:
			var handle := _hold_handle
			var due := _hold_due
			_hold_handle = null   # the slot is clear before `due` runs: it may start the next hold or cancel nothing
			_hold_left = -1.0
			_hold_due = Callable()
			if due.is_valid():
				due.call()
			handle.settle(PresentationTypes.Outcome.COMPLETED)
	if _defeat_handle != null and not _defeat_handle.is_done() and frame != _defeat_armed_frame:
		_defeat_left -= delta
		if _defeat_left <= 0.0:
			_defeat_left = -1.0
			_defeat_handle.settle(PresentationTypes.Outcome.COMPLETED)   # the handle stays: a defeat that finished is still the defeat
	if _removal_handle != null and not _removal_handle.is_done() and frame != _removal_armed_frame:
		_removal_left -= delta
		if _removal_left <= 0.0 and (_defeat_handle == null or _defeat_handle.is_done()):
			_removal_handle.settle(PresentationTypes.Outcome.COMPLETED)

## The action stage of a frame: the attack moves on, and the rescue clock advances (the rig applies what it says; see CharacterRig.advance_rescue_clock). Call once per frame, after readiness and
## posture have been followed and before the weapon-pose update that applies the results. Both hosts (the tactical adapter and the workbench) call it from the same place in their update; a second call
## in the same engine frame does nothing, so nothing can advance twice.
func advance_actions(delta: float) -> void:
	var frame := Engine.get_process_frames()
	if frame == _actions_frame:
		return
	_actions_frame = frame
	attack.advance(delta, time)
	if is_instance_valid(rig):
		rig.advance_rescue_clock(delta)

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
	if _facing_hold:
		snapshot.facing_mode = PresentationTypes.FacingMode.HOLD
	elif facing_mode == PresentationTypes.FacingMode.FACE_POINT or facing_mode == PresentationTypes.FacingMode.FACE_YAW:
		snapshot.facing_mode = facing_mode
	else:
		snapshot.facing_mode = PresentationTypes.FacingMode.FOLLOW_VELOCITY if speed > 0.0 else PresentationTypes.FacingMode.HOLD
	snapshot.posture = postures.resolved()
	snapshot.posture_yaw_offset = postures.resolved_yaw_offset()
	snapshot.posture_depth = postures.resolved_depth()
	return snapshot

## Releases everything the presenter holds: no posture request outlives the character.
func teardown() -> void:
	attack.cancel()
	aim.clear()
	cancel_hold()
	cancel_pending_pickup(PresentationTypes.Outcome.INTERRUPTED)
	if _defeat_handle != null:
		var defeat := _defeat_handle
		_defeat_handle = null
		_defeat_left = -1.0
		defeat.settle(PresentationTypes.Outcome.INTERRUPTED)   # a no-op when the defeat had finished
	if _removal_handle != null:
		var removal := _removal_handle
		_removal_handle = null
		removal.settle(PresentationTypes.Outcome.INTERRUPTED)
	aim_committed = false
	_facing_hold = false
	has_authority_yaw = false
	postures.teardown()
	speed = 0.0
	heading_rate = 0.0
	velocity = Vector3.ZERO
	_authority_known = false
	_scripted = false
