class_name AttackSequence
extends RefCounted
## The attack presentation lifecycle of one character (Task 04 section 14, Task 07 package 6): RAISE, ALIGN, FIRE, RECOVER, RELEASE. The tactical attack is already resolved when this runs; this only stages
## that outcome. It is the ONLY clock of an attack: the presenter advances it once per frame with the engine's delta (never scaled again), and it reads time from the presenter, never from the wall.
## One attack at a time: a newer attack, a hit, a defeat or the character's removal ends the running one (INTERRUPTED). The lifecycle was moved here from TacticalCharacterAdapter without changing a rule.

signal shot_released(timeline: Dictionary)

enum Phase { NONE, RAISE, ALIGN, FIRE, RECOVER, RELEASE }
## The readiness source an attack requests the weapon-up level under.
const SOURCE := &"attack"

var phase := Phase.NONE
## Record of the latest attack: times (presentation seconds), phases, aim blend and muzzle error at the shot.
var timeline: Dictionary = {}
var handle: AttackHandle
var shot_state := &"shoot"

var _host: AttackHost
var _recover_left := 0.0
var _time := 0.0
var _skipped := false
var _closed := false
var _cleaning := false
const MAX_REPLACEMENT_CANCELLATIONS := 16

## True from the request until the shot is shown (or the attack ends).
func is_pending() -> bool:
	return phase == Phase.RAISE or phase == Phase.ALIGN

func is_active() -> bool:
	return phase != Phase.NONE

## Starts an attack. Any attack still running is ended first (INTERRUPTED). `time` is the presenter's clock. From a character that cannot sequence the shot is shown at once.
func begin(host: AttackHost, time: float, shot: StringName, from_state: StringName, from_blend: float) -> AttackHandle:
	if _closed: return _refused(PresentationTypes.Outcome.CANCELLED)
	if _cleaning: return _refused(PresentationTypes.Outcome.SKIPPED)
	cancel()
	# The outer replacement wins finite interruption callbacks. If callbacks keep
	# restarting, refuse the outer request and retain the live operation's ownership.
	var reentered := 0
	while phase != Phase.NONE and reentered < MAX_REPLACEMENT_CANCELLATIONS:
		cancel()
		reentered += 1
	if _closed: return _refused(PresentationTypes.Outcome.CANCELLED)
	if phase != Phase.NONE: return _refused(PresentationTypes.Outcome.SKIPPED)
	_host = host
	_time = time
	_skipped = false
	shot_state = shot
	timeline = {"start": time, "from_state": from_state, "from_blend": from_blend, "phases": [], "forced": false, "fired": false, "shot_state": shot}
	handle = AttackHandle.new()
	var started := handle
	started.finished.connect(_on_handle_settled.bind(started))
	phase = Phase.RAISE
	var available := host.sequence_available()
	if not _owns(started): return started
	if not available:
		timeline["forced"] = true
		_skipped = true
		_fire()
		return started
	_note(Phase.RAISE)
	if not _owns(started): return started
	host.begin_raise()
	if _owns(started): advance(0.0, time)
	return started

static func _refused(outcome: PresentationTypes.Outcome) -> AttackHandle:
	var refused := AttackHandle.new()
	refused.shot.settle(outcome)
	refused.settle(outcome)
	return refused

func _owns(current: AttackHandle) -> bool:
	return current != null and handle == current and phase != Phase.NONE and not _closed

## Once per frame, after readiness has moved. Host callbacks may replace us.
func advance(delta: float, time: float) -> void:
	if _closed or handle == null: return
	_time = time
	var current := handle
	var owner := _host
	match phase:
		Phase.RAISE:
			var waited := _time - float(timeline.get("start", 0.0))
			var aligned := owner.weapon_aligned()
			if not _owns(current): return
			var limit := owner.max_raise_wait_seconds()
			if not _owns(current): return
			if not aligned and waited < limit: return
			phase = Phase.ALIGN
			_note(Phase.ALIGN)
			if not _owns(current): return
			timeline["forced"] = not aligned
			_fire()
		Phase.RECOVER:
			_recover_left -= delta
			if _recover_left <= 0.0: _release()
		Phase.RELEASE:
			var blend := owner.aim_blend()
			var target := owner.aim_target()
			if _owns(current) and is_equal_approx(blend, target): _finish(PresentationTypes.Outcome.COMPLETED)

func cancel() -> void:
	if handle != null:
		timeline["cancelled"] = true
		_finish(PresentationTypes.Outcome.INTERRUPTED)

## Terminal: set the admission guard before notifying any observer.
func teardown() -> void:
	if _closed: return
	_closed = true
	cancel()

func _on_handle_settled(outcome: PresentationTypes.Outcome, which: AttackHandle) -> void:
	if which != handle or outcome != PresentationTypes.Outcome.CANCELLED: return
	timeline["cancelled"] = true
	_finish(PresentationTypes.Outcome.CANCELLED)

func _fire() -> void:
	var current := handle
	var owner := _host
	if not _owns(current): return
	var start := float(timeline.get("start", _time))
	var blend := owner.aim_blend()
	var error := owner.alignment_error_degrees()
	if not _owns(current): return
	timeline["fired"] = true
	timeline["fire_t"] = _time - start
	timeline["fire_blend"] = blend
	timeline["fire_muzzle_error_degrees"] = error
	phase = Phase.FIRE
	_note(Phase.FIRE)
	if not _owns(current): return
	owner.play_shot(shot_state)
	if not _owns(current): return
	var recovery := owner.recover_seconds()
	if not _owns(current): return
	phase = Phase.RECOVER
	_recover_left = recovery
	_note(Phase.RECOVER)
	if not _owns(current): return
	var fired_timeline := timeline
	current.shot.settle(PresentationTypes.Outcome.SKIPPED if _skipped else PresentationTypes.Outcome.COMPLETED)
	shot_released.emit(fired_timeline)
	if not _owns(current) or phase != Phase.RECOVER: return
	var immediate := owner.immediate_release()
	if _owns(current) and immediate: _release()

func _release() -> void:
	var current := handle
	var owner := _host
	owner.release_aimed()
	if not _owns(current): return
	phase = Phase.RELEASE
	_note(Phase.RELEASE)
	if not _owns(current): return
	owner.resume_after_shot()
	if not _owns(current): return
	var blend := owner.aim_blend()
	var target := owner.aim_target()
	if _owns(current) and is_equal_approx(blend, target): _finish(PresentationTypes.Outcome.COMPLETED)

func _finish(outcome: PresentationTypes.Outcome) -> void:
	# Detach the old operation BEFORE calling host hooks or settling handles. Cleanup
	# hooks cannot start work; completion observers may (except during teardown).
	var finished := handle
	var owner := _host
	var skipped := _skipped
	handle = null
	_host = null
	phase = Phase.NONE
	timeline["end_t"] = _time - float(timeline.get("start", 0.0))
	_cleaning = true
	if owner != null:
		owner.release_aimed()
		owner.attack_ended()
	_cleaning = false
	if finished != null:
		if skipped and outcome == PresentationTypes.Outcome.COMPLETED: outcome = PresentationTypes.Outcome.SKIPPED
		finished.shot.settle(PresentationTypes.Outcome.INTERRUPTED)
		finished.settle(outcome)

func _note(which: Phase) -> void:
	var current := handle
	var owner := _host
	var blend := owner.aim_blend()
	var error := owner.alignment_error_degrees()
	if not _owns(current): return
	var phases: Array = timeline.get("phases", [])
	phases.append({"phase": which, "t": _time - float(timeline.get("start", 0.0)), "blend": blend, "muzzle_error_degrees": error})
