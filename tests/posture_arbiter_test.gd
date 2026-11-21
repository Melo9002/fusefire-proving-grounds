extends SceneTree
## PostureArbiter (Task 07 package 2): source-keyed arbitration with explicit priorities, deterministic ties, idempotent repeats, replacement, release (single, prefix, teardown) and
## whole-body overrides that never touch the persistent requests. Pure: no scene, no cover knowledge.
const Posture := PresentationTypes.Posture
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var a := PostureArbiter.new()
	check(a.resolved() == Posture.STAND and a.resolved_source() == &"" and a.request_count() == 0, "With no requests the posture is STAND")

	# ---- Priority is explicit and independent of the enum values.
	a.set_posture(&"base", Posture.KNEEL, PresentationTypes.PRIORITY_BASE)
	a.set_posture(&"cover", Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.35)
	check(a.resolved() == Posture.CROUCH and a.resolved_source() == &"cover" and is_equal_approx(a.resolved_yaw_offset(), 0.35), "A CROUCH at CONTEXT beats a KNEEL at BASE even though KNEEL has the larger enum value")
	a.set_posture(&"forced", Posture.STAND, PresentationTypes.PRIORITY_FORCED)
	check(a.resolved() == Posture.STAND and a.resolved_source() == &"forced", "A STAND at FORCED beats both")
	a.release(&"forced")
	check(a.resolved() == Posture.CROUCH, "Releasing the winner hands the posture to the next highest")
	a.release(&"absent")
	check(a.request_count() == 2, "Releasing an absent source is a no-op")

	# ---- Ties: the most recently changed request wins, deterministically.
	var t := PostureArbiter.new()
	t.set_posture(&"x", Posture.CROUCH, 100)
	t.set_posture(&"y", Posture.KNEEL, 100)
	check(t.resolved() == Posture.KNEEL and t.resolved_source() == &"y", "Equal priority: the most recent change wins")
	t.set_posture(&"x", Posture.STAND, 100)
	check(t.resolved_source() == &"x", "A real change refreshes the order, so x becomes the most recent")
	var tied := t.report().filter(func(r: Dictionary) -> bool: return r.tied_with_winner)
	check(tied.size() == 1 and tied[0].source == &"y", "The report flags the tie (a design smell worth seeing)")
	var replay_a := PostureArbiter.new()
	var replay_b := PostureArbiter.new()
	for arbiter in [replay_a, replay_b]:
		arbiter.set_posture(&"p", Posture.CROUCH, 100)
		arbiter.set_posture(&"q", Posture.KNEEL, 100)
		arbiter.set_posture(&"p", Posture.STAND, 100)
		arbiter.release(&"q")
		arbiter.set_posture(&"q", Posture.CROUCH, 100)
	check(replay_a.resolved_source() == replay_b.resolved_source() and replay_a.resolved() == replay_b.resolved(), "The same call sequence resolves identically every time (call-order counter, no wall clock)")

	# ---- Idempotence: an identical repeat does not reorder; a real change does.
	var i := PostureArbiter.new()
	i.set_posture(&"first", Posture.CROUCH, 100)
	i.set_posture(&"second", Posture.KNEEL, 100)
	for n in 5:
		i.set_posture(&"first", Posture.CROUCH, 100)   # per-frame idempotent call
	check(i.resolved_source() == &"second", "Repeating an identical request every frame does not steal a tie from a later request")
	i.set_posture(&"first", Posture.CROUCH, 100, 0.2)
	check(i.resolved_source() == &"first", "Changing only the yaw offset is a real change and refreshes the order")
	check(i.request_count() == 2, "Replacement by the same source never duplicates a request")

	# ---- Source replacement and priority changes.
	var r := PostureArbiter.new()
	r.set_posture(&"ctx", Posture.CROUCH, PresentationTypes.PRIORITY_BASE)
	r.set_posture(&"other", Posture.KNEEL, PresentationTypes.PRIORITY_CONTEXT)
	check(r.resolved_source() == &"other", "Setup: other wins on priority")
	r.set_posture(&"ctx", Posture.CROUCH, PresentationTypes.PRIORITY_ACTION)
	check(r.resolved_source() == &"ctx", "Raising a source's own priority makes it win")
	r.set_posture(&"ctx", Posture.STAND, PresentationTypes.PRIORITY_ACTION)
	check(r.resolved() == Posture.STAND and r.request_count() == 2, "The same source replaces its own request")

	# ---- Context-scoped release.
	var c := PostureArbiter.new()
	c.set_posture(&"tactical/cover", Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT)
	c.set_posture(&"tactical/aim", Posture.KNEEL, PresentationTypes.PRIORITY_BASE)
	c.set_posture(&"exploration/walk", Posture.STAND, PresentationTypes.PRIORITY_BASE)
	c.release_prefix("tactical/")
	check(c.request_count() == 1 and c.has_request(&"exploration/walk") and not c.has_request(&"tactical/cover"), "release_prefix removes every request of one context and leaves the others")
	c.release_prefix("nothing/")
	check(c.request_count() == 1, "An unmatched prefix removes nothing")

	# ---- Whole-body overrides never corrupt persistent intent.
	var o := PostureArbiter.new()
	o.set_posture(&"cover", Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.4)
	o.begin_override(&"traversal")
	check(o.is_overridden() and o.resolved() == Posture.CROUCH and is_equal_approx(o.resolved_yaw_offset(), 0.4), "During an override the persistent request is stored untouched")
	check(o.report()[0].overridden, "The report says an override is active")
	o.begin_override(&"defeat")
	o.end_override(&"traversal")
	check(o.is_overridden(), "Overrides are keyed: ending one leaves the other active")
	o.end_override(&"defeat")
	check(not o.is_overridden() and o.resolved() == Posture.CROUCH, "When the last override ends the persistent posture is exactly what it was")

	# ---- Teardown.
	o.teardown()
	check(o.request_count() == 0 and not o.is_overridden() and o.resolved() == Posture.STAND, "teardown() clears every request and every override")

	print("PostureArbiter: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
