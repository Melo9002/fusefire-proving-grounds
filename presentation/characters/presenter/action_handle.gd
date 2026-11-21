class_name ActionHandle
extends RefCounted
## The completion of one one-shot presentation action. It settles EXACTLY ONCE with an outcome (COMPLETED, CANCELLED, INTERRUPTED or SKIPPED) and can be observed whether it is still
## pending or already settled: a rejected, skipped or suppressed request settles before the request call returns, so a caller that connects a signal afterwards would otherwise hang.
##  * is_done() / outcome       inspect at any time
##  * wait()                    coroutine: returns the outcome at once if already settled, otherwise when it settles
##  * when_done(callback)       runs callback(outcome) exactly once: at once if already settled, otherwise on settlement
##  * settle(outcome)           the owner of the action settles it; a second settle is ignored and the first outcome stays
##  * cancel()                  the requester withdraws a pending action (a no-op once settled)
## Direct `finished.connect` still works for observers connected BEFORE the request; new code should use wait() or when_done().

signal finished(outcome: PresentationTypes.Outcome)

var outcome: PresentationTypes.Outcome = PresentationTypes.Outcome.COMPLETED
var _done := false

func is_done() -> bool:
	return _done

## Coroutine. `await handle.wait()` never hangs on a handle that settled earlier.
func wait() -> PresentationTypes.Outcome:
	if _done:
		return outcome
	return await finished

func when_done(callback: Callable) -> void:
	if _done:
		callback.call(outcome)
	else:
		finished.connect(callback, CONNECT_ONE_SHOT)

## Returns true when this call settled the handle, false when it had already settled (the first outcome stands).
func settle(result: PresentationTypes.Outcome) -> bool:
	if _done:
		return false
	_done = true
	outcome = result
	finished.emit(result)
	return true

func cancel() -> bool:
	return settle(PresentationTypes.Outcome.CANCELLED)

## A handle that is already settled, for requests that are rejected, skipped or suppressed immediately.
static func settled(result: PresentationTypes.Outcome) -> ActionHandle:
	var handle := ActionHandle.new()
	handle.settle(result)
	return handle
