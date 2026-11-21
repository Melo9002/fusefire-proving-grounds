class_name PostureArbiter
extends RefCounted
## Source-keyed posture arbitration (Task 04, section 6.4). Pure shared policy: it knows nothing about cover, tactical units or any particular posture.
##  * A request is (source, posture, priority, yaw offset, depth, kneel, exact). `depth` is how far into the posture the requester wants the body, in metres of lowering (0 when it does not care);
##    the arbiter only carries it with the winning request, it never interprets it. The same source replaces its own request.
##    `kneel` is an explicit half-kneel blend 0..1, or -1 to let the applier derive it from `depth`. `exact` says the requester already shapes the motion (an authored timeline), so the applier
##    follows it without its own easing. Both are carried, never interpreted.
##  * The winner has the highest priority; equal priorities go to the MOST RECENTLY CHANGED request (a call-order counter, so replays are deterministic).
##  * An identical repeated request is a no-op and does NOT refresh the order, so per-frame idempotent calls cannot reorder anything.
##  * release(source), release_prefix(prefix) and teardown() withdraw requests. With none, the posture is STAND.
##  * A whole-body override (traversal, defeat) does not touch the table: it is a separate layer that only says "something else owns the body now". The persistent winner stays resolvable.

class Request extends RefCounted:
	var source: StringName
	var posture: int
	var priority: int
	var yaw_offset: float
	var depth: float
	var kneel: float
	var exact: bool
	var sequence: int

var _requests: Dictionary = {}   # source -> Request
var _overrides: Dictionary = {}  # override source -> true
var _sequence := 0

func set_posture(source: StringName, posture: PresentationTypes.Posture, priority: int, yaw_offset := 0.0, depth := 0.0, kneel := -1.0, exact := false) -> void:
	var existing: Request = _requests.get(source)
	if existing != null and existing.posture == posture and existing.priority == priority and is_equal_approx(existing.yaw_offset, yaw_offset) and is_equal_approx(existing.depth, depth) 			and is_equal_approx(existing.kneel, kneel) and existing.exact == exact:
		return
	_sequence += 1
	var request := Request.new()
	request.source = source
	request.posture = posture
	request.priority = priority
	request.yaw_offset = yaw_offset
	request.depth = depth
	request.kneel = kneel
	request.exact = exact
	request.sequence = _sequence
	_requests[source] = request

func release(source: StringName) -> void:
	_requests.erase(source)

## Removes every request whose source starts with `prefix` (a context leaving).
func release_prefix(prefix: String) -> void:
	for source: StringName in _requests.keys():
		if String(source).begins_with(prefix):
			_requests.erase(source)

func has_request(source: StringName) -> bool:
	return _requests.has(source)

func request_count() -> int:
	return _requests.size()

func _winner() -> Request:
	var best: Request = null
	for request: Request in _requests.values():
		if best == null or request.priority > best.priority or (request.priority == best.priority and request.sequence > best.sequence):
			best = request
	return best

## The persistent posture, resolved from the requests alone (a whole-body override never changes it).
func resolved() -> PresentationTypes.Posture:
	var best := _winner()
	return PresentationTypes.Posture.STAND if best == null else best.posture as PresentationTypes.Posture

func resolved_yaw_offset() -> float:
	var best := _winner()
	return 0.0 if best == null else best.yaw_offset

func resolved_depth() -> float:
	var best := _winner()
	return 0.0 if best == null else best.depth

func resolved_kneel() -> float:
	var best := _winner()
	return -1.0 if best == null else best.kneel

func resolved_exact() -> bool:
	var best := _winner()
	return false if best == null else best.exact

func resolved_source() -> StringName:
	var best := _winner()
	return &"" if best == null else best.source

## Whole-body overrides: keyed so that each owner clears only its own.
func begin_override(source: StringName) -> void:
	_overrides[source] = true

func end_override(source: StringName) -> void:
	_overrides.erase(source)

func is_overridden() -> bool:
	return not _overrides.is_empty()

## Every request cleared, every override ended: nothing outlives the character.
func teardown() -> void:
	_requests.clear()
	_overrides.clear()

## Diagnostics: every request, the winner flagged, and every tie at the winning priority flagged.
func report() -> Array[Dictionary]:
	var winner := _winner()
	var rows: Array[Dictionary] = []
	for request: Request in _requests.values():
		var tied := winner != null and request != winner and request.priority == winner.priority
		rows.append({"source": request.source, "posture": request.posture, "priority": request.priority, "depth": request.depth, "kneel": request.kneel, "exact": request.exact, "sequence": request.sequence,
			"winner": request == winner, "tied_with_winner": tied, "overridden": is_overridden()})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.sequence) < int(b.sequence))
	return rows
