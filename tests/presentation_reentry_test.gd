extends SceneTree
## INVARIANT: finite callback reentry never orphans handles, and teardown is terminal.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
var failures := 0
var checks := 0
class WaitingHost extends AttackHost:
	var aligned := false
	var shot_callback: Callable
	func sequence_available() -> bool: return true
	func immediate_release() -> bool: return false
	func weapon_aligned() -> bool: return aligned
	func max_raise_wait_seconds() -> float: return 10.0
	func play_shot(_state: StringName) -> void:
		if shot_callback.is_valid(): shot_callback.call()
class ReactionFamily extends MotionPresenter:
	var shown := 0
	func _present(_request: MotionRequest) -> void: shown += 1
	func _capabilities() -> Array[StringName]: return [MOTION, FACING, REACTION]
class RestartChain extends RefCounted:
	var sequence: AttackSequence
	var host: WaitingHost
	var left := 40
	var handles: Array[AttackHandle] = []
	func restart(_outcome: int) -> void:
		if left <= 0: return
		left -= 1
		var next := sequence.begin(host, 0.1, &"shoot", &"rifle_idle", 0.0)
		handles.append(next)
		if not next.is_done(): next.when_done(restart)
func _initialize() -> void:
	_run.call_deferred()
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)
func _run() -> void:
	var host := WaitingHost.new()
	var sequence := AttackSequence.new()
	var chain := RestartChain.new()
	chain.sequence = sequence
	chain.host = host
	var first := sequence.begin(host, 0.0, &"shoot", &"rifle_idle", 0.0)
	first.when_done(chain.restart)
	var outer := sequence.begin(host, 0.2, &"shoot", &"rifle_idle", 0.0)
	var pending := 0
	var all_owned := true
	for h in chain.handles:
		if not h.is_done():
			pending += 1
			all_owned = all_owned and h == sequence.handle
		else:
			all_owned = all_owned and h.shot.is_done()
	check(all_owned and pending <= 1, "Exhausting replacement cancellation never overwrites a live nested attack")
	check(sequence.handle == outer or outer.is_done(), "The outer request either owns the operation or is explicitly refused")
	check(outer.is_done() and outer.outcome == PresentationTypes.Outcome.SKIPPED and outer.shot.outcome == PresentationTypes.Outcome.SKIPPED, "Exhaustion explicitly refuses both outer handles with SKIPPED")
	chain.left = 0
	sequence.cancel()
	var all_settled := outer.is_done() and outer.shot.is_done()
	for h in chain.handles: all_settled = all_settled and h.is_done() and h.shot.is_done()
	check(all_settled, "Every attack and shot handle settles after bounded replacement and cleanup")
	# Synchronous shot callbacks may interrupt the operation they were called from.
	sequence = AttackSequence.new()
	host = WaitingHost.new()
	var shot := sequence.begin(host, 0.0, &"shoot", &"rifle_idle", 0.0)
	host.shot_callback = sequence.cancel
	host.aligned = true
	sequence.advance(0.1, 0.1)
	check(shot.is_done() and shot.shot.is_done() and not sequence.is_active(), "Cancelling inside play_shot ends the timeline without reviving it")
	# The neutral reaction owner must keep exactly the same cleanup guarantees.
	var family := ReactionFamily.new()
	var nested: Array[ActionHandle] = []
	var a := family.request_action(&"reaction", 5.0)
	a.when_done(func(_x: int) -> void: nested.append(family.request_action(&"reaction", 4.0)))
	var b := family.request_action(&"reaction", 3.0)
	family.teardown()
	check(a.is_done() and b.is_done() and nested.size() == 1 and nested[0].is_done(), "Reaction replacement settles nested handles")
	family = ReactionFamily.new()
	nested = []
	a = family.request_action(&"reaction", 5.0)
	a.when_done(func(_x: int) -> void: nested.append(family.request_action(&"reaction", 4.0)))
	family.teardown()
	check(not family.is_acting() and nested[0].is_done(), "Reaction teardown immediately refuses observer-created work")
	family.teardown()
	check(not family.is_acting(), "Repeated reaction teardown is idempotent")
	check(family.request_action(&"reaction", 1.0).is_done(), "A removed family refuses subsequent actions")
	var completion_family := ReactionFamily.new()
	var finishing := completion_family.request_action(&"reaction", 0.1)
	finishing.when_done(func(_x: int) -> void: completion_family.teardown())
	completion_family.present(MotionRequest.make(0.2, Vector3.ZERO))
	check(completion_family.shown == 0 and not completion_family.is_acting(), "Completion-triggered teardown prevents the rest of the visual frame")
	var presenter := CharacterPresenter.new()
	var attacks: Array[AttackHandle] = []
	var held := presenter.begin_hold(5.0, func() -> void: pass)
	held.when_done(func(_x: int) -> void: attacks.append(presenter.attack.begin(WaitingHost.new(), 0.0, &"shoot", &"rifle_idle", 0.0)))
	presenter.teardown()
	check(not presenter.attack.is_active() and attacks[0].is_done() and attacks[0].shot.is_done(), "Humanoid teardown immediately refuses cross-action callback reentry")
	presenter.teardown()
	check(not presenter.attack.is_active(), "Repeated humanoid teardown is idempotent")
	check(presenter.begin_hold(1.0, func() -> void: pass).is_done() and not presenter.is_holding(), "A removed humanoid accepts no new timed hold")
	# Real production signal, not only the fake AttackHost.
	var visual: TacticalCharacterAdapter = VISUAL.instantiate()
	root.add_child(visual)
	await create_timer(0.25).timeout
	var bridge := HumanoidMotionBridge.new(visual.presenter)
	var reaction := bridge.request_action(&"reaction", 1.0)
	bridge.teardown()
	check(reaction.is_done() and not visual.presenter.is_holding() and bridge.request_action(&"reaction", 1.0).is_done(), "The humanoid bridge releases its delegated reaction on teardown")
	var observed := []
	visual.presentation_state_changed.connect(func(state: StringName) -> void:
		if state in [&"shoot", &"shoot_left", &"shoot_right"] and observed.is_empty():
			observed.append(state)
			visual.present_hit())
	var actual := visual.present_attack(visual.global_position + Vector3(0, 0, 6))
	await create_timer(1.0).timeout
	check(observed.size() == 1 and actual.is_done() and actual.shot.is_done() and not visual.presenter.attack.is_active(), "A real shot-state observer can request a hit without a script error or stale attack")
	visual.queue_free()
	await process_frame
	print("Presentation reentry: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
