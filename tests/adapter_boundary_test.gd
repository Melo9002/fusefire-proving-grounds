extends SceneTree
## The tactical adapter's boundary (Task 07 package 7). The adapter translates tactical facts (the committed Aim, a rescue waiting for its carrier, a defeat) into typed requests; the presenter owns what
## follows: the committed Aim's progression, the pending pickup and its reserved handle, the defeat and the removal floor, and the precedence between competing requests. Production characters, not mocks.
## Precedence (Task 04, section 14, as implemented): defeat is terminal and refuses every later request; a rescue lift already committed is not cut short by a cosmetic hit (SKIPPED); a hit ends an attack; a
## newer attack ends a running hit reaction (the committed shot is shown on time); persistent aim never blocks anything and survives hit and attack.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const UNIT_SCENE := preload("res://units/tactical_unit.tscn")
const COMPLETED := PresentationTypes.Outcome.COMPLETED
const CANCELLED := PresentationTypes.Outcome.CANCELLED
const INTERRUPTED := PresentationTypes.Outcome.INTERRUPTED
const SKIPPED := PresentationTypes.Outcome.SKIPPED
var failures := 0
var checks := 0
var _aim_presenter: CharacterPresenter

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

func _watch(handle: ActionHandle) -> Array:
	var seen: Array = []
	handle.when_done(func(outcome: int) -> void: seen.append(outcome))
	return seen

func _unit() -> TacticalUnit:
	var unit := UNIT_SCENE.instantiate() as TacticalUnit
	unit.show_world_hud = false
	root.add_child(unit)
	await _frames(4)
	return unit

func _run() -> void:
	await _committed_aim()
	await _defeat_removal()
	await _precedence()
	await _pending_pickup()
	await _facing_hint()
	print("Adapter boundary: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _committed_aim() -> void:
	# The presenter never reads a tactical type: the adapter reports the committed Aim as a typed input.
	for path in ["res://presentation/characters/presenter/character_presenter.gd", "res://presentation/characters/presenter/aim_hold.gd"]:
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("tactical_state") and not text.contains("TacticalUnit"), "%s reads no tactical state" % path.get_file())
	var unit := await _unit()
	var p := unit.visual_adapter.presenter
	var events: Array = []
	_aim_presenter = p   # a member, so the callback below does not capture the presenter it is connected to (a reference cycle)
	p.aim_hold_changed.connect(func(transition: int, _settling: bool) -> void: events.append([transition, _aim_presenter.last_tick_frame == Engine.get_process_frames()]))
	unit.tactical_state.establish_aim()
	await _frames(3)
	check(p.aim_committed and p.aim.held and events.size() == 1 and events[0][0] == AimHold.Transition.ENGAGED and events[0][1], "A committed Aim engages the hold, inside the presenter's tick of that frame, once: %s" % [events])
	check(unit.visual_adapter.get_presentation_state() == &"aim", "...and the quiet pose settles to the aimed stance (%s)" % unit.visual_adapter.get_presentation_state())
	await _frames(60)
	check(p.aim.held and events.size() == 1, "While the Aim stays committed the hold stays and nothing re-fires")
	unit.tactical_state.clear_aim()
	var frames := 0
	while p.aim.held and frames < 150:
		await process_frame
		frames += 1
	var seconds := frames / 60.0
	check(not p.aim_committed and not p.aim.held and seconds > 0.9 and seconds < 1.25 and events.size() == 2 and events[1][0] == AimHold.Transition.RELEASED,
		"After the Aim is cleared the sights stay up for the grace period and then release once (%.2f s)" % seconds)
	await _frames(70)
	check(unit.visual_adapter.aim_blend < 0.05 and not unit.visual_adapter.readiness.has_request(AttackSequence.SOURCE), "...the weapon is relaxed again and no attack request is left (blend %.2f)" % unit.visual_adapter.aim_blend)
	# The committed Aim persists through a hit (the hit plays uninterrupted, then the aimed stance returns); a hold in its grace period is ended by the hit.
	unit.tactical_state.establish_aim()
	await _frames(3)
	var committed_hit := unit.visual_adapter.present_hit()
	var committed_hit_seen := _watch(committed_hit)
	await _frames(2)
	check(p.aim.held and unit.visual_adapter.get_presentation_state() == &"hit", "A hit during a committed Aim does not drop the hold and plays uninterrupted")
	var wait_frames := 0
	while not committed_hit.is_done() and wait_frames < 120:
		await process_frame
		wait_frames += 1
	await _frames(2)
	check(committed_hit_seen == [COMPLETED] and p.aim.held and unit.visual_adapter.get_presentation_state() == &"aim", "...and after the reaction the aimed stance returns (%s)" % unit.visual_adapter.get_presentation_state())
	unit.tactical_state.clear_aim()
	unit.visual_adapter.present_hit()
	await _frames(2)
	check(not p.aim.held, "With the Aim no longer committed, a hit ends the grace-period hold at once")
	unit.queue_free()
	await _frames(2)

func _defeat_removal() -> void:
	# Defeat: the defeat settles after its clip, the body stays at least the tactical floor, a repeat never restarts it.
	var unit := await _unit()
	var adapter := unit.visual_adapter
	var p := adapter.presenter
	var defeats := [0]
	adapter.presentation_state_changed.connect(func(state: StringName) -> void: defeats[0] += int(state == &"defeat"))
	var defeat := adapter.present_defeat()
	var defeat_seen := _watch(defeat)
	var removal := p.removal_handle(TacticalUnit.DEFEAT_REMOVAL_SECONDS)
	var removal_seen := _watch(removal)
	var again := adapter.present_defeat()
	unit.finish_defeat_presentation()   # not awaited: polled below
	var last_time := 0.0
	var started := Time.get_ticks_msec()
	var defeat_done_at := -1.0
	while is_instance_valid(unit) and Time.get_ticks_msec() - started < 5000:
		last_time = p.time
		if defeat_done_at < 0.0 and defeat.is_done():
			defeat_done_at = p.time
		await process_frame
	check(again == defeat and defeats[0] == 1, "A repeated defeat is the same defeat and does not restart the clip")
	check(defeat_seen == [COMPLETED] and defeat_done_at > 1.1 and defeat_done_at < 1.3, "The defeat settles COMPLETED once after its clip (%.2f s of presentation time)" % defeat_done_at)
	check(removal_seen == [COMPLETED] and last_time >= TacticalUnit.DEFEAT_REMOVAL_SECONDS - 0.03 and last_time < TacticalUnit.DEFEAT_REMOVAL_SECONDS + 0.2 and not is_instance_valid(unit),
		"The body is removed once the defeat finished and the 1.25 s tactical floor passed (%.2f s), and the removal handle settled COMPLETED once" % last_time)

	# A defeat that finished long ago still keeps the body for the floor from the removal request.
	var late := await _unit()
	var late_adapter := late.visual_adapter
	late_adapter.present_defeat()
	await _frames(150)
	var floor_start: float = late_adapter.presenter.time
	late.finish_defeat_presentation()
	var floor_end := 0.0
	started = Time.get_ticks_msec()
	while is_instance_valid(late) and Time.get_ticks_msec() - started < 5000:
		floor_end = late_adapter.presenter.time
		await process_frame
	check(floor_end - floor_start >= TacticalUnit.DEFEAT_REMOVAL_SECONDS - 0.03 and floor_end - floor_start < TacticalUnit.DEFEAT_REMOVAL_SECONDS + 0.2, "A defeat that finished earlier still waits the floor from the removal request (%.2f s)" % (floor_end - floor_start))

	# Removal during the defeat settles every handle INTERRUPTED and does not stall.
	var gone := await _unit()
	var gone_adapter := gone.visual_adapter
	var gone_defeat := gone_adapter.present_defeat()
	var gone_removal := gone_adapter.presenter.removal_handle(TacticalUnit.DEFEAT_REMOVAL_SECONDS)
	var gone_defeat_seen := _watch(gone_defeat)
	var gone_removal_seen := _watch(gone_removal)
	gone.finish_defeat_presentation()
	await _frames(10)
	gone.queue_free()
	await _frames(3)
	check(gone_defeat_seen == [INTERRUPTED] and gone_removal_seen == [INTERRUPTED], "Freeing the unit mid-defeat interrupts both handles: %s %s" % [gone_defeat_seen, gone_removal_seen])

	# A character that no longer processes has no lifecycle to observe: the plain floor applies.
	var idle := await _unit()
	idle.visual_adapter.process_mode = Node.PROCESS_MODE_DISABLED
	var idle_started := Time.get_ticks_msec()
	idle.finish_defeat_presentation()
	while is_instance_valid(idle) and Time.get_ticks_msec() - idle_started < 5000:
		await process_frame
	var waited := (Time.get_ticks_msec() - idle_started) / 1000.0
	check(not is_instance_valid(idle) and waited > 1.1 and waited < 1.7, "A unit whose visual does not process is still removed after the floor (%.2f s)" % waited)

func _precedence() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var v: UnitVisualAdapter = VISUAL.instantiate()
	stage.add_child(v)
	await _frames(15)
	var p := v.presenter
	var target := v.global_position + v.global_basis.z * 6.0

	# Attack and hit: a hit ends an attack; a newer attack ends a running hit (the committed shot shows on time); the committed one then completes.
	var hit := v.present_hit()
	var hit_seen := _watch(hit)
	var attack := v.present_attack(target)
	var attack_seen := _watch(attack)
	check(hit_seen == [INTERRUPTED] and not attack.is_done(), "A newer attack ends a running hit reaction (INTERRUPTED once); the committed shot is not delayed")
	var guard := 0
	while not attack.is_done() and guard < 300:
		await process_frame
		guard += 1
	check(attack_seen == [COMPLETED] and attack.shot.outcome == COMPLETED, "...and the attack completes")
	var raising := v.present_attack(target)
	var raising_seen := _watch(raising)
	await _frames(3)
	v.present_hit()
	check(raising_seen == [INTERRUPTED], "A hit ends an attack in progress")

	# Persistent aim never blocks a hit or an attack (the committed Aim's persistence through a hit is checked on a production unit above).
	v.present_aim()
	await _frames(40)
	var aimed_hit := v.present_hit()
	var aimed_hit_seen := _watch(aimed_hit)
	await _frames(2)
	check(v.get_presentation_state() == &"hit" and not p.aim.held, "A hit is not blocked by an aim hold; an uncommitted hold (grace period) ends when another action takes over")
	guard = 0
	while not aimed_hit.is_done() and guard < 120:
		await process_frame
		guard += 1
	check(aimed_hit_seen == [COMPLETED], "...and the reaction completes")

	# A rescue lift already committed is not cut short by a cosmetic hit.
	v.preview_carrying = true
	var lift := v.begin_pickup(v.character_root.global_position + v.character_root.global_basis.orthonormalized().z)
	var lift_seen := _watch(lift)
	await _frames(20)
	var during_lift := v.present_hit()
	check(during_lift.outcome == SKIPPED and during_lift.is_done() and v.interaction_active() and not p.is_holding() and lift_seen.is_empty() and v.get_presentation_state() != &"hit",
		"A hit during a rescue lift is SKIPPED: no clip, no hold, the lift carries on")
	v.end_carry()
	v.preview_carrying = false
	await _frames(3)

	# Defeat is terminal: it ends everything and every later request is refused without a presentation.
	var doomed := v.present_attack(target)
	var doomed_seen := _watch(doomed)
	await _frames(3)
	var defeat := v.present_defeat()
	check(doomed_seen == [INTERRUPTED] and p.is_defeated() and v.get_presentation_state() == &"defeat", "Defeat ends the running attack and is terminal")
	var states: Array = []
	v.presentation_state_changed.connect(func(state: StringName) -> void: states.append(state))
	var late_hit := v.present_hit()
	var late_attack := v.present_attack(target)
	var late_pickup := v.present_pickup(v.global_position + Vector3(1, 0, 0))
	check(late_hit.outcome == CANCELLED and late_attack.outcome == CANCELLED and late_attack.shot.outcome == CANCELLED and late_pickup.outcome == CANCELLED and states.is_empty() and v.get_presentation_state() == &"defeat" and not p.is_holding(),
		"After a defeat a hit, an attack and a pickup are refused (CANCELLED) and change nothing")
	check(v.present_defeat() == defeat and not p.attack.is_active() and not defeat.is_done() or defeat.is_done(), "A repeated defeat is the same handle")
	stage.queue_free()
	await _frames(2)

func _level() -> BattleLevel:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(3, 2, false, 1, 0, Vector2i(32, 24), false, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 2, false))
	root.add_child(level)
	return level

func _begin_level() -> BattleLevel:
	var level := _level()
	await create_timer(0.3).timeout
	level.action_camera_director.frequency = level.action_camera_director.Frequency.OFF
	return level

func _start_rescue(level: BattleLevel, carrier: TacticalUnit, target: TacticalUnit) -> void:
	var run := func() -> void:
		await level.objective_manager.try_rescue(carrier, target)
	run.call()

## A rescue decided while the carrier's body is still far away: the presenter holds the request and its handle.
func _far_carrier(level: BattleLevel) -> Array:
	var target := level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var carrier: TacticalUnit = level.turn_manager.player_units[0]
	var grid := level.battle_controller.grid_manager
	grid.update_unit_position(carrier, carrier.grid_position, grid.get_unit_grid(target) + Vector3i.LEFT)   # decided "there", the body still far away
	_start_rescue(level, carrier, target)
	await create_timer(0.3).timeout
	return [carrier, target]

func _pending_pickup() -> void:
	# Arrival: the held request starts the lift and its reserved handle runs and completes.
	var level := await _begin_level()
	var pair := await _far_carrier(level)
	var carrier: TacticalUnit = pair[0]
	var target: TacticalUnit = pair[1]
	var adapter := carrier.visual_adapter
	var p := adapter.presenter
	check(p.has_pending_pickup() and adapter.pickup_pending() and not adapter.interaction_active(), "A rescue decided far away is held by the presenter, nothing is lifted yet")
	var reserved := adapter.reserve_rescue_handle()
	var reserved_seen := _watch(reserved)
	check(adapter.rescue_presentation() == null and not reserved.is_done(), "...with a reserved handle that is not running")
	var grid := level.battle_controller.grid_manager
	var cell := grid.get_unit_grid(target) + Vector3i.LEFT
	carrier.global_position = grid.grid_to_world(cell) + Vector3.UP * carrier.standing_height
	adapter.present_movement_end()
	check(not p.has_pending_pickup() and adapter.interaction_active() and adapter.rescue_presentation() == reserved, "The carrier arrives: the held request starts the lift, and the same reserved handle is the one running")
	adapter.rescue_interaction.scrub(adapter.rescue_interaction.duration() - 0.05)
	await _frames(8)
	check(reserved_seen == [COMPLETED] and not p.has_pending_pickup(), "...and it settles COMPLETED once")
	level.queue_free()
	await _frames(2)

	# Cancellation by the requester: nothing is started on arrival.
	level = await _begin_level()
	pair = await _far_carrier(level)
	carrier = pair[0]
	adapter = carrier.visual_adapter
	p = adapter.presenter
	var held := adapter.reserve_rescue_handle()
	var held_seen := _watch(held)
	held.cancel()
	check(held_seen == [CANCELLED] and not p.has_pending_pickup(), "Cancelling the held pickup forgets it: CANCELLED once, nothing pending")
	adapter.present_movement_end()
	check(not adapter.interaction_active() and not is_instance_valid(adapter.carry_passenger), "...and the carrier's arrival starts no lift")
	level.queue_free()
	await _frames(2)

	# A defeat while it waits interrupts it.
	level = await _begin_level()
	pair = await _far_carrier(level)
	carrier = pair[0]
	adapter = carrier.visual_adapter
	var defeat_held := adapter.reserve_rescue_handle()
	var defeat_held_seen := _watch(defeat_held)
	adapter.present_defeat()
	check(defeat_held_seen == [INTERRUPTED] and not adapter.presenter.has_pending_pickup(), "A defeat while the pickup waits settles its handle INTERRUPTED and forgets it")
	level.queue_free()
	await _frames(2)

	# Teardown while it waits: no handle is left unresolved.
	level = await _begin_level()
	pair = await _far_carrier(level)
	carrier = pair[0]
	adapter = carrier.visual_adapter
	var torn := adapter.reserve_rescue_handle()
	var torn_seen := _watch(torn)
	var presenter_ref := adapter.presenter
	carrier.queue_free()
	await _frames(3)
	check(torn_seen == [INTERRUPTED] and not presenter_ref.has_pending_pickup(), "Freeing the carrier while its pickup waits interrupts the handle: %s" % [torn_seen])
	level.queue_free()
	await _frames(2)

func _facing_hint() -> void:
	# The replay camera's focus uses a read-only facing hint, never the adapter's transform.
	var unit := await _unit()
	unit.visual_adapter.rotation.y = deg_to_rad(90.0)
	check(unit.get_presentation_facing().is_equal_approx(Vector3(1, 0, 0)) and unit.get_presentation_facing().is_equal_approx(unit.visual_adapter.presenter.facing_direction()), "The presentation facing hint is the presenter's read-only horizontal facing")
	var replay_text := FileAccess.get_file_as_string("res://systems/replay/battle_replay_player.gd")
	check(not replay_text.contains("visual_adapter.global_basis") and replay_text.contains("get_presentation_facing()"), "The replay player no longer reads the adapter's transform")
	unit.queue_free()
	await _frames(2)
