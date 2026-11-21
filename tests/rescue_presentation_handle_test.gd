extends SceneTree
## The rescue presentation lifecycle (Task 07 package 5): the lift and the release are ONE operation each, observed through an ActionHandle that settles exactly once (COMPLETED, SKIPPED, INTERRUPTED,
## CANCELLED), and the carrier's posture is an ACTION-priority request in the shared PostureArbiter that never outlives the operation. Part 1 drives the production visual alone (every phase, repeated and
## re-entrant requests, teardown); part 2 drives a production rescue in the mission and proves the handle never changes the authoritative result. Structural headless checks, not a visual verdict.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const SOURCE := CharacterRig.RESCUE_POSTURE_SOURCE
const TEST_COVER := &"test/cover"
var failures := 0
var checks := 0
var _stage: Node3D

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

func _new_visual() -> UnitVisualAdapter:
	_stage = Node3D.new()
	root.add_child(_stage)
	var v: UnitVisualAdapter = VISUAL.instantiate()
	_stage.add_child(v)
	v.preview_carrying = true   # a bare visual has no tactical unit: this is what makes it a loaded carrier (the timeline only advances while carrying)
	await _frames(12)
	return v

func _drop(v: UnitVisualAdapter) -> void:
	_stage.queue_free()
	await _frames(2)

func _place(v: UnitVisualAdapter) -> Vector3:
	return v.rig.character_root.global_position + v.rig.character_root.global_basis.orthonormalized().z * 1.0

func _passengers(node: Node) -> int:
	return node.find_children("RescuePassenger", "", true, false).size()

## Records every outcome a handle settles with (an array that can be shared with a callback).
func _watch(handle: ActionHandle) -> Array:
	var seen: Array = []
	handle.when_done(func(outcome: int) -> void: seen.append(outcome))
	return seen

func _run() -> void:
	var v := await _new_visual()
	var home := v.position
	var COMPLETED := PresentationTypes.Outcome.COMPLETED
	var CANCELLED := PresentationTypes.Outcome.CANCELLED
	var INTERRUPTED := PresentationTypes.Outcome.INTERRUPTED
	var SKIPPED := PresentationTypes.Outcome.SKIPPED

	# ---- 1. A normal pickup: one handle, a posture request that exists for the lift only, the carry afterwards.
	check(v.rig.rescue_presentation() == null and not v.presenter.postures.has_request(SOURCE), "Idle: no rescue handle and no rescue posture request")
	var pickup: ActionHandle = v.rig.begin_pickup(_place(v))
	var seen := _watch(pickup)
	await _frames(40)
	check(not pickup.is_done() and v.rig.rescue_presentation() == pickup, "The lift is a running operation with a pending handle")
	check(v.presenter.postures.has_request(SOURCE) and v.presenter.postures.resolved_source() == SOURCE and v.presenter.postures.resolved_exact(), "...and the carrier's bend is an exact request in the posture arbiter")
	check(v.presenter.postures.resolved_depth() > 0.0 and v.rig.crouch_modifier.depth > 0.0, "...which the rig applied (depth %.3f)" % v.rig.crouch_modifier.depth)
	# Repeated pickup requests are the same operation, not a second pickup.
	var time_before := v.rig.rescue_interaction.time
	var again: ActionHandle = v.rig.begin_pickup(_place(v))
	check(again == pickup and v.rig.rescue_interaction.time >= time_before and _passengers(v) == 1, "A repeated pickup request returns the same handle, does not restart the timeline and adds no second passenger")
	check(v.rig.begin_release().is_done() and v.rig.begin_release().outcome == SKIPPED, "A release requested during the lift is rejected at once (SKIPPED) and the lift goes on: %s" % [v.rig.interaction_active()])
	v.rig.rescue_interaction.scrub(v.rig.rescue_interaction.duration() - 0.05)
	await _frames(8)
	check(seen == [COMPLETED] and pickup.is_done(), "The lift settles COMPLETED exactly once: %s" % [seen])
	check(not v.presenter.postures.has_request(SOURCE) and v.rig.rescue_presentation() == null, "...the posture request is released and nothing is pending")
	check(is_instance_valid(v.rig.carry_passenger) and v.rig.carry_contacts_active() and v.rig.is_weapon_stowed(), "The carry that follows holds the passenger and the slung rifle")
	var settled_late := []
	pickup.when_done(func(outcome: int) -> void: settled_late.append(outcome))
	check(settled_late == [COMPLETED] and await pickup.wait() == COMPLETED, "A settled handle is still safe to observe: when_done runs at once and wait() does not hang")

	# ---- 2. Release: repeated requests, completion, nothing left behind.
	var release: ActionHandle = v.rig.begin_release()
	var release_seen := _watch(release)
	check(v.rig.begin_release() == release, "A repeated release request returns the same handle")
	await _frames(20)
	check(v.presenter.postures.has_request(SOURCE) and not release.is_done(), "The release is running, with its own posture request")
	v.rig.rescue_interaction.scrub(v.rig.rescue_interaction.duration() - 0.05)
	await _frames(8)
	check(release_seen == [COMPLETED] and _passengers(v) == 0 and not v.presenter.postures.has_request(SOURCE), "The release settles COMPLETED once, the passenger is gone and no posture request is left")
	check(v.rig.begin_release().is_done() and v.rig.begin_release().outcome == SKIPPED, "Releasing with nobody carried is rejected at once (SKIPPED)")

	# ---- 3. Cover underneath: a context request keeps its place, the lift wins while it runs, the cover takes the body back.
	v.presenter.postures.set_posture(TEST_COVER, PresentationTypes.Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.0, 0.30)
	await _frames(40)
	check(absf(v.rig.crouch_modifier.depth - 0.30) < 0.02, "Setup: the cover request is followed (depth %.3f)" % v.rig.crouch_modifier.depth)
	var lift: ActionHandle = v.rig.begin_pickup(_place(v))
	await _frames(30)
	check(v.presenter.postures.resolved_source() == SOURCE and v.presenter.postures.has_request(TEST_COVER), "During the lift the rescue request wins and the cover request is untouched underneath")
	lift.cancel()
	await _frames(2)
	check(lift.outcome == CANCELLED and v.presenter.postures.resolved_source() == TEST_COVER and absf(v.rig.crouch_modifier.depth - 0.30) < 0.02,
		"Cancelled, the cover takes the body back at once (source %s, depth %.3f)" % [v.presenter.postures.resolved_source(), v.rig.crouch_modifier.depth])
	check(v.presenter.postures.has_request(TEST_COVER) and not v.presenter.postures.has_request(SOURCE) and _passengers(v) == 0 and not v.rig.interaction_active(), "...nothing of the lift is left and the cover request was never cleared by it")
	v.presenter.postures.release(&"test/unrelated")
	check(v.presenter.postures.has_request(TEST_COVER), "Releasing some other source does not clear anyone's request")
	v.presenter.postures.release(TEST_COVER)
	await _frames(40)
	check(v.rig.crouch_modifier.depth < 0.01, "With no request left the body stands again (%.3f)" % v.rig.crouch_modifier.depth)

	# ---- 4. Cancellation before the passenger is attached: a reserved handle that never started.
	var reserved: ActionHandle = v.rig.reserve_rescue_handle()
	check(v.rig.reserve_rescue_handle() == reserved and v.rig.rescue_presentation() == null, "A reserved handle is one operation and is not 'running' before its timeline starts")
	var reserved_seen := _watch(reserved)
	reserved.cancel()
	check(reserved_seen == [CANCELLED] and not v.rig.interaction_active() and _passengers(v) == 0 and not v.presenter.postures.has_request(SOURCE), "Cancelled before attachment: nothing attached, nothing requested, the handle settled CANCELLED")
	reserved.cancel()
	check(reserved_seen == [CANCELLED], "A second cancel is ignored: the first outcome stands")

	# ---- 5. Cancelled mid-pickup leaves nothing; cancelled mid-release keeps the carry.
	var p2: ActionHandle = v.rig.begin_pickup(_place(v))
	v.rig.rescue_interaction.paused = true
	v.rig.rescue_interaction.scrub(1.8)
	await _frames(4)
	var p2_seen := _watch(p2)
	p2.cancel()
	await _frames(2)
	check(p2_seen == [CANCELLED] and _passengers(v) == 0 and not v.rig.is_weapon_stowed() and v.rig.crouch_modifier.depth < 0.01 and v.rig.crouch_modifier.kneel < 0.01 and v.position.is_equal_approx(home),
		"A pickup cancelled mid-lift: no passenger, the rifle back in hand, the carrier upright at its own place (seen %s, passengers %d, stowed %s, depth %.3f, kneel %.3f, at %s)" % [p2_seen, _passengers(v), v.rig.is_weapon_stowed(), v.rig.crouch_modifier.depth, v.rig.crouch_modifier.kneel, v.position])
	v.rig.rescue_interaction.paused = false
	v.rig.begin_carry()
	var r2: ActionHandle = v.rig.begin_release()
	v.rig.rescue_interaction.paused = true
	v.rig.rescue_interaction.scrub(1.2)
	await _frames(4)
	var r2_seen := _watch(r2)
	r2.cancel()
	await _frames(2)
	check(r2_seen == [CANCELLED] and is_instance_valid(v.rig.carry_passenger) and v.rig.carry_passenger.lift == 1.0 and not v.rig.interaction_active() and not v.presenter.postures.has_request(SOURCE),
		"A release cancelled midway leaves the passenger carried, steady across the shoulders")
	v.rig.rescue_interaction.paused = false

	# ---- 6. Interruption after attachment: the carrier loses the passenger (the tactical layer put it down).
	v.rig.end_carry()
	var p3: ActionHandle = v.rig.begin_pickup(_place(v))
	v.rig.rescue_interaction.paused = true
	v.rig.rescue_interaction.scrub(2.4)
	await _frames(4)
	var p3_seen := _watch(p3)
	v.present_carry_released()
	await _frames(3)
	check(p3_seen == [INTERRUPTED] and _passengers(v) == 0 and not v.presenter.postures.has_request(SOURCE) and v.rig.crouch_modifier.depth < 0.01 and not v.rig.interaction_active(),
		"Interrupted after attachment: INTERRUPTED once, no passenger, no request, upright")
	v.present_carry_released()
	check(p3_seen == [INTERRUPTED], "A repeated interruption changes nothing")
	v.rig.rescue_interaction.paused = false

	# ---- 7. Defeat during a pickup, and while carrying.
	var p4: ActionHandle = v.rig.begin_pickup(_place(v))
	v.rig.rescue_interaction.paused = true
	v.rig.rescue_interaction.scrub(1.5)
	await _frames(4)
	var p4_seen := _watch(p4)
	v.present_defeat()
	await _frames(3)
	check(p4_seen == [INTERRUPTED] and not v.rig.interaction_active() and not v.presenter.postures.has_request(SOURCE), "Defeat during a pickup interrupts its operation and releases its posture")
	v.present_carry_released()
	check(_passengers(v) == 0, "...and the tactical layer's release then leaves no passenger on the fallen carrier")
	v.rig.rescue_interaction.paused = false
	v.rig.end_carry()
	v.rig.begin_carry()
	v.present_defeat()
	check(is_instance_valid(v.rig.carry_passenger) and v.rig.rescue_presentation() == null, "Defeat while carrying has no operation to interrupt; the passenger is left to the authoritative release")
	v.present_carry_released()
	check(_passengers(v) == 0 and not v.presenter.postures.has_request(SOURCE), "...which frees it")

	# ---- 8. Skipped: run to its end at once.
	var p5: ActionHandle = v.rig.begin_pickup(_place(v))
	var p5_seen := _watch(p5)
	await _frames(5)
	v.rig.finish_interaction_now()
	check(p5_seen == [SKIPPED] and v.rig.carry_passenger.lift == 1.0 and not v.presenter.postures.has_request(SOURCE), "Run to its end at once, the lift settles SKIPPED in its final state")
	v.rig.end_carry()

	# ---- 9. Several observers, and one that re-enters in its callback.
	var p6: ActionHandle = v.rig.begin_pickup(_place(v))
	var first := _watch(p6)
	var second := _watch(p6)
	var nested: Array = []
	p6.when_done(func(outcome: int) -> void:
		var inner: ActionHandle = v.rig.begin_release()
		nested.append([outcome, inner.is_done(), inner == p6, v.rig.rescue_presentation() == inner]))
	var third := _watch(p6)
	v.rig.rescue_interaction.scrub(v.rig.rescue_interaction.duration() - 0.05)
	await _frames(8)
	check(first == [COMPLETED] and second == [COMPLETED] and third == [COMPLETED], "Every observer is told once, in the same outcome: %s %s %s" % [first, second, third])
	check(nested.size() == 1 and nested[0][0] == COMPLETED and not nested[0][1] and not nested[0][2] and nested[0][3], "An observer may start the release from inside the callback: it finds a clean rig and gets a fresh, running handle: %s" % [nested])
	check(v.rig.rescue_presentation() != null and v.rig.interaction_active(), "...which is running now")
	v.rig.end_carry()

	# ---- 10. Teardown during an active action: the observer is told, nothing waits, nothing is left.
	var p7: ActionHandle = v.rig.begin_pickup(_place(v))
	var p7_seen := _watch(p7)
	var waiter: Array = []
	var wait_for := func() -> void:
		waiter.append(await p7.wait())
	wait_for.call()
	await _frames(10)
	var presenter_ref := v.presenter
	v.queue_free()   # the character is freed under the running operation, as a level teardown or a defeat clean-up does
	await _frames(2)
	check(p7_seen == [INTERRUPTED] and waiter == [INTERRUPTED], "Leaving the tree mid-lift interrupts the operation and releases a pending wait: %s %s" % [p7_seen, waiter])
	check(presenter_ref.postures.request_count() == 0, "...and no posture request survives the character")
	await _drop(null)

	await _production_rescue()

	print("Rescue presentation handle: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

# ---- Part 2: through the production mission.
func _level() -> BattleLevel:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(3, 2, false, 1, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 2, false))
	root.add_child(level)
	return level

func _arrive(level: BattleLevel, unit: TacticalUnit, target: TacticalUnit, offset := Vector3i.LEFT) -> void:
	var grid := level.battle_controller.grid_manager
	var cell := grid.get_unit_grid(target) + offset
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

## Starts the rescue action without waiting for it: the returned array receives its result when the action returns.
func _start_rescue(level: BattleLevel, carrier: TacticalUnit, target: TacticalUnit) -> Array:
	var result: Array = []
	var run := func() -> void:
		result.append(await level.objective_manager.try_rescue(carrier, target))
	run.call()
	return result

func _result_of(result: Array) -> bool:
	var started := Time.get_ticks_msec()
	while result.is_empty() and Time.get_ticks_msec() - started < 9000:
		await process_frame
	return not result.is_empty() and bool(result[0])

func _begin_level() -> BattleLevel:
	var level := _level()
	await create_timer(0.3).timeout
	level.action_camera_director.frequency = level.action_camera_director.Frequency.OFF
	return level

func _production_rescue() -> void:
	var COMPLETED := PresentationTypes.Outcome.COMPLETED
	var CANCELLED := PresentationTypes.Outcome.CANCELLED
	var INTERRUPTED := PresentationTypes.Outcome.INTERRUPTED
	# A completed lift: the action returns after it (observing the handle) and the handle says COMPLETED.
	var level := await _begin_level()
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	_arrive(level, carrier, target)
	var adapter := carrier.visual_adapter
	var rescue_task := _start_rescue(level, carrier, target)
	await create_timer(0.4).timeout
	var handle := adapter.rig.rescue_presentation()
	check(handle != null and not handle.is_done(), "A production rescue runs one presentation handle")
	var seen := _watch(handle) if handle != null else []
	var accepted: bool = await _result_of(rescue_task)
	check(accepted and seen == [COMPLETED] and carrier.is_carrying_unit() and not target.visible, "The rescue action returns once the lift has settled COMPLETED: %s" % [seen])
	check(not adapter.presenter.postures.has_request(SOURCE), "...and the lift's posture request is gone")
	level.queue_free()
	await _frames(2)

	# The handle never decides the result: cancelling the visual operation leaves the authoritative rescue as it was.
	level = await _begin_level()
	target = level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	carrier = level.turn_manager.player_units[0]
	_arrive(level, carrier, target)
	adapter = carrier.visual_adapter
	var task2 := _start_rescue(level, carrier, target)
	await create_timer(1.0).timeout
	var h2 := adapter.rig.rescue_presentation()
	check(h2 != null, "Setup: a lift is running")
	if h2 != null:
		h2.cancel()
	var accepted2: bool = await _result_of(task2)
	check(accepted2 and carrier.is_carrying_unit() and not target.visible and carrier.stats.current_hp > 0,
		"Cancelling the visual operation does not change the authoritative result: the rescue was accepted and the carrier still carries (accepted %s)" % accepted2)
	check(not is_instance_valid(adapter.rig.carry_passenger) and not adapter.presenter.postures.has_request(SOURCE), "...only the visual lift was withdrawn")
	level.queue_free()
	await _frames(2)

	# The carrier is lost during the lift: the handle is interrupted, and the authoritative recovery is untouched.
	level = await _begin_level()
	target = level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	carrier = level.turn_manager.player_units[0]
	_arrive(level, carrier, target)
	adapter = carrier.visual_adapter
	_start_rescue(level, carrier, target)
	await create_timer(1.4).timeout
	var h3 := adapter.rig.rescue_presentation()
	var seen3 := _watch(h3) if h3 != null else []
	carrier.stats.take_damage(1000)
	await create_timer(0.4).timeout
	check(seen3 == [INTERRUPTED] and target.visible and target.awaiting_rescue and not adapter.presenter.postures.has_request(SOURCE), "A carrier lost mid-lift interrupts the handle; the target is recoverable again: %s" % [seen3])
	level.queue_free()
	await _frames(2)

	# A rescue decided while the carrier is still far: the reserved handle is interrupted when the carrier is lost, and a cancel stops it from starting on arrival.
	level = await _begin_level()
	target = level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	carrier = level.turn_manager.player_units[0]
	var grid := level.battle_controller.grid_manager
	grid.update_unit_position(carrier, carrier.grid_position, grid.get_unit_grid(target) + Vector3i.LEFT)   # decided "there", the body still far away
	adapter = carrier.visual_adapter
	_start_rescue(level, carrier, target)
	await create_timer(0.3).timeout
	var pending := adapter.rig.reserve_rescue_handle()
	var pending_seen := _watch(pending)
	check(adapter.pickup_pending() and not pending.is_done() and adapter.rig.rescue_presentation() == null, "A held pickup has a reserved handle that is not yet running")
	carrier.stats.take_damage(1000)
	await create_timer(0.4).timeout
	check(pending_seen == [INTERRUPTED] and not adapter.pickup_pending(), "Losing the carrier before it arrives interrupts the reserved handle and leaves nothing pending: %s" % [pending_seen])
	level.queue_free()
	await _frames(2)

	level = await _begin_level()
	target = level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	carrier = level.turn_manager.player_units[0]
	grid = level.battle_controller.grid_manager
	grid.update_unit_position(carrier, carrier.grid_position, grid.get_unit_grid(target) + Vector3i.LEFT)
	adapter = carrier.visual_adapter
	_start_rescue(level, carrier, target)
	await create_timer(0.3).timeout
	var held := adapter.rig.reserve_rescue_handle()
	held.cancel()
	check(not adapter.pickup_pending() and not adapter.rig.interaction_active(), "Cancelling a pickup that was waiting for its carrier leaves nothing pending, so no lift starts on arrival")
	level.queue_free()
	await _frames(2)
