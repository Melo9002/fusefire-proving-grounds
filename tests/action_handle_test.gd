extends SceneTree
## ActionHandle (Task 07 package 2): exactly-once settlement and safe observation, proven with REAL coroutines and signals, not just a syntax check. The contract: a handle can settle before
## anyone observes it (a rejected or skipped request settles before the request call returns) or after, and wait() / when_done() must work identically and never hang or run twice.
const Outcome := PresentationTypes.Outcome
var failures := 0
var checks := 0
var results: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## Records what a waiter received, and that it resumed at all.
func _waiter(key: String, handle: ActionHandle) -> void:
	results[key] = {"resumed": false, "outcome": null, "count": 0}
	var got: Outcome = await handle.wait()
	results[key].resumed = true
	results[key].outcome = got
	results[key].count += 1

func _run() -> void:
	# ---- Immediate completion: settled BEFORE anyone observes it.
	var early := ActionHandle.new()
	check(not early.is_done(), "A new handle is pending")
	check(early.settle(Outcome.COMPLETED), "The first settle reports that it settled the handle")
	check(early.is_done() and early.outcome == Outcome.COMPLETED, "A settled handle is inspectable: done, COMPLETED")
	var sync_result: Array = []
	early.when_done(func(o: Outcome) -> void: sync_result.append(o))
	check(sync_result == [Outcome.COMPLETED], "when_done on an already-settled handle runs the callback at once, exactly once")
	_waiter("early", early)   # not awaited here: if wait() hung this key would stay unresumed
	check(results.early.resumed and results.early.outcome == Outcome.COMPLETED, "wait() on an already-settled handle returns immediately with its outcome (no frame needed, no hang)")
	# The factory for rejected / skipped / suppressed requests.
	var skipped := ActionHandle.settled(Outcome.SKIPPED)
	_waiter("skipped", skipped)
	check(skipped.is_done() and results.skipped.resumed and results.skipped.outcome == Outcome.SKIPPED, "A handle created already settled (SKIPPED) is observable at once")

	# ---- Delayed completion: observed first, settled later.
	var late := ActionHandle.new()
	var late_calls: Array = []
	late.when_done(func(o: Outcome) -> void: late_calls.append(o))
	_waiter("late_a", late)
	_waiter("late_b", late)
	check(not results.late_a.resumed and not results.late_b.resumed and late_calls.is_empty(), "Observers of a pending handle wait: nothing resumes before settlement")
	await process_frame
	check(not results.late_a.resumed and late_calls.is_empty(), "A pending handle stays pending across frames")
	late.settle(Outcome.INTERRUPTED)
	check(results.late_a.resumed and results.late_b.resumed, "Every waiter resumes when the handle settles (several observers are all released)")
	check(results.late_a.outcome == Outcome.INTERRUPTED and results.late_b.outcome == Outcome.INTERRUPTED, "Waiters receive the settled outcome (INTERRUPTED)")
	check(late_calls == [Outcome.INTERRUPTED], "when_done on a pending handle runs once on settlement with the outcome")

	# ---- Exactly once.
	var emissions: Array = []
	var once := ActionHandle.new()
	once.finished.connect(func(o: Outcome) -> void: emissions.append(o))
	_waiter("once", once)
	check(once.settle(Outcome.COMPLETED), "First settle wins")
	check(not once.settle(Outcome.CANCELLED), "A second settle reports it did nothing")
	once.settle(Outcome.INTERRUPTED)
	check(once.outcome == Outcome.COMPLETED, "The first outcome stands after later settle attempts")
	check(emissions == [Outcome.COMPLETED] and results.once.count == 1, "finished emitted once and the waiter resumed once")
	var after: Array = []
	once.when_done(func(o: Outcome) -> void: after.append(o))
	once.when_done(func(o: Outcome) -> void: after.append(o))
	check(after == [Outcome.COMPLETED, Outcome.COMPLETED], "Late observers each get the original outcome")

	# ---- Re-entrancy: a callback that tries to settle again, and one that observes during settlement.
	var reentrant := ActionHandle.new()
	var seen: Array = []
	reentrant.when_done(func(o: Outcome) -> void:
		seen.append(o)
		reentrant.settle(Outcome.CANCELLED))
	reentrant.settle(Outcome.COMPLETED)
	check(seen == [Outcome.COMPLETED] and reentrant.outcome == Outcome.COMPLETED, "A callback cannot change an outcome that is being delivered")

	# ---- Cancellation.
	var pending := ActionHandle.new()
	_waiter("cancelled", pending)
	check(pending.cancel(), "cancel() settles a pending handle")
	check(pending.outcome == Outcome.CANCELLED and results.cancelled.resumed and results.cancelled.outcome == Outcome.CANCELLED, "A cancelled handle releases its waiter with CANCELLED")
	var done := ActionHandle.new()
	done.settle(Outcome.COMPLETED)
	check(not done.cancel() and done.outcome == Outcome.COMPLETED, "cancel() after completion is a no-op: the completed outcome is not rewritten")

	# ---- A waiter that resumes in a later frame still gets the value (coroutine across frames).
	var timed := ActionHandle.new()
	_waiter("timed", timed)
	get_root().get_tree().create_timer(0.05, true, false, true).timeout.connect(func() -> void: timed.settle(Outcome.SKIPPED))
	var frames := 0
	while not results.timed.resumed and frames < 120:
		await process_frame
		frames += 1
	check(results.timed.resumed and results.timed.outcome == Outcome.SKIPPED, "A waiter suspended across several frames resumes with the outcome when a timer settles it (%d frames)" % frames)

	# ---- Dropping the last external reference while a coroutine waits must not crash or leak the settlement.
	var orphan_key := "orphan"
	var orphan := ActionHandle.new()
	_waiter(orphan_key, orphan)
	orphan.settle(Outcome.COMPLETED)
	orphan = null
	await process_frame
	check(results.orphan.resumed, "A waiter is released even when the requester dropped its reference")

	print("ActionHandle: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
