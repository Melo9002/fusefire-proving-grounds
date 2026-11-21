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

## True from the request until the shot is shown (or the attack ends).
func is_pending() -> bool:
	return phase == Phase.RAISE or phase == Phase.ALIGN

func is_active() -> bool:
	return phase != Phase.NONE

## Starts an attack. Any attack still running is ended first (INTERRUPTED). `time` is the presenter's clock. From a character that cannot sequence the shot is shown at once.
func begin(host: AttackHost, time: float, shot: StringName, from_state: StringName, from_blend: float) -> AttackHandle:
	cancel()
	_host = host
	_time = time
	_skipped = false
	shot_state = shot
	timeline = {"start": time, "from_state": from_state, "from_blend": from_blend, "phases": [], "forced": false, "fired": false, "shot_state": shot}
	handle = AttackHandle.new()
	var started := handle
	started.finished.connect(_on_handle_settled.bind(started))
	if not host.sequence_available():
		timeline["forced"] = true
		_skipped = true
		_fire()
		return started
	phase = Phase.RAISE
	_note(Phase.RAISE)
	host.begin_raise()
	advance(0.0, time)
	return started

## Once per frame, after the weapon readiness has moved.
func advance(delta: float, time: float) -> void:
	_time = time
	match phase:
		Phase.RAISE:
			var waited := _time - float(timeline.get("start", 0.0))
			var aligned := _host.weapon_aligned()
			if not aligned and waited < _host.max_raise_wait_seconds():
				return
			phase = Phase.ALIGN
			_note(Phase.ALIGN)
			timeline["forced"] = not aligned
			_fire()
		Phase.RECOVER:
			_recover_left -= delta
			if _recover_left <= 0.0:
				_release()
		Phase.RELEASE:
			if is_equal_approx(_host.aim_blend(), _host.aim_target()):
				_finish(PresentationTypes.Outcome.COMPLETED)

## A higher-priority or newer presentation took over (a hit, a defeat, another attack, removal): the attack's readiness request is dropped so the weapon goes back to whatever the new state wants,
## and whoever waits on the handles continues.
func cancel() -> void:
	if phase != Phase.NONE:
		timeline["cancelled"] = true
		_finish(PresentationTypes.Outcome.INTERRUPTED)
	elif _host != null:
		_host.release_aimed()

## The requester withdrew the attack (handle.cancel()): it ends like any other interruption, and the shot handle is told. Only the CURRENT handle acts; settlements made by this sequence have already cleaned up.
func _on_handle_settled(outcome: PresentationTypes.Outcome, which: AttackHandle) -> void:
	if which != handle or outcome != PresentationTypes.Outcome.CANCELLED:
		return
	timeline["cancelled"] = true
	_finish(PresentationTypes.Outcome.CANCELLED)

func _fire() -> void:
	var start := float(timeline.get("start", _time))
	timeline["fired"] = true
	timeline["fire_t"] = _time - start
	timeline["fire_blend"] = _host.aim_blend()
	timeline["fire_muzzle_error_degrees"] = _host.alignment_error_degrees()
	phase = Phase.FIRE
	_note(Phase.FIRE)
	_host.play_shot(shot_state)
	phase = Phase.RECOVER
	_recover_left = _host.recover_seconds()
	_note(Phase.RECOVER)
	var current := handle
	current.shot.settle(PresentationTypes.Outcome.SKIPPED if _skipped else PresentationTypes.Outcome.COMPLETED)
	shot_released.emit(timeline)
	if phase == Phase.RECOVER and handle == current and _host.immediate_release():
		_release()

## Back to the readiness the character is otherwise holding: relaxed unless a committed Aim (or another request) keeps the weapon up.
func _release() -> void:
	_host.release_aimed()
	phase = Phase.RELEASE
	_note(Phase.RELEASE)
	_host.resume_after_shot()
	if phase == Phase.RELEASE and is_equal_approx(_host.aim_blend(), _host.aim_target()):
		_finish(PresentationTypes.Outcome.COMPLETED)

func _finish(outcome: PresentationTypes.Outcome) -> void:
	_host.release_aimed()
	_host.attack_ended()   # back to the passive cover posture
	var finished := handle
	if phase != Phase.NONE:
		phase = Phase.NONE
		timeline["end_t"] = _time - float(timeline.get("start", 0.0))
	if finished != null:
		# The slot is clear before anyone is told, so an observer may start the next attack from its callback.
		handle = null
		if _skipped and outcome == PresentationTypes.Outcome.COMPLETED:
			outcome = PresentationTypes.Outcome.SKIPPED
		finished.shot.settle(PresentationTypes.Outcome.INTERRUPTED)   # a no-op once the shot was shown
		finished.settle(outcome)

func _note(which: Phase) -> void:
	var phases: Array = timeline.get("phases", [])
	phases.append({"phase": which, "t": _time - float(timeline.get("start", 0.0)), "blend": _host.aim_blend(), "muzzle_error_degrees": _host.alignment_error_degrees()})
