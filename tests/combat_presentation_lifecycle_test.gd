extends SceneTree
## Combat presentation lifecycle (Task 07 package 6). The attack, the hit return, the defeat and the rescue clock are advanced by the character's CharacterPresenter and observed through ActionHandles that
## settle exactly once. Part 1 drives AttackSequence, AimHold and the presenter's timed states with fakes (pure). Part 2 drives the production visual: attack from several poses, supersession and
## interruption precedence (hit, defeat, a newer attack, a requester's cancel, teardown), the persistent aim hold (never a handle), rescue advancement through the presenter in both hosts, and a production
## attack whose authoritative result is untouched by anything that happens to its handles. Structural headless checks, not a visual verdict.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const WORKBENCH := preload("res://art/characters/mira_0/demo/mira_0_pose_workbench.tscn")
const UNIT_SCENE := preload("res://units/tactical_unit.tscn")
const COMPLETED := PresentationTypes.Outcome.COMPLETED
const CANCELLED := PresentationTypes.Outcome.CANCELLED
const INTERRUPTED := PresentationTypes.Outcome.INTERRUPTED
const SKIPPED := PresentationTypes.Outcome.SKIPPED
const Phase := AttackSequence.Phase
var failures := 0
var checks := 0

func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

## Records every outcome a handle settles with.
func _watch(handle: ActionHandle) -> Array:
	var seen: Array = []
	handle.when_done(func(outcome: int) -> void: seen.append(outcome))
	return seen

class FakeHost extends AttackHost:
	var available := true
	var immediate := false
	var aligned := false
	var blend := 0.0
	var target := 0.0
	var raise_wait := 0.3
	var recover := 0.2
	var plays: Array[StringName] = []
	var raised := 0
	var released := 0
	var resumed := 0
	var ended := 0
	func sequence_available() -> bool: return available
	func immediate_release() -> bool: return immediate
	func weapon_aligned() -> bool: return aligned
	func aim_blend() -> float: return blend
	func aim_target() -> float: return target
	func max_raise_wait_seconds() -> float: return raise_wait
	func recover_seconds() -> float: return recover
	func begin_raise() -> void: raised += 1
	func release_aimed() -> void: released += 1
	func play_shot(state: StringName) -> void: plays.append(state)
	func resume_after_shot() -> void: resumed += 1
	func attack_ended() -> void: ended += 1

func _phases(sequence: AttackSequence) -> Array:
	var names := []
	for entry in sequence.timeline.phases:
		names.append(entry.phase)
	return names

func _run() -> void:
	# ================= Part 1: the pure lifecycle.
	var host := FakeHost.new()
	var seq := AttackSequence.new()
	var shots: Array = []
	seq.shot_released.connect(func(timeline: Dictionary) -> void: shots.append(timeline.get("forced", false)))
	var t := 0.0
	var h := seq.begin(host, t, &"shoot", &"rifle_idle", 0.0)
	var seen := _watch(h)
	var shot_seen := _watch(h.shot)
	check(seq.is_pending() and seq.phase == Phase.RAISE and host.raised == 1 and not h.shot.is_done(), "A request from an unaligned weapon starts at RAISE and waits")
	for i in 30:
		t += 1.0 / 60.0
		seq.advance(1.0 / 60.0, t)
	check(seq.phase == Phase.RECOVER or seq.phase == Phase.NONE or seq.phase == Phase.RELEASE, "After the raise wait the shot is forced (phase %d)" % seq.phase)
	check(shot_seen == [COMPLETED] and shots == [true] and seq.timeline.forced and is_equal_approx(float(seq.timeline.fire_t), snappedf(float(seq.timeline.fire_t), 0.0001)), "The shot handle settles COMPLETED once, at the forced fire")
	for i in 40:
		t += 1.0 / 60.0
		seq.advance(1.0 / 60.0, t)
	check(seen == [COMPLETED] and _phases(seq) == [Phase.RAISE, Phase.ALIGN, Phase.FIRE, Phase.RECOVER, Phase.RELEASE] and seq.phase == Phase.NONE and host.plays == [&"shoot"] and host.ended == 1,
		"The attack settles COMPLETED once, through RAISE, ALIGN, FIRE, RECOVER, RELEASE; the host is told it ended once: %s %s" % [seen, _phases(seq)])
	var late := []
	h.when_done(func(outcome: int) -> void: late.append(outcome))
	check(late == [COMPLETED] and await h.wait() == COMPLETED and await h.shot.wait() == COMPLETED, "A settled attack handle is safe to observe late")
	seq.cancel()
	check(seen == [COMPLETED], "Cancelling an attack that already completed changes nothing")

	# An aligned weapon fires at once; a character that cannot sequence shows the shot immediately (SKIPPED).
	host = FakeHost.new()
	host.aligned = true
	seq = AttackSequence.new()
	var h2 := seq.begin(host, 0.0, &"shoot_left", &"aim", 1.0)
	check(h2.shot.is_done() and h2.shot.outcome == COMPLETED and not seq.timeline.forced and host.plays == [&"shoot_left"] and seq.phase == Phase.RECOVER, "From an aligned weapon the shot is shown at once, not forced")
	host = FakeHost.new()
	host.available = false
	host.immediate = true
	seq = AttackSequence.new()
	var h3 := seq.begin(host, 0.0, &"shoot", &"carry_idle", 0.0)
	check(h3.is_done() and h3.outcome == SKIPPED and h3.shot.outcome == SKIPPED and host.plays == [&"shoot"] and seq.phase == Phase.NONE and host.raised == 0, "A character that cannot sequence shows the shot at once: both handles SKIPPED, nothing raised")

	# Interruption: before the shot, between attacks, by a requester's cancel, and with a re-entrant observer.
	host = FakeHost.new()
	seq = AttackSequence.new()
	var a := seq.begin(host, 0.0, &"shoot", &"rifle_idle", 0.0)
	var a_seen := _watch(a)
	var b := seq.begin(host, 0.1, &"shoot", &"aim", 0.5)
	check(a_seen == [INTERRUPTED] and a.shot.outcome == INTERRUPTED and seq.handle == b and not b.is_done(), "A newer attack ends the running one: both its handles INTERRUPTED once, the new one runs")
	var b_seen := _watch(b)
	b.cancel()
	check(b_seen == [CANCELLED] and b.shot.outcome == INTERRUPTED and seq.phase == Phase.NONE and host.ended >= 2, "A requester's cancel withdraws the attack: CANCELLED once, the shot handle is told, the host cleaned up")
	b.cancel()
	check(b_seen == [CANCELLED], "A second cancel is ignored")
	var chain := []
	var c := seq.begin(host, 0.0, &"shoot", &"rifle_idle", 0.0)
	c.when_done(func(outcome: int) -> void:
		var next := seq.begin(host, 0.5, &"shoot", &"rifle_idle", 0.0)
		chain.append([outcome, seq.handle == next and not next.is_done()]))
	seq.cancel()
	check(chain == [[INTERRUPTED, true]] and seq.is_pending(), "An observer may start the next attack from its callback: it finds a clean sequence")
	seq.cancel()

	# The aim hold is persistent state, never an action.
	var hold := AimHold.new()
	check(not hold.held and hold.update(0.1, false, true) == AimHold.Transition.NONE, "No hold, nothing to release")
	check(hold.update(0.1, true, true) == AimHold.Transition.ENGAGED and hold.held and hold.update(0.1, true, true) == AimHold.Transition.NONE, "A committed Aim engages the hold once")
	var released_at := 0.0
	var transition := AimHold.Transition.NONE
	while transition == AimHold.Transition.NONE and released_at < 3.0:
		transition = hold.update(0.1, false, true)
		released_at += 0.1
	check(transition == AimHold.Transition.RELEASED and not hold.held and released_at > 0.9 and released_at < 1.3, "After the committed Aim ends the sights stay up for the grace period (%.1f s)" % released_at)
	hold.engage()
	check(hold.update(0.016, false, false) == AimHold.Transition.RELEASED, "Another action taking over ends the hold at once")
	hold.engage()
	hold.clear()
	check(not hold.held and hold.release_left == 0.0, "clear() leaves nothing of the hold")

	# The presenter's timed states: counted by its own tick, from the frame after they began, settled once.
	var presenter := CharacterPresenter.new(null)
	var ran := []
	var hold_handle := presenter.begin_hold(0.2, func() -> void: ran.append(presenter.time))
	var hold_seen := _watch(hold_handle)
	var ticks := 0
	while not hold_handle.is_done() and ticks < 60:
		await process_frame
		presenter.tick(1.0 / 60.0)
		ticks += 1
	check(hold_seen == [COMPLETED] and ran.size() == 1 and ticks >= 12 and ticks <= 14 and not presenter.is_holding(), "A hold of 0.2 s runs its due callback once and settles COMPLETED after %d frames" % ticks)
	var first := presenter.begin_hold(5.0, func() -> void: pass)
	var first_seen := _watch(first)
	var second := presenter.begin_hold(5.0, func() -> void: pass)
	check(first_seen == [INTERRUPTED] and presenter.is_holding() and not second.is_done(), "A newer hold supersedes the running one (INTERRUPTED once)")
	var d1 := presenter.begin_defeat(5.0)
	check(presenter.begin_defeat(5.0) == d1 and presenter.is_defeating(), "A repeated defeat request while it runs is the same defeat")
	var d1_seen := _watch(d1)
	var second_seen := _watch(second)
	presenter.teardown()
	check(d1_seen == [INTERRUPTED] and second_seen == [INTERRUPTED] and not presenter.is_holding() and not presenter.is_defeating() and not presenter.attack.is_active() and not presenter.aim.held,
		"Teardown settles every outstanding handle INTERRUPTED and leaves no hold, defeat, attack or aim")

	# ================= Part 2: the production visual.
	await _production_visual()
	await _rescue_through_the_presenter()
	await _authoritative_attack()

	print("Combat presentation lifecycle: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _visual() -> Array:
	var stage := Node3D.new()
	root.add_child(stage)
	var v: UnitVisualAdapter = VISUAL.instantiate()
	stage.add_child(v)
	await _frames(15)
	return [stage, v]

func _target(v: UnitVisualAdapter) -> Vector3:
	return v.global_position + v.global_basis.z * 6.0

func _drop(stage: Node) -> void:
	stage.queue_free()
	await _frames(2)

func _production_visual() -> void:
	var pair := await _visual()
	var stage: Node3D = pair[0]
	var v: UnitVisualAdapter = pair[1]
	var p := v.presenter

	# A normal attack: the shot handle settles first (the shot is shown), the attack when the release is over; nothing is left behind.
	var attack := v.present_attack(_target(v))
	var attack_seen := _watch(attack)
	var shot_seen := _watch(attack.shot)
	check(not attack.shot.is_done() and p.attack.is_pending() and v.rig.readiness.has_request(AttackSequence.SOURCE), "An attack from idle raises the weapon first: the shot is pending and the weapon-up request is held")
	var guard := 0
	while not attack.shot.is_done() and guard < 200:
		await process_frame
		guard += 1
	check(shot_seen == [COMPLETED] and attack_seen.is_empty() and v.get_presentation_state() in [&"shoot", &"aim", &"rifle_idle"], "The shot handle settles COMPLETED when the shot is shown, before the attack is over (%d frames)" % guard)
	guard = 0
	while not attack.is_done() and guard < 200:
		await process_frame
		guard += 1
	check(attack_seen == [COMPLETED] and not p.attack.is_active() and not v.rig.readiness.has_request(AttackSequence.SOURCE) and v.attack_plan.is_empty(), "The attack settles COMPLETED once; no readiness request and no cover plan is left")

	# A repeated attack supersedes the first (INTERRUPTED once); the second completes; one shot is shown.
	var shots := [0]
	p.attack.shot_released.connect(func(_t: Dictionary) -> void: shots[0] += 1)
	var first := v.present_attack(_target(v))
	var first_seen := _watch(first)
	await _frames(5)
	var second := v.present_attack(_target(v))
	var second_seen := _watch(second)
	await _frames(120)
	check(first_seen == [INTERRUPTED] and second_seen == [COMPLETED] and shots[0] == 1, "A repeated attack supersedes the first: INTERRUPTED once, the second COMPLETED, one shot shown (%d)" % shots[0])
	check(v.presenter.time > 0.0 and v.presenter.attack.timeline.has("end_t"), "The attack's timeline is recorded in presentation time")

	# Hit during an attack: the attack is interrupted, the hit holds then returns to idle (COMPLETED), a newer hit supersedes.
	var raising := v.present_attack(_target(v))
	var raising_seen := _watch(raising)
	var raising_shot := _watch(raising.shot)
	await _frames(3)
	var hit := v.present_hit()
	var hit_seen := _watch(hit)
	check(raising_seen == [INTERRUPTED] and raising_shot == [INTERRUPTED] and v.get_presentation_state() == &"hit" and not v.rig.readiness.has_request(AttackSequence.SOURCE), "A hit during the attack interrupts it (both handles once) and owns the pose")
	var t0 := p.time
	var returned_after := 0.0
	guard = 0
	while not hit.is_done() and guard < 200:
		await process_frame
		guard += 1
	returned_after = p.time - t0
	check(hit_seen == [COMPLETED] and absf(returned_after - v.hit_return_seconds) < 0.05 and v.get_presentation_state() != &"hit", "The hit returns to idle after hit_return_seconds of presentation time (%.3f s) and settles COMPLETED once" % returned_after)
	var h1 := v.present_hit()
	var h1_seen := _watch(h1)
	await _frames(5)
	var h2 := v.present_hit()
	check(h1_seen == [INTERRUPTED] and not h2.is_done(), "A newer hit supersedes the running one")
	var then_attack := v.present_attack(_target(v))
	var h2_seen := _watch(h2)
	check(h2_seen == [INTERRUPTED], "An attack requested during a hit takes over: the hit's return is cancelled, it settles INTERRUPTED")
	then_attack.cancel()
	await _frames(3)

	# Defeat during an attack and an aim: everything ends, nothing is left, the defeat settles once, a repeat is the same defeat.
	v.present_aim()
	check(p.aim.held and not p.is_holding(), "The aim hold is persistent state: it holds, and no handle is pending for it")
	var doomed := v.present_attack(_target(v))
	var doomed_seen := _watch(doomed)
	await _frames(4)
	var states := []
	v.presentation_state_changed.connect(func(state: StringName) -> void: states.append(state))
	var defeat := v.present_defeat()
	var defeat_seen := _watch(defeat)
	check(doomed_seen == [INTERRUPTED] and not p.attack.is_active() and not p.aim.held and not v.rig.readiness.has_request(AttackSequence.SOURCE) and not p.is_holding() and v.get_presentation_state() == &"defeat",
		"Defeat during an attack and a held aim ends both: attack INTERRUPTED, no aim hold, no readiness request, no pending hold")
	var again := v.present_defeat()
	await _frames(2)
	check(again == defeat and states.count(&"defeat") == 1, "A repeated defeat request is the same defeat and does not restart the clip")
	var hit_after := v.present_hit()
	check(hit_after.outcome == CANCELLED and defeat_seen.is_empty(), "A hit after the defeat is refused (CANCELLED) without disturbing the defeat handle")
	var clip: float = v.rig.animation_controller.state_length(&"defeat")
	check(clip > 1.0, "The defeat reports its clip length (%.2f s)" % clip)
	t0 = p.time
	guard = 0
	while not defeat.is_done() and guard < 400:
		await process_frame
		guard += 1
	check(defeat_seen == [COMPLETED] and absf((p.time - t0) - clip) < 0.1, "The defeat settles COMPLETED once, after the clip's own length (%.2f s)" % (p.time - t0))
	await _drop(stage)

	# Defeat during a rescue.
	pair = await _visual()
	stage = pair[0]
	v = pair[1]
	v.preview_carrying = true
	var lift := v.rig.begin_pickup(v.rig.character_root.global_position + v.rig.character_root.global_basis.orthonormalized().z * 1.0)
	var lift_seen := _watch(lift)
	await _frames(30)
	var rescue_defeat := v.present_defeat()
	check(lift_seen == [INTERRUPTED] and not v.rig.interaction_active() and not v.presenter.postures.has_request(CharacterRig.RESCUE_POSTURE_SOURCE) and not rescue_defeat.is_done(), "Defeat during a rescue interrupts the lift and releases its posture; the defeat itself runs")
	v.present_carry_released()
	check(not is_instance_valid(v.rig.carry_passenger) and not v.presenter.is_holding(), "...and the tactical release leaves no passenger and no hold")
	await _drop(stage)

	# Teardown with outstanding handles: an attack in flight and a hit hold, on two characters.
	pair = await _visual()
	stage = pair[0]
	v = pair[1]
	var pending_attack := v.present_attack(_target(v))
	var pending_seen := _watch(pending_attack)
	var pending_shot := _watch(pending_attack.shot)
	var waiter := []
	var waiting := func() -> void: waiter.append(await pending_attack.wait())
	waiting.call()
	var presenter_ref := v.presenter
	await _frames(3)
	v.queue_free()
	await _frames(2)
	check(pending_seen == [INTERRUPTED] and pending_shot == [INTERRUPTED] and waiter == [INTERRUPTED] and not presenter_ref.attack.is_active() and presenter_ref.postures.request_count() == 0,
		"Removing the character mid-attack interrupts both handles and releases a pending wait: %s %s %s" % [pending_seen, pending_shot, waiter])
	await _drop(stage)
	pair = await _visual()
	stage = pair[0]
	v = pair[1]
	var pending_hit := v.present_hit()
	var pending_hit_seen := _watch(pending_hit)
	await _frames(3)
	v.queue_free()
	await _frames(2)
	check(pending_hit_seen == [INTERRUPTED], "Removing the character during a hit interrupts the hold's handle: %s" % [pending_hit_seen])
	await _drop(stage)

func _rescue_through_the_presenter() -> void:
	# The presenter advances the rescue clock, once per frame, and the tactical visual no longer does it from its weapon-pose update.
	var pair := await _visual()
	var stage: Node3D = pair[0]
	var v: UnitVisualAdapter = pair[1]
	v.preview_carrying = true
	v.rig.begin_pickup(v.rig.character_root.global_position + v.rig.character_root.global_basis.orthonormalized().z)
	var t0 := v.rig.rescue_interaction.time
	var p0 := v.presenter.time
	await _frames(30)
	var lift_time := v.rig.rescue_interaction.time - t0
	var presented := v.presenter.time - p0
	check(absf(lift_time - presented) < 0.002 and lift_time > 0.3, "The tactical host advances the lift by exactly the presentation time, once per frame (%.4f of %.4f s)" % [lift_time, presented])
	var before := v.rig.rescue_interaction.time
	v.presenter.advance_actions(0.25)
	var after_first := v.rig.rescue_interaction.time
	v.presenter.advance_actions(0.25)
	check(is_equal_approx(after_first - before, 0.25) and is_equal_approx(v.rig.rescue_interaction.time, after_first), "The stage advances the clock once per engine frame: a second call in the same frame advances nothing")
	var carrier_time := v.rig.rescue_interaction.time
	v.preview_carrying = false
	await _frames(5)
	check(is_equal_approx(v.rig.rescue_interaction.time, carrier_time), "A character that is not a loaded carrier does not advance the clock (as it never applied it)")
	await _drop(stage)

	# The workbench host uses the same stage.
	var bench: Node3D = WORKBENCH.instantiate()
	root.add_child(bench)
	await _frames(15)
	bench.rig.begin_pickup(bench.rig.character_root.global_position + bench.rig.character_root.global_basis.orthonormalized().z)
	var b0: float = bench.rig.rescue_interaction.time
	var bp0: float = bench.presenter.time
	await _frames(30)
	var bench_lift: float = bench.rig.rescue_interaction.time - b0
	var bench_presented: float = bench.presenter.time - bp0
	check(absf(bench_lift - bench_presented) < 0.002 and bench_lift > 0.3, "The workbench advances the lift through the same presenter stage (%.4f of %.4f s)" % [bench_lift, bench_presented])
	bench.rig.rescue_interaction.paused = true
	var held_at: float = bench.rig.rescue_interaction.time
	await _frames(5)
	check(is_equal_approx(bench.rig.rescue_interaction.time, held_at), "The workbench's pause still holds the timeline")
	bench.queue_free()
	await _frames(2)

func _authoritative_attack() -> void:
	# A production attack through the tactical presenter: whatever happens to its handles, the committed result stands.
	var grid := GridManager.new()
	root.add_child(grid)
	var registry := TacticalActorRegistry.new()
	var presenter := TacticalActionPresenter.new()
	root.add_child(presenter)
	presenter.setup(registry, grid, null, func(): return false, Callable())
	var attacker := UNIT_SCENE.instantiate() as TacticalUnit
	attacker.tactical_id = &"shooter"
	attacker.show_world_hud = false
	root.add_child(attacker)
	var victim := UNIT_SCENE.instantiate() as TacticalUnit
	victim.tactical_id = &"victim"
	victim.faction = TacticalUnit.Faction.ENEMY
	victim.show_world_hud = false
	victim.position = Vector3(0, 0, 6)
	root.add_child(victim)
	await _frames(3)
	registry.register_actor(attacker)
	registry.register_actor(victim)
	var result := AttackActionResult.new()
	result.request = TacticalActionRequest.attack(&"shooter", &"victim", 0, TacticalActionRequest.Source.SYSTEM)
	result.did_hit = true
	result.damage = 10
	result.target_position = victim.global_position
	var hp_before := victim.stats.current_hp
	var ap_before := attacker.stats.current_ap
	var snapshot := [result.did_hit, result.damage, result.target_defeated, result.hit_chance, result.actor_ap_after]
	var done := [false]
	var run := func() -> void:
		await presenter.present_attack(result)
		done[0] = true
	run.call()
	await _frames(2)
	var handle: AttackHandle = attacker.visual_adapter.presenter.attack.handle
	check(handle != null and not handle.shot.is_done(), "The tactical presenter is waiting on the production attack's shot handle")
	handle.cancel()   # the visual attack is withdrawn mid-raise
	var guard := 0
	while not done[0] and guard < 200:
		await process_frame
		guard += 1
	check(done[0] and handle.outcome == CANCELLED and handle.shot.outcome == INTERRUPTED, "Cancelling the handle releases the tactical wait at once (%d frames)" % guard)
	check([result.did_hit, result.damage, result.target_defeated, result.hit_chance, result.actor_ap_after] == snapshot and attacker.stats.current_ap == ap_before and result.presentation_error.is_empty(),
		"The authoritative result and the attacker's AP are untouched by what happened to the visual handles")
	check(victim.stats.current_hp == hp_before, "...presentation applied no damage (that was committed elsewhere)")
	attacker.queue_free()
	victim.queue_free()
	presenter.queue_free()
	grid.queue_free()
	await _frames(2)
