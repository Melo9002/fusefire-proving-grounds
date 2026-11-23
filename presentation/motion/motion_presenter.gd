class_name MotionPresenter
extends RefCounted
## The smallest contract every movement family's presenter keeps (Task 13): a family-neutral base for a presenter that turns a context's MotionRequest into the APPEARANCE of one body, and says which things it can and
## cannot present. It shares only what means the same for a humanoid, a wheeled platform and a drone: a presentation clock advanced once per request, a read-only snapshot for diagnostics, a capability query, and the
## ActionHandle lifecycle for the one-shot actions a family really has. It owns no anatomy, no gait and no physics, and it never moves the entity: a family writes only to its own visual nodes.
##
## A new family extends this, overrides `family()`, `_capabilities()`, `_present()` (and `_begin_action` if it has a one-shot) and adds its own motion code. Nothing here knows legs, wheels or rotors.

## The few concepts that are genuinely shared enough to ask about. A family answers each; anything else it does is its own API, reached through its own presenter.
const MOTION := &"motion"          ## shows a body moving from a velocity
const FACING := &"facing"          ## shows an orientation request
const REACTION := &"reaction"      ## a one-shot hit reaction
const POSTURE := &"posture"        ## a persistent body posture (crouch, kneel): a legged body concept
const AIMING := &"aiming"          ## aims carried equipment
const TRAVERSAL := &"traversal"    ## climbs, steps and similar contact-driven travel
const ALL_CAPABILITIES: Array[StringName] = [MOTION, FACING, REACTION, POSTURE, AIMING, TRAVERSAL]

## The one-shot action names a context may request (each needs the capability of the same name).
const ACTION_REACTION := &"reaction"
const ACTIONS: Array[StringName] = [ACTION_REACTION]

## Presentation time: the sum of the deltas of the requests this presenter was given.
var time := 0.0
var present_count := 0
## Requests whose frame number repeated the previous one (time advanced twice for one frame): a diagnostic.
var duplicate_frames := 0
## Every refused request, newest last: {action, family, reason}. Unsupported is reported, never silently accepted or faked.
var refusals: Array[Dictionary] = []
var last_request: MotionRequest
var _last_frame_id := -1
var _facing_refused := false
var _action: ActionHandle
var _action_left := 0.0
var _closed := false
var _ending := false
const MAX_REPLACEMENT_CANCELLATIONS := 16

## What kind of body this is ("humanoid", "wheeled", "drone"...). Informational.
func family() -> StringName:
	return &"unknown"

## The capabilities this family implements (a subset of ALL_CAPABILITIES).
func _capabilities() -> Array[StringName]:
	return [MOTION, FACING]

func supports(capability: StringName) -> bool:
	return _capabilities().has(capability)

func capabilities() -> Array[StringName]:
	return _capabilities().duplicate()

## Why a capability is unavailable (empty when it is supported).
func unsupported_reason(capability: StringName) -> String:
	if supports(capability):
		return ""
	return "%s presentation has no %s" % [family(), capability]

## Presents one frame. Call exactly once per frame with the context's request. The clock advances here and only here.
func present(request: MotionRequest) -> void:
	if _closed: return
	if request.frame_id >= 0 and request.frame_id == _last_frame_id:
		duplicate_frames += 1
	_last_frame_id = request.frame_id
	time += request.delta
	present_count += 1
	last_request = request
	if (request.facing_mode == PresentationTypes.FacingMode.FACE_YAW or request.facing_mode == PresentationTypes.FacingMode.FACE_POINT) and not supports(FACING) and not _facing_refused:
		_facing_refused = true   # reported once, not every frame
		refusals.append({"action": FACING, "family": family(), "reason": unsupported_reason(FACING)})
	_advance_action(request.delta)
	if not _closed: _present(request)

## Override: show this frame.
func _present(_request: MotionRequest) -> void:
	pass

## Asks for a one-shot action. A family that does not support it returns an already-SKIPPED handle and records why; it never pretends. A new request supersedes a running one (the older settles INTERRUPTED).
func request_action(action: StringName, seconds := 0.0) -> ActionHandle:
	if not ACTIONS.has(action) or not supports(action):
		var reason := unsupported_reason(action) if ACTIONS.has(action) else "%s is not a shared one-shot action (a family's own actions use its own API)" % action
		refusals.append({"action": action, "family": family(), "reason": reason})
		return ActionHandle.settled(PresentationTypes.Outcome.SKIPPED)
	if _closed: return ActionHandle.settled(PresentationTypes.Outcome.CANCELLED)
	if _ending: return ActionHandle.settled(PresentationTypes.Outcome.SKIPPED)
	var cancelled := 0
	while _action != null and cancelled < MAX_REPLACEMENT_CANCELLATIONS:
		_stop_action(PresentationTypes.Outcome.INTERRUPTED)
		cancelled += 1
	if _closed: return ActionHandle.settled(PresentationTypes.Outcome.CANCELLED)
	if _action != null: return ActionHandle.settled(PresentationTypes.Outcome.SKIPPED)
	_action = ActionHandle.new()
	_action_left = maxf(seconds, 0.0)
	var handle := _action
	_begin_action(action, seconds)
	return handle

func _begin_action(_action_name: StringName, _seconds: float) -> void:
	pass

## A running action ended early by the requester (`handle.cancel()`) is noticed here, at the next frame.
func _advance_action(delta: float) -> void:
	if _action == null: return
	if _action.is_done():
		_stop_action(_action.outcome)
		return
	_action_left -= delta
	if _action_left <= 0.0: _stop_action(PresentationTypes.Outcome.COMPLETED)

## Clean the old visual before its completion observers can start a new action.
func _stop_action(outcome: PresentationTypes.Outcome) -> void:
	var finished := _action
	_action = null
	_action_left = 0.0
	_ending = true
	_end_action(outcome)
	_ending = false
	if finished != null: finished.settle(outcome)

func _end_action(_outcome: PresentationTypes.Outcome) -> void:
	pass

func is_closed() -> bool:
	return _closed

func is_acting() -> bool:
	return _action != null

## Terminal and idempotent; observers cannot restart a removed family.
func teardown() -> void:
	if _closed: return
	_closed = true
	_stop_action(PresentationTypes.Outcome.INTERRUPTED)
	_teardown()

func _teardown() -> void:
	pass

## A read-only description of what is presented now, for diagnostics: plain values the family chose to expose, plus the shared ones. A diagnostic reads this and nothing private.
func snapshot() -> Dictionary:
	var out := {"family": family(), "time": time, "frames": present_count, "duplicates": duplicate_frames, "capabilities": _capabilities(), "acting": is_acting()}
	if last_request != null:
		out["velocity"] = last_request.velocity
		out["horizontal_speed"] = last_request.horizontal_speed()
		out["vertical_speed"] = last_request.vertical_speed()
		out["intended_velocity"] = last_request.intended_velocity if last_request.has_intent else null
		out["facing_mode"] = PresentationTypes.FacingMode.keys()[last_request.facing_mode]
	out.merge(_snapshot_extra(), true)
	return out

func _snapshot_extra() -> Dictionary:
	return {}
