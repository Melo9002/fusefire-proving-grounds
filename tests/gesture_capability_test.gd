extends SceneTree
## Task 10: the shared way to add a one-shot animation capability, proven with one gesture (&"acknowledge") on BOTH humanoids and from BOTH hosts that can ask for it (the exploration host and the workbench's call).
## Covers: the request and its refusals, the lifecycle (COMPLETED once, INTERRUPTED, CANCELLED, SKIPPED), the hold ranks, replacement, teardown, restoring the persistent state (posture, aim, movement), modifier composition
## (the weapon's arm stages keep the hands on the weapon), nothing advancing twice, and the negative controls of the new contracts.
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
const DT := 1.0 / 60.0
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

var _hand := {}       # host -> the right hand's height in the FINAL pose (after the modifiers), sampled at skeleton_updated
var _shoulder := {}   # host -> the right shoulder's height, likewise

func _spawn(stage: Node3D, key: String, armed: bool) -> ExplorationCharacterHost:
	var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
	if not armed:
		host.rig.weapon_scene = null
	stage.add_child(host)
	# Between updates the skeleton reports the animation pose; the modifiers' result (the arms) exists only at skeleton_updated.
	var skeleton: Skeleton3D = host.rig.skeleton
	skeleton.skeleton_updated.connect(func() -> void:
		var hand := skeleton.find_bone(host.rig.bones.right_arm[2])
		var arm := skeleton.find_bone(host.rig.bones.right_arm[0])
		_hand[host] = (skeleton.global_transform * skeleton.get_bone_global_pose(hand).origin).y
		_shoulder[host] = (skeleton.global_transform * skeleton.get_bone_global_pose(arm).origin).y)
	return host

func _hand_height(host: ExplorationCharacterHost) -> float:
	return _hand.get(host, 0.0)

func _shoulder_height(host: ExplorationCharacterHost) -> float:
	return _shoulder.get(host, 0.0)

func _walk(host: ExplorationCharacterHost, frames: int) -> void:
	for i in frames:
		host.report_velocity(Vector3(0, 0, 1.4), DT)
		await process_frame

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var x := 0.0
	for key in SCENES:
		await _body_checks(stage, key, x)
		x += 3.0
	await _contract_checks(stage)
	await _hardening_checks(stage)
	stage.queue_free()
	print("gesture_capability_test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)

## One humanoid, unarmed and armed: the gesture shows, completes, restores, and composes with posture and the weapon.
func _body_checks(stage: Node3D, key: String, x: float) -> void:
	var bare := _spawn(stage, key, false)
	bare.position.x = x
	await _frames(30)
	var rest := _hand_height(bare)
	var shoulder := _shoulder_height(bare)
	var handle := bare.gesture(&"acknowledge")
	var seen := []
	handle.when_done(func(outcome: int) -> void: seen.append(outcome))
	check(not handle.is_done() and bare.is_interacting() and bare.get_presentation_state() == &"acknowledge", "%s: an unarmed gesture starts (pending handle, the clip is selected)" % key)
	var peak := rest
	for i in 70:
		await process_frame
		peak = maxf(peak, _hand_height(bare))
	check(peak > rest + 0.25 and peak > shoulder - 0.1, "%s: the unarmed hand really comes up (in the final pose) (%.2f -> %.2f m, shoulder %.2f)" % [key, rest, peak, shoulder])
	await create_timer(1.6).timeout
	check(handle.is_done() and seen == [PresentationTypes.Outcome.COMPLETED] and not bare.is_interacting(), "%s: it completes (COMPLETED, exactly once)" % key)
	await _frames(40)
	check(bare.get_presentation_state() == &"rifle_idle" and absf(_hand_height(bare) - rest) < 0.05, "%s: the body goes back to idle and the hand comes down (%.3f m from rest)" % [key, _hand_height(bare) - rest])
	bare.queue_free()

	# Armed: the hands stay on the weapon (equipment contact continuity), the torso and head still show the gesture.
	var armed := _spawn(stage, key, true)
	armed.position.x = x
	await _frames(30)
	var weapon_rest := _hand_height(armed)
	var armed_handle := armed.gesture(&"acknowledge")
	var deviation := 0.0
	for i in 70:
		await process_frame
		deviation = maxf(deviation, absf(_hand_height(armed) - weapon_rest))
	check(armed_handle.is_done() == false and deviation < 0.04, "%s: an armed character keeps its hand on the weapon during the gesture (peak %.3f m)" % [key, deviation])
	await create_timer(1.6).timeout
	check(armed_handle.is_done() and armed_handle.outcome == PresentationTypes.Outcome.COMPLETED, "%s: the armed gesture completes" % key)

	# Persistent state is untouched and wins afterwards: crouched stays crouched, aiming goes back to the aim clip.
	armed.set_crouched(true)
	await create_timer(1.5).timeout
	var depth_before: float = armed.rig.crouch_modifier.depth
	var crouched_handle := armed.gesture(&"acknowledge")
	await _frames(40)
	check(absf(armed.rig.crouch_modifier.depth - depth_before) < 0.01 and armed.presenter.postures.resolved() == PresentationTypes.Posture.CROUCH, "%s: a crouch is not disturbed by a gesture (depth %.3f -> %.3f)" % [key, depth_before, armed.rig.crouch_modifier.depth])
	await create_timer(1.6).timeout
	await _frames(3)
	check(crouched_handle.is_done() and armed.is_crouched() and armed.get_presentation_state() == &"rifle_idle", "%s: ...and the crouch is still there after it" % key)
	armed.set_crouched(false)
	await create_timer(1.2).timeout
	armed.set_aiming(true)
	await create_timer(0.8).timeout
	var aim_handle := armed.gesture(&"acknowledge")
	await create_timer(1.9).timeout
	await _frames(3)
	check(aim_handle.is_done() and aim_handle.outcome == PresentationTypes.Outcome.COMPLETED and armed.get_presentation_state() == &"aim" and armed.is_aiming(), "%s: aiming resumes as the aim clip after the gesture, not blindly idle (state %s)" % [key, armed.get_presentation_state()])
	armed.queue_free()

## Lifecycle and arbitration, on the larger body (the rules are shared, the body is irrelevant).
func _contract_checks(stage: Node3D) -> void:
	var host := _spawn(stage, "mira", true)
	host.position.x = -4.0
	await _frames(30)

	# Movement interrupts, and the walk is what follows (not idle).
	var first := host.gesture(&"acknowledge")
	await _frames(20)
	await _walk(host, 4)
	check(first.is_done() and first.outcome == PresentationTypes.Outcome.INTERRUPTED and not host.presenter.is_holding(), "Walking away interrupts a gesture (INTERRUPTED)")
	await _frames(1)
	check(host.get_presentation_state() == &"move", "...and the walk is the state that follows, not idle (state %s)" % host.get_presentation_state())
	await _frames(80)

	# Replacement: a second gesture replaces the first, which settles INTERRUPTED.
	var older := host.gesture(&"acknowledge")
	await _frames(10)
	var newer := host.gesture(&"acknowledge")
	check(older.is_done() and older.outcome == PresentationTypes.Outcome.INTERRUPTED and not newer.is_done(), "A replacement gesture interrupts the running one (INTERRUPTED) and runs")
	var unknown := host.gesture(&"not_a_gesture")
	check(unknown.is_done() and unknown.outcome == PresentationTypes.Outcome.SKIPPED and not newer.is_done(), "An unknown gesture is refused at once (SKIPPED) and disturbs nothing")

	# Cancellation by the requester, through the handle alone: the hold is freed, the persistent state returns, it settles once, and an obsolete handle cannot touch a newer gesture.
	var cancel_settles := []
	newer.finished.connect(func(outcome: int) -> void: cancel_settles.append(outcome))
	newer.cancel()
	newer.cancel()
	check(cancel_settles == [PresentationTypes.Outcome.CANCELLED] and not host.presenter.is_holding() and not host.is_interacting(), "Cancelling the handle ends the gesture and frees the hold, settling once (CANCELLED)")
	await _frames(3)
	check(host.get_presentation_state() == &"rifle_idle" and host.presenter.gesture_hand() == Vector2.ZERO, "...and the character is back in its persistent state (state %s)" % host.get_presentation_state())
	var stale := host.gesture(&"acknowledge")
	await _frames(5)
	var current := host.gesture(&"acknowledge")
	stale.cancel()
	check(stale.outcome == PresentationTypes.Outcome.INTERRUPTED and not current.is_done() and host.presenter.is_holding() and host.get_presentation_state() == &"acknowledge", "Cancelling an obsolete handle does not touch the newer gesture")
	current.cancel()
	await _frames(3)

	# Ranks: a gesture yields to an interaction and to a hit; an interaction and a hit take over a gesture; a hit during a gesture is not refused.
	var inspect := host.inspect(Vector3(0, 0, 3), 1.0)
	var yielded := host.gesture(&"acknowledge")
	check(yielded.is_done() and yielded.outcome == PresentationTypes.Outcome.SKIPPED and not inspect.is_done(), "A gesture yields to a running interaction (SKIPPED) and leaves it alone")
	host.cancel_interaction()
	await _frames(40)
	var gesture := host.gesture(&"acknowledge")
	await _frames(10)
	var taken := host.inspect(Vector3(0, 0, 3), 0.5)
	check(gesture.is_done() and gesture.outcome == PresentationTypes.Outcome.INTERRUPTED and not taken.is_done(), "An interaction takes over a gesture (the gesture is INTERRUPTED)")
	host.cancel_interaction()
	await _frames(40)
	var again := host.gesture(&"acknowledge")
	await _frames(10)
	var hit := host.react_hit()
	check(again.is_done() and again.outcome == PresentationTypes.Outcome.INTERRUPTED and host.get_presentation_state() == &"hit" and not hit.is_done(), "A hit takes over a gesture and shows the hit clip")
	var refused_during_hit := host.gesture(&"acknowledge")
	check(refused_during_hit.is_done() and refused_during_hit.outcome == PresentationTypes.Outcome.SKIPPED and host.get_presentation_state() == &"hit", "A gesture during a hit reaction is SKIPPED and the hit keeps playing")
	await create_timer(0.8).timeout
	check(hit.is_done() and hit.outcome == PresentationTypes.Outcome.COMPLETED and host.get_presentation_state() == &"rifle_idle", "The hit completes and the character is back to idle")

	# Other owners of the body: an attack, a traversal, a carried body.
	host.set_aiming(true)
	await _frames(60)
	var shot := host.fire(Vector3(0, 1.2, 8))
	var during_attack := host.gesture(&"acknowledge")
	check(during_attack.is_done() and during_attack.outcome == PresentationTypes.Outcome.SKIPPED, "A gesture during an attack is SKIPPED")
	await shot.wait()
	host.set_aiming(false)
	await _frames(30)
	host.begin_climb(2.0)
	var on_ladder := host.gesture(&"acknowledge")
	check(on_ladder.is_done() and on_ladder.outcome == PresentationTypes.Outcome.SKIPPED, "A gesture on a ladder is SKIPPED")
	host.end_climb()
	await _frames(30)

	# Defeat: it ends a gesture, and a gesture afterwards is refused. Removal settles a running one.
	var doomed := host.gesture(&"acknowledge")
	await _frames(10)
	host.defeat()
	check(doomed.is_done() and doomed.outcome == PresentationTypes.Outcome.INTERRUPTED, "Defeat interrupts a running gesture (INTERRUPTED)")
	var late := host.gesture(&"acknowledge")
	check(late.is_done() and late.outcome == PresentationTypes.Outcome.CANCELLED and host.get_presentation_state() == &"defeat", "A gesture after defeat is CANCELLED and the defeat stands")
	host.queue_free()

	var removed_host := _spawn(stage, "small", true)
	removed_host.position.x = 5.0
	await _frames(30)
	var removed := removed_host.gesture(&"acknowledge")
	var settles := []
	removed.when_done(func(outcome: int) -> void: settles.append(outcome))
	await _frames(10)
	removed_host.presenter.teardown()
	removed_host.presenter.teardown()
	check(settles == [PresentationTypes.Outcome.INTERRUPTED] and not removed_host.presenter.is_holding(), "Removing the character settles a running gesture INTERRUPTED, once")
	removed_host.queue_free()

	# Nothing is advanced twice: ticks match frames across a whole gesture.
	var timed := _spawn(stage, "small", false)
	timed.position.x = 8.0
	await _frames(20)
	var run := timed.gesture(&"acknowledge")
	var settle_count := [0]
	run.finished.connect(func(_o: int) -> void: settle_count[0] += 1)
	var worst := 0
	var total := 0
	var last_ticks: int = timed.presenter.tick_count
	for i in 150:
		await process_frame
		var now: int = timed.presenter.tick_count
		worst = maxi(worst, now - last_ticks)
		total += now - last_ticks
		last_ticks = now
	await create_timer(1.8).timeout
	check(worst == 1 and total >= 149 and settle_count[0] == 1 and run.is_done(), "One presenter tick per frame through a gesture (at most %d in any frame, %d over 150), and its handle settles once (%d)" % [worst, total, settle_count[0]])
	timed.queue_free()

	# Negative controls of the ranks: a presenter whose hold ignores the rank would let a gesture cut a hit.
	var probe := CharacterPresenter.new()
	var low := probe.begin_hold(1.0, func() -> void: pass, PresentationTypes.HOLD_GESTURE)
	var high := probe.begin_hold(1.0, func() -> void: pass, PresentationTypes.HOLD_REACTION)
	check(low.is_done() and low.outcome == PresentationTypes.Outcome.INTERRUPTED and not high.is_done(), "Rank: a higher request supersedes a lower hold")
	var refused_low := probe.begin_hold(1.0, func() -> void: pass, PresentationTypes.HOLD_GESTURE)
	check(refused_low.is_done() and refused_low.outcome == PresentationTypes.Outcome.SKIPPED and not high.is_done() and probe.is_holding(), "Rank: a lower request is refused and the running hold is untouched")
	var same := probe.begin_hold(1.0, func() -> void: pass, PresentationTypes.HOLD_REACTION)
	check(high.is_done() and high.outcome == PresentationTypes.Outcome.INTERRUPTED and not same.is_done(), "Rank: an equal request supersedes (as every hold did before ranks)")
	var unranked := probe.begin_hold(1.0, func() -> void: pass)
	check(same.is_done() and not unranked.is_done(), "Rank: a request naming no rank supersedes any hold")
	probe.teardown()
	check(unranked.is_done() and unranked.outcome == PresentationTypes.Outcome.INTERRUPTED and probe.hold_allowed(PresentationTypes.HOLD_GESTURE), "Rank: teardown clears the hold and its rank")

## Shared-contract hardening: reentrant observers, the hand following the gesture, and higher-priority actions ending a gesture.
func _hardening_checks(stage: Node3D) -> void:
	# A superseded hold's observer starts a hold of its own: the new request does not orphan it.
	var p := CharacterPresenter.new()
	var first := p.begin_hold(5.0, func() -> void: pass)
	var started := []
	first.when_done(func(_o: int) -> void: started.append(p.begin_hold(5.0, func() -> void: pass)))
	var second := p.begin_hold(5.0, func() -> void: pass)
	var reentrant: ActionHandle = started[0]
	check(first.outcome == PresentationTypes.Outcome.INTERRUPTED and reentrant.is_done() and reentrant.outcome == PresentationTypes.Outcome.INTERRUPTED and not second.is_done() and p.is_holding(), "A hold started by an observer of the superseded one is settled (INTERRUPTED), not orphaned; the new request runs")
	# ...and if that hold outranks the new request, the request is the one refused.
	var q := CharacterPresenter.new()
	var gesture_hold := q.begin_hold(5.0, func() -> void: pass, PresentationTypes.HOLD_GESTURE)
	var big := []
	gesture_hold.when_done(func(_o: int) -> void: big.append(q.begin_hold(5.0, func() -> void: pass, PresentationTypes.HOLD_REACTION)))
	var late := q.begin_hold(5.0, func() -> void: pass, PresentationTypes.HOLD_GESTURE)   # supersedes the first; the first's observer starts a REACTION
	check(late.is_done() and late.outcome == PresentationTypes.Outcome.SKIPPED and not (big[0] as ActionHandle).is_done() and q.is_holding(), "A reentrant hold that outranks the request is kept and the request is refused (SKIPPED)")
	# Removal: an observer of the removed hold cannot leave a hold behind.
	var r := CharacterPresenter.new()
	var removed := r.begin_hold(5.0, func() -> void: pass)
	var survivor := []
	removed.when_done(func(_o: int) -> void: survivor.append(r.begin_hold(5.0, func() -> void: pass)))
	r.teardown()
	check(not r.is_holding() and (survivor[0] as ActionHandle).is_done(), "Nothing outlives the character: a hold an observer started during teardown is settled and gone")

	# The hand follows the GESTURE, not the rank: a head-only gesture leaves an unarmed hand alone, a hand gesture raises it, and a plain gesture-rank hold raises nothing.
	var bare := _spawn(stage, "mira", false)
	bare.position.x = -8.0
	await _frames(30)
	var rest := _hand_height(bare)
	var nod := bare.gesture(&"nod")
	var nod_peak := 0.0
	var weight := 0.0
	for i in 40:
		await process_frame
		nod_peak = maxf(nod_peak, absf(_hand_height(bare) - rest))
		weight = maxf(weight, bare.presenter.gesture_hand().x)
	check(not nod.is_done() and bare.get_presentation_state() == &"nod" and nod_peak < 0.04 and weight == 0.0, "A head-only gesture (nod) does not raise an unarmed hand (hand moved %.3f m, weight %.2f)" % [nod_peak, weight])
	await create_timer(1.3).timeout
	check(nod.is_done() and nod.outcome == PresentationTypes.Outcome.COMPLETED, "...and completes")
	var raised := bare.gesture(&"acknowledge")
	var raise_weight := 0.0
	for i in 40:
		await process_frame
		raise_weight = maxf(raise_weight, bare.presenter.gesture_hand().x)
	check(raise_weight > 0.5, "A hand gesture does raise it (weight %.2f)" % raise_weight)
	raised.cancel()
	bare.presenter.begin_hold(1.0, func() -> void: pass, PresentationTypes.HOLD_GESTURE)
	await create_timer(0.4).timeout
	check(bare.presenter.gesture_hand() == Vector2.ZERO, "A gesture-rank hold that is not a gesture asks nothing of the hand")
	bare.queue_free()

	# Higher-priority actions end a running gesture (INTERRUPTED) and nothing is left holding; cover is persistent and coexists with it.
	for action in ["fire", "pick_up", "climb", "stairs", "hit", "inspect"]:
		var host := _spawn(stage, "mira", action == "fire")
		host.position.x = -12.0
		await _frames(30)
		var running := host.gesture(&"acknowledge")
		await _frames(15)
		match action:
			"fire":
				host.set_aiming(true)
				host.fire(Vector3(0, 1.2, 8))
			"pick_up": host.pick_up(host.global_position + Vector3(0, 0, 0.6))
			"climb": host.begin_climb(2.0)
			"stairs":
				var model := StairModel.new()
				model.direction = Vector3.BACK
				model.tread_depth = 0.3
				model.tread_rise = 0.15
				model.count = 6
				model.width = 1.2
				host.begin_stairs(model, true)
			"hit": host.react_hit()
			"inspect": host.inspect(Vector3(0, 0, 3), 1.0)
		check(running.is_done() and running.outcome == PresentationTypes.Outcome.INTERRUPTED and host.presenter.gesture_hand() == Vector2.ZERO, "%s during a gesture interrupts it (INTERRUPTED) and the hand is released" % action)
		host.queue_free()
	var covered := _spawn(stage, "mira", false)
	covered.position.x = -16.0
	await _frames(30)
	var under_cover := covered.gesture(&"acknowledge")
	await _frames(15)
	covered.enter_cover(0.0, false, 0.55, 0)
	await _frames(15)
	check(not under_cover.is_done(), "Cover is a persistent posture: it coexists with a running gesture")
	covered.queue_free()
