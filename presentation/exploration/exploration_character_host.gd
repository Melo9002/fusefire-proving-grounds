@tool
class_name ExplorationCharacterHost
extends Node3D
## The NON-TACTICAL context host of a humanoid character (Task 08): a plain Node3D with a `Rig` child (the same CharacterRig scene the tactical adapter hosts) that translates an exploration or base-style
## controller's wishes into the shared presenter's requests and drives the character once per frame. It reads no tactical type (no unit, turn, AP, cover or combat state, ratcheted) and adds no animation
## controller: CharacterPresenter owns presentation time, facing, postures and the interaction's lifecycle; CharacterRig applies the pose. The context (the controller) decides WHAT the character does.
##
## Per frame, in this order (as every host): the controller reports velocity (`report_velocity`, from its own movement), then `_process` ticks the presenter, applies the posture, advances the action stage
## and lets the rig place the arms and weapon. The foot-point convention holds: this node's origin is the character's feet.

## Emitted when the clip state the host selected changes (a diagnostic or a UI label).
signal presentation_state_changed(state_name: StringName)

@export var rig_path := NodePath("Rig")
## How fast the body turns toward its velocity (degrees per second).
@export_range(90.0, 1080.0) var turn_speed_degrees := 360.0
## The hip drop a crouch asks for (metres on the reference body, scaled by the rig's body_ratio, then capped by its human limit): about the depth for hiding behind a 1.15 m wall.
@export_range(0.0, 0.8, 0.01, "suffix:m") var crouch_depth := 0.41
## An interaction's default length, seconds of presentation time.
@export_range(0.2, 6.0, 0.05, "suffix:s") var inspect_seconds := 1.6

const CROUCH_SOURCE := &"exploration/crouch"
const COVER_SOURCE := &"exploration/cover"
## How long a hit reaction holds (presentation seconds) before the character goes back to what it was doing.
const HIT_SECONDS := 0.58
const INSPECT_SOURCE := &"exploration/inspect"
## A character is moving while velocity was reported within this many seconds (the controller reports every physics step it moves).
const MOVING_REPORT_SECONDS := 0.1
const MOVING_SPEED := 0.05

var rig: CharacterRig
var presenter: CharacterPresenter

var _crouched := false
var _last_report_time := -1000.0
var _state: StringName = &""
var _interaction: ActionHandle   # the inspection, while one runs
var _gesture: ActionHandle       # the gesture, while one runs

var _aiming := false
var _attack_raise := false
var _attack_host := ExplorationAttackHost.new(self)
var _cover := {}   # {full: bool, height: float, side: int} while in cover


func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		_resolve_rig()


func _enter_tree() -> void:
	_resolve_rig()
	rig.aim_blend_follows_clips = false   # this host drives the sights from its own aim request (see _advance_aim)


func _resolve_rig() -> void:
	if rig == null:
		rig = get_node_or_null(rig_path) as CharacterRig
		if rig != null:
			presenter = rig.presenter


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	rig.animation_controller.state_changed.connect(func(state_name: StringName) -> void: presentation_state_changed.emit(state_name))
	await get_tree().process_frame
	await get_tree().process_frame
	for problem in presenter.foot_point_problems():
		push_error("[ExplorationCharacterHost] %s" % problem)


# ------------------------------------------------------------------ what a controller asks for

## The character is moving with this world velocity this frame (call every frame it moves, with the frame's delta). The presenter turns the body toward the velocity and derives the gait from it.
func report_velocity(world_velocity: Vector3, delta: float) -> void:
	var flat := Vector3(world_velocity.x, 0.0, world_velocity.z)
	if flat.length() <= MOVING_SPEED:
		return
	_last_report_time = Time.get_ticks_msec() / 1000.0
	if is_interacting():
		cancel_interaction()   # walking away from an interaction ends it
	presenter.report_velocity(flat, delta, turn_speed_degrees)


## Face a world point (the body turns to it, showing the hips catching up).
func face_point(world_point: Vector3) -> void:
	presenter.face_point(world_point)


## Face a world yaw (radians about the vertical; +Z is forward at zero).
func face_yaw(yaw: float) -> void:
	presenter.face_yaw(yaw)


## Crouch or stand: a CONTEXT-priority posture request, eased by the rig. Standing releases it.
func set_crouched(on: bool) -> void:
	_crouched = on
	_sync_posture()


func is_crouched() -> bool:
	return _crouched


## A simple inspection of something at `world_point`: the character turns to face it, bends toward it (a crouch while the interaction lasts) and holds for `seconds`, then stands back up. The returned
## handle settles COMPLETED when the interaction has finished, INTERRUPTED when the controller walks away or asks for another, CANCELLED if the character cannot begin it (it is already doing one).
## It describes the PRESENTATION only: what inspecting does in the game is the controller's business.
func inspect(world_point: Vector3, seconds := -1.0) -> ActionHandle:
	if (_interaction != null and not _interaction.is_done()) or not presenter.hold_allowed(PresentationTypes.HOLD_INTERACTION):
		return ActionHandle.settled(PresentationTypes.Outcome.CANCELLED)
	presenter.face_point(world_point)
	_set_interaction_posture(true)
	var handle := presenter.begin_hold(seconds if seconds > 0.0 else inspect_seconds, func() -> void: _state = &"", PresentationTypes.HOLD_INTERACTION)
	handle.when_done(func(_outcome: PresentationTypes.Outcome) -> void: _set_interaction_posture(false))   # standing back up, however it ended
	_interaction = handle
	return handle


## A gesture (CharacterAnimationController.GESTURES, e.g. &"acknowledge"): the presenter's one rule decides whether it shows (see CharacterPresenter.begin_gesture) and this host only gives the persistent state
## back when it ends. Walking away, a hit, another interaction or the character's removal ends it INTERRUPTED; the handle settles COMPLETED when it has played out.
func gesture(clip: StringName, seconds := -1.0) -> ActionHandle:
	var handle := presenter.begin_gesture(clip, func() -> void: _state = &"", seconds)
	if not handle.is_done():
		_gesture = handle
	return handle


## Ends an interaction in progress (INTERRUPTED); a no-op when there is none.
func cancel_interaction() -> void:
	presenter.cancel_hold()   # settles INTERRUPTED; the handle's completion stands the character back up


## The controller moved the character without walking it (a respawn, a teleport): forget the motion that was in progress and any interaction, and face the way the body now faces (`yaw`, radians; the rig keeps its own yaw
## otherwise).
func reset_motion(yaw := NAN) -> void:
	_last_report_time = -1000.0
	if is_interacting():
		cancel_interaction()
	if not is_nan(yaw):
		presenter.face_yaw(yaw, false, false)


## True while a one-shot of this host runs (an inspection or a gesture).
func is_interacting() -> bool:
	return (_interaction != null and not _interaction.is_done()) or (_gesture != null and not _gesture.is_done())


func get_presentation_state() -> StringName:
	return rig.animation_controller.current_state if is_instance_valid(rig) and is_instance_valid(rig.animation_controller) else &"setup"


## Whether the character was reported moving within the last few frames.
func is_moving() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _last_report_time <= MOVING_REPORT_SECONDS


# ------------------------------------------------------------------ aim and shoot

## Raise or lower the weapon (the sights come up over the readiness time; nothing happens for an unarmed character).
func set_aiming(on: bool) -> void:
	_aiming = on and rig.has_weapon()


func is_aiming() -> bool:
	return _aiming


## Shows one shot at `aim_point` (a world point; Vector3.INF for straight ahead): the weapon comes up if it is not, aligns, fires (muzzle flash, recoil) and recovers. The handle settles when the release is over;
## `handle.shot` when the shot is shown. Unarmed, defeated or carrying: SKIPPED or CANCELLED. What the shot hits is the controller's business; this only shows the character shooting.
func fire(aim_point := Vector3.INF) -> AttackHandle:
	if presenter.is_defeated():
		var refused := AttackHandle.new()
		refused.shot.settle(PresentationTypes.Outcome.CANCELLED)
		refused.settle(PresentationTypes.Outcome.CANCELLED)
		return refused
	if not rig.has_weapon() or is_carrying():
		var skipped := AttackHandle.new()
		skipped.shot.settle(PresentationTypes.Outcome.SKIPPED)
		skipped.settle(PresentationTypes.Outcome.SKIPPED)
		return skipped
	if aim_point.is_finite() and _cover.is_empty():
		presenter.face_point(aim_point)
	var shot: StringName = &"shoot"
	if not _cover.is_empty() and bool(_cover.full):
		shot = &"shoot_left" if int(_cover.side) < 0 else &"shoot_right"
	presenter.cancel_gesture()   # a shot takes the body: a running gesture yields
	presenter.attack.cancel()
	return presenter.attack.begin(_attack_host, presenter.time, shot, get_presentation_state(), rig.aim_blend)


## The muzzle against the firing direction (degrees).
func _alignment_error() -> float:
	if not is_instance_valid(rig.muzzle_socket) or not rig.muzzle_socket.is_inside_tree():
		return 0.0
	var muzzle := rig.muzzle_socket.global_basis.z.normalized()
	var forward := (rig.character_root.global_basis * rig.torso_frame).z.normalized()
	return rad_to_deg(acos(clampf(muzzle.dot(forward), -1.0, 1.0)))


func _aim_target() -> float:
	return 1.0 if (_aiming or _attack_raise) and rig.has_weapon() and not is_carrying() else 0.0


func _advance_aim(delta: float) -> void:
	var target := _aim_target()
	var seconds: float = rig.handling.raise_seconds if target > rig.aim_blend else rig.handling.lower_seconds
	rig.aim_blend = move_toward(rig.aim_blend, target, delta / maxf(seconds, 0.001))


## What the attack sequence asks of this body (see AttackHost).
class ExplorationAttackHost extends AttackHost:
	var host: ExplorationCharacterHost
	func _init(owner_host: ExplorationCharacterHost) -> void:
		host = owner_host
	func sequence_available() -> bool:
		return host.rig.has_weapon() and is_instance_valid(host.rig.muzzle_socket) and not host.is_carrying()
	func immediate_release() -> bool:
		return not sequence_available()
	func weapon_aligned() -> bool:
		return host._alignment_error() <= host.rig.handling.alignment_tolerance_degrees
	func alignment_error_degrees() -> float:
		return host._alignment_error()
	func aim_blend() -> float:
		return host.rig.aim_blend
	func aim_target() -> float:
		return 1.0 if host._aiming else 0.0
	func max_raise_wait_seconds() -> float:
		return host.rig.handling.max_raise_wait_seconds
	func recover_seconds() -> float:
		return host.rig.handling.shot_recover_seconds
	func begin_raise() -> void:
		host._attack_raise = true
		if host._cover.is_empty() and host.get_presentation_state() not in [&"aim", &"shoot"]:
			host._play(&"aim")
	func release_aimed() -> void:
		host._attack_raise = false
	func play_shot(state: StringName) -> void:
		host._play(state)
	func resume_after_shot() -> void:
		host._state = &""
	func attack_ended() -> void:
		host._attack_raise = false


# ------------------------------------------------------------------ hit and defeat

## A hit reaction: the hit clip for a moment, then back to what the character was doing. It ends a running attack. The handle settles COMPLETED at the return, INTERRUPTED if something took over.
func react_hit() -> ActionHandle:
	if presenter.is_defeated():
		return ActionHandle.settled(PresentationTypes.Outcome.CANCELLED)
	presenter.attack.cancel()
	_attack_raise = false
	_play(&"hit")
	return presenter.begin_hold(HIT_SECONDS, func() -> void: _state = &"")


## Defeat: the defeat clip, which stays. Terminal for this character (a respawn builds a new one). Ends everything else the character was presenting.
func defeat() -> ActionHandle:
	if presenter.is_defeated():
		return presenter.begin_defeat(0.0)
	_aiming = false
	_attack_raise = false
	cancel_interaction()
	leave_cover()
	presenter.attack.cancel()
	presenter.cancel_hold()
	if rig.ladder != null:
		rig.end_traversal()
	rig.end_stairs()
	_play(&"defeat")
	return presenter.begin_defeat(rig.animation_controller.state_length(&"defeat") if is_instance_valid(rig.animation_controller) else 0.0)


func is_defeated() -> bool:
	return presenter.is_defeated()


# ------------------------------------------------------------------ cover

## Take cover behind a wall: the body faces the wall (`yaw_toward_wall`, radians), crouches to what the cover height asks and turns toward the side it is sliding to (-1 left, 1 right). The cover policy (the pose
## numbers) is the shared CoverPostureProfile; where the wall is and which wall is the controller's. Aiming (`set_aiming`) brings the weapon up over the wall or around its edge.
func enter_cover(yaw_toward_wall: float, full: bool, height: float, side := 0) -> void:
	_cover = {"full": full, "height": height, "side": side}
	presenter.face_yaw(yaw_toward_wall, false, false)
	_state = &""


func set_cover_side(side: int) -> void:
	if not _cover.is_empty():
		_cover.side = side


func leave_cover() -> void:
	if _cover.is_empty():
		return
	_cover = {}
	presenter.postures.release(COVER_SOURCE)
	_state = &""


func is_in_cover() -> bool:
	return not _cover.is_empty()


func _sync_cover(delta: float) -> void:
	if not _cover.is_empty() and rig.crouch_modifier != null:
		var request: float = rig.cover_profile.crouch_request(bool(_cover.full), float(_cover.height), rig.aim_blend, rig.crouch_modifier.standing_head_height, rig.crouch_modifier.body_ratio())
		var posture := PresentationTypes.Posture.KNEEL if request > rig.crouch_modifier.max_depth + rig.KNEEL_BLEND_RANGE * 0.5 else PresentationTypes.Posture.CROUCH
		presenter.postures.set_posture(COVER_SOURCE, posture, PresentationTypes.PRIORITY_CONTEXT, rig.cover_profile.yaw_offset(bool(_cover.full), int(_cover.side), rig.aim_blend), request)
	# The body yaw is always driven: leaving cover releases the request, and the yaw it asked for must ease back to square (driving it only while in cover froze the cover turn in place).
	presenter.apply_posture(delta, rig.cover_profile, true)


# ------------------------------------------------------------------ ladder and stairs

## Start climbing a ladder of `length` metres (the character's origin is at the ladder's foot level; the ladder plane is ahead of it). The controller moves the body up and calls `set_climb_height`.
func begin_climb(length: float, deck_from_rungs := NAN, direction := 1, brace_posts := Vector2.ZERO) -> void:
	presenter.cancel_gesture()
	rig.begin_traversal(&"ladder", length, direction, deck_from_rungs, brace_posts)
	_state = &""


func set_climb_height(climbed: float, rung_plane := NAN, across_deck := 0.0) -> void:
	rig.set_traversal_progress(climbed, rung_plane, across_deck)


func end_climb() -> void:
	rig.end_traversal()
	_state = &""


func is_climbing() -> bool:
	return rig.ladder != null


## Walk a staircase (a StairModel in world space): the feet are planned on the treads and the pelvis rides them. The controller places the body on the stair and reports its distance along it.
func begin_stairs(model: StairModel, ascending: bool) -> void:
	presenter.cancel_gesture()
	rig.end_stairs()
	rig.begin_stairs(model, ascending, model.riser_s(1) - model.tread_depth, model.end_s() + model.tread_depth)


func set_stairs_progress(s: float, speed: float, lateral_speed := 0.0) -> void:
	rig.set_stair_progress(s, speed, lateral_speed, true)


func end_stairs() -> void:
	rig.end_stairs()


func is_on_stairs() -> bool:
	return rig.stairs != null


# ------------------------------------------------------------------ carrying a body

## Lift the body lying at `world_point` onto the shoulders (the shared rescue lift: the character steps in, reaches, lifts). The handle settles when the lift is over; a loaded character walks with the loaded gait.
func pick_up(world_point: Vector3) -> ActionHandle:
	if is_carrying() or presenter.is_defeated():
		return ActionHandle.settled(PresentationTypes.Outcome.CANCELLED)
	_aiming = false
	leave_cover()
	presenter.cancel_gesture()   # a lift takes the body
	presenter.face_point(world_point)
	_state = &""
	return rig.begin_pickup(world_point)


## Put the carried body down in front (the shared release). The body is left lying where it is put.
func put_down() -> ActionHandle:
	if not is_carrying():
		return ActionHandle.settled(PresentationTypes.Outcome.CANCELLED)
	rig.keep_released_passenger = true
	_state = &""
	return rig.begin_release()


func is_carrying() -> bool:
	return is_instance_valid(rig.carry_passenger)


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(rig) or not rig.is_inside_tree() or not is_instance_valid(rig.skeleton) or not rig.skeleton.is_inside_tree():
		return
	_select_state()
	_sync_posture()
	_advance_aim(delta)
	presenter.tick(delta)
	_sync_cover(delta)
	presenter.advance_actions(delta)
	rig.update_weapon_pose(delta)


func _play(state_name: StringName) -> void:
	_state = state_name
	rig.animation_controller.play(state_name)


## The clip state of what the character is doing. Defeat, a hit, a shot, a rescue lift or a ladder own the clip while they last.
func _select_state() -> void:
	if presenter.is_defeated() or presenter.is_holding() or presenter.attack.is_active() or rig.interaction_active():
		return
	var wanted: StringName
	if rig.ladder != null:
		wanted = &"rifle_idle"
	elif is_carrying():
		wanted = &"carry_move" if is_moving() else &"carry_idle"
	elif not _cover.is_empty():
		wanted = &"move" if is_moving() else (&"cover_high" if bool(_cover.full) else &"cover_low")
	elif _aiming:
		wanted = &"move" if is_moving() else &"aim"
	else:
		wanted = &"move" if is_moving() else &"rifle_idle"
	if wanted != _state or get_presentation_state() != wanted:
		rig.animation_controller.play(wanted)
		_state = wanted


func _sync_posture() -> void:
	# The stair solver bounds the crouch against the planted feet. The ladder owns the whole posture.
	if _crouched and rig.ladder == null:
		presenter.postures.set_posture(CROUCH_SOURCE, PresentationTypes.Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.0, rig.crouch_modifier.clamp_depth(crouch_depth * rig.crouch_modifier.body_ratio()))
	else:
		presenter.postures.release(CROUCH_SOURCE)


func _set_interaction_posture(on: bool) -> void:
	if on:
		presenter.postures.set_posture(INSPECT_SOURCE, PresentationTypes.Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.0, rig.crouch_modifier.clamp_depth(crouch_depth * rig.crouch_modifier.body_ratio()))
	else:
		presenter.postures.release(INSPECT_SOURCE)
