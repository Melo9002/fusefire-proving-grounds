class_name PresentationMonitor
extends Node
## A read-only, opt-in observer of one CharacterPresenter and its rig: a compact live snapshot of what the character is presenting right now, and a bounded history of what changed. Nothing in the game creates it;
## a diagnostic host (the workbench, a test, a capture) attaches it and frees it.
##
## RUNTIME STATE versus INTERPRETATION. `snapshot` holds only values the presenter and rig expose through public accessors (the controller's current state, presenter.intent(), hold_report(), the locomotion report, which
## contexts own the body). It reads no private field and runs no logic of the presenter's: the hold, the attack and the rescue clock are the presenter's, and this class never times or settles anything. The `history` entries are
## derived by comparing consecutive snapshots (a hold that was running and is not, a state that changed); they say WHAT changed and when on the presenter's own clock (`presenter.time`), never WHY, except for the outcomes
## of handles a caller passes to watch(), whose outcome (COMPLETED, CANCELLED, INTERRUPTED, SKIPPED) is the presenter's own word.
## It adds no clock: `presenter.time` is the timestamp.

signal event_logged(entry: Dictionary)

const MAX_HISTORY := 60

var presenter: CharacterPresenter
var rig: CharacterRig
var snapshot: Dictionary = {}
var history: Array[Dictionary] = []
var previous_state: StringName = &""
var _last_state: StringName = &""
var _last := {}
var _connected := false
var _watched: Array[ActionHandle] = []

## Attaches an observer to `p_rig`'s presenter as a child of the rig. Returns null when the rig is not built.
static func attach(p_rig: CharacterRig) -> PresentationMonitor:
	if not is_instance_valid(p_rig) or p_rig.animation_controller == null:
		return null
	var monitor := PresentationMonitor.new()
	monitor.name = "PresentationMonitor"
	monitor.rig = p_rig
	monitor.presenter = p_rig.presenter
	p_rig.add_child(monitor)
	return monitor

func _ready() -> void:
	_last_state = rig.animation_controller.current_state
	rig.animation_controller.state_changed.connect(_on_state_changed)
	_connected = true
	refresh()

## Disconnects from the controller and stops observing. Safe to call twice; the node frees itself.
func shutdown() -> void:
	if _connected and is_instance_valid(rig) and is_instance_valid(rig.animation_controller) and rig.animation_controller.state_changed.is_connected(_on_state_changed):
		rig.animation_controller.state_changed.disconnect(_on_state_changed)
	_connected = false
	_watched.clear()
	queue_free()

func is_listening() -> bool:
	return _connected

func _process(_delta: float) -> void:
	refresh()

func _on_state_changed(state_name: StringName) -> void:
	if state_name == _last_state:
		return   # the controller restarted the same state: not a transition
	previous_state = _last_state
	_last_state = state_name
	_log(&"state", "%s -> %s" % [previous_state, state_name])

## Observes one action handle: its outcome is logged when it settles ("gesture acknowledge: INTERRUPTED"). The handle is the presenter's; this only listens.
func watch(handle: ActionHandle, label: String) -> void:
	if handle == null:
		return
	_log(&"request", "%s requested" % label)
	var outcome_name := func(outcome: PresentationTypes.Outcome) -> void:
		_log(&"outcome", "%s: %s" % [label, PresentationTypes.Outcome.keys()[outcome]])
	handle.when_done(outcome_name)
	if not handle.is_done():
		_watched.append(handle)

## Takes a fresh snapshot from public accessors and logs what changed since the last one. Call it from the host's frame (after its presenter tick) for an exact reading; the monitor also calls it from its own _process.
func refresh() -> void:
	if not is_instance_valid(rig) or not is_instance_valid(presenter):
		return
	var intent := presenter.intent()
	var hold := presenter.hold_report()
	var report := rig.locomotion_report
	var contexts: Array[String] = []
	if rig.interaction_active():
		contexts.append("rescue interaction")
	if rig.ladder != null:
		contexts.append("ladder")
	if rig.stairs != null:
		contexts.append("stairs")
	if is_instance_valid(rig.carry_passenger):
		contexts.append("carrying")
	if presenter.attack.is_active():
		contexts.append("attack")
	if presenter.is_defeated():
		contexts.append("defeated")
	snapshot = {
		"state": rig.animation_controller.current_state,
		"previous_state": previous_state,
		"time": presenter.time,
		"speed": presenter.speed,
		"legs_speed": float(report.get("speed", 0.0)),
		"gait": float(report.get("gait", 0.0)),
		"cadence": float(report.get("cadence", 0.0)),
		"heading_rate_deg": rad_to_deg(presenter.heading_rate),
		"facing_yaw_deg": rad_to_deg(intent.facing_yaw),
		"facing_mode": PresentationTypes.FacingMode.keys()[intent.facing_mode],
		"direction": rig.locomotion_direction,
		"posture": PresentationTypes.Posture.keys()[intent.posture],
		"posture_depth": intent.posture_depth,
		"readiness": WeaponReadiness.Level.keys()[intent.readiness],
		"equipment": PresentationTypes.EquipmentState.keys()[intent.equipment],
		"aim_blend": rig.aim_blend,
		"ik_enabled": rig.ik_enabled,
		"hold": hold,
		"contexts": contexts,
	}
	_diff(hold, contexts, intent)

func _diff(hold: Dictionary, contexts: Array[String], intent: PresentationIntent) -> void:
	var rank_names := {PresentationTypes.HOLD_GESTURE: "gesture", PresentationTypes.HOLD_INTERACTION: "interaction", PresentationTypes.HOLD_REACTION: "reaction"}
	if _last.has("hold_active") and bool(_last.hold_active) != bool(hold.active):
		_log(&"hold", "hold %s (%s)" % ["started" if hold.active else "ended", rank_names.get(int(hold.rank) if hold.active else int(_last.hold_rank), "?")])
	elif _last.has("hold_active") and hold.active and int(_last.hold_rank) != int(hold.rank):
		_log(&"hold", "hold replaced (%s -> %s)" % [rank_names.get(int(_last.hold_rank), "?"), rank_names.get(int(hold.rank), "?")])
	if _last.has("contexts"):
		for context in contexts:
			if not (_last.contexts as Array).has(context):
				_log(&"context", "%s began" % context)
		for context: String in _last.contexts:
			if not contexts.has(context):
				_log(&"context", "%s ended" % context)
	if _last.has("posture") and int(_last.posture) != int(intent.posture):
		_log(&"posture", "posture %s -> %s" % [PresentationTypes.Posture.keys()[int(_last.posture)], PresentationTypes.Posture.keys()[intent.posture]])
	if _last.has("readiness") and int(_last.readiness) != int(intent.readiness):
		_log(&"readiness", "readiness %s -> %s" % [WeaponReadiness.Level.keys()[int(_last.readiness)], WeaponReadiness.Level.keys()[intent.readiness]])
	_last = {"hold_active": hold.active, "hold_rank": hold.rank, "contexts": contexts.duplicate(), "posture": int(intent.posture), "readiness": int(intent.readiness)}

func _log(kind: StringName, text: String) -> void:
	var entry := {"t": snappedf(presenter.time if is_instance_valid(presenter) else 0.0, 0.001), "kind": String(kind), "text": text}
	history.append(entry)
	while history.size() > MAX_HISTORY:
		history.pop_front()
	event_logged.emit(entry)

func clear_history() -> void:
	history.clear()

## The live view as compact text (runtime values only).
func live_text() -> String:
	if snapshot.is_empty():
		return "no sample yet"
	var s := snapshot
	var hold: Dictionary = s.hold
	var hold_text := "none"
	if hold.active:
		hold_text = "rank %d, %.2f s left" % [int(hold.rank), float(hold.left)]
	return "state %s  (from %s)\nspeed %.2f m/s  legs %.2f  gait %.2f  cadence %.2f\nfacing %.0f deg (%s)  turn rate %.0f deg/s  dir %s\nposture %s (%.2f m)  readiness %s  %s  aim %.2f\nhold: %s    contexts: %s    IK %s" % [
		s.state, s.previous_state if s.previous_state != &"" else "-", s.speed, s.legs_speed, s.gait, s.cadence, s.facing_yaw_deg, s.facing_mode, s.heading_rate_deg, s.direction, s.posture, s.posture_depth, s.readiness, s.equipment, s.aim_blend, hold_text,
		", ".join(s.contexts) if not (s.contexts as Array).is_empty() else "none", "on" if s.ik_enabled else "OFF"]

func history_text(count := 12) -> String:
	var lines: Array[String] = []
	for index in mini(count, history.size()):
		var entry := history[history.size() - 1 - index]   # newest first
		lines.append("%6.2f  %-8s %s" % [entry.t, entry.kind, entry.text])
	return "\n".join(lines)
