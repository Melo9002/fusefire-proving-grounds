extends RefCounted
## Optional main-thread elapsed samples. Suspended frames and authoritative
## action windows never count toward planner work.

var actor_id: StringName
var decisions: Array[Dictionary] = []
var stages := {}
var counts := {}
var _started: int
var _decision_start: int
var _slice_start: int
var _work := 0
var _max_slice := 0
var _yield_time := 0
var _yields := 0
var _delay_total := 0
var _action_total := 0
var _action_start := -1
var _suspended_at := -1
var _action := {}

func _init(actor: StringName, now: int = Time.get_ticks_usec()) -> void:
	actor_id = actor
	_started = now
	_decision_start = now
	_slice_start = now

func note(stage: String, elapsed: int, count := 1) -> void:
	stages[stage] = int(stages.get(stage, 0)) + elapsed
	counts[stage] = int(counts.get(stage, 0)) + count

func peak(stage: String, elapsed: int) -> void:
	stages[stage] = maxi(stages.get(stage, 0), elapsed)

func yield_usec() -> int:
	return _yield_time

func suspend(now: int = Time.get_ticks_usec()) -> void:
	_close_slice(now)
	_suspended_at = now

func resume(kind: String, now: int = Time.get_ticks_usec()) -> void:
	if _suspended_at < 0:
		return
	var elapsed := now - _suspended_at
	if kind == "yield":
		_yield_time += elapsed
		_yields += 1
	else:
		_delay_total += elapsed
		_decision_start += elapsed
	_suspended_at = -1
	_slice_start = now

func begin_action(now: int = Time.get_ticks_usec()) -> void:
	_close_slice(now)
	_action_start = now
	_action = _decision_sample(now)

func note_commit(kind: StringName, transaction: int, core: int, observers: int) -> void:
	if _action_start < 0:
		return
	_action.merge({"action": kind, "transaction": transaction, "core_us": core, "observers_us": observers})

func end_action(now: int = Time.get_ticks_usec()) -> void:
	if _action_start < 0:
		return
	var elapsed := now - _action_start
	_action["action_window_us"] = elapsed
	_action_total += elapsed
	decisions.append(_action)
	_action_start = -1
	_decision_start = now
	_slice_start = now
	_work = 0
	_max_slice = 0
	_yield_time = 0
	_yields = 0
	stages = {}
	counts = {}

func finish(now: int = Time.get_ticks_usec()) -> Dictionary:
	_close_slice(now)
	return {"actor": actor_id, "activation_us": now - _started, "delay_us": _delay_total,
		"action_windows_us": _action_total, "decisions": decisions,
		"tail": _decision_sample(_suspended_at if _suspended_at >= 0 else now)}

func _close_slice(now: int) -> void:
	if _slice_start < 0:
		return
	var elapsed := now - _slice_start
	_work += elapsed
	_max_slice = maxi(_max_slice, elapsed)
	_slice_start = -1

func _decision_sample(now: int) -> Dictionary:
	return {"work_us": _work, "max_slice_us": _max_slice,
		"wall_us": now - _decision_start, "yield_us": _yield_time, "yields": _yields,
		"stages_us": stages, "counts": counts}
