extends SceneTree
## The timing contract of a traversal, end to end, on the real Tactical Test Range: the tactical state is committed BEFORE the walk is shown; the move action does not return, and no
## later command is accepted, until the visual walk has finished and the unit stands exactly on its cell; the shown duration follows the configured presentation speeds and the
## replay playback scale; the presenter's deadline follows the walk, not a fixed 30 s.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
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
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var bottom := Vector3i(12, 0, 4)
	var top := Vector3i(12, 3, 5)
	f.place(actor, bottom)
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	for i in 20: await process_frame
	var service := f.battle.action_service

	# ---- The ladder: tactical first, visual after, the barrier holds until the unit is home.
	var done := []
	var go := func() -> void:
		done.append(await f.battle.try_move(actor, top))
	var started := Time.get_ticks_msec()
	go.call()
	var estimate := 0.0
	var mid_checked := false
	var rejected_while_walking := false
	var tactical_committed_early := false
	var far_from_target := false
	var guard := 0
	while done.is_empty() and guard < 3000:
		guard += 1
		await process_frame
		if estimate == 0.0 and actor.is_moving:
			estimate = actor.estimated_move_seconds()
		if not mid_checked and actor.is_moving and actor.global_position.y - actor.standing_height > 1.0:
			mid_checked = true
			tactical_committed_early = f.grid.get_unit_grid(actor) == top and f.grid.get_unit_at(top) == actor
			far_from_target = actor.global_position.distance_to(f.grid.grid_to_world(top) + Vector3.UP * actor.standing_height) > 0.5
			var second: bool = await f.battle.try_move(actor, bottom)
			rejected_while_walking = not second and service.last_rejection != null
	var seconds := (Time.get_ticks_msec() - started) / 1000.0
	check(bool(done[0]) and actor.grid_position == top, "The Move returns true and the unit is on its committed cell")
	check(mid_checked and tactical_committed_early and far_from_target, "Mid-climb the tactical grid already holds the destination while the body is still more than half a metre away: the walk is presentation (committed %s, far %s)" % [tactical_committed_early, far_from_target])
	check(rejected_while_walking, "A second command while the unit is still walking is rejected (the action barrier, code %s)" % [service.last_rejection.code if service.last_rejection != null else "none"])
	check(not actor.is_moving and actor.global_position.is_equal_approx(f.grid.grid_to_world(top) + Vector3.UP * actor.standing_height), "When the Move returns the unit has stopped and stands exactly on the cell")
	print("  ladder move shown in %.2f s (estimate %.2f s)" % [seconds, estimate])
	check(estimate > 2.0 and absf(seconds - estimate) / estimate < 0.25, "The shown duration matches the unit's own estimate within 25%% (%.2f s vs %.2f s)" % [seconds, estimate])
	check(maxf(30.0, 3.0 * estimate) >= 30.0 and 3.0 * estimate < 30.0, "The presenter's deadline (30 s or 3x the estimate) has room for it (%.1f s estimate)" % estimate)
	f.ready_actor(actor, 6, 4)
	check(await f.battle.try_move(actor, bottom) and actor.grid_position == bottom, "The next command is accepted at once and the unit walks back")

	# ---- Replay playback scale: the shown duration follows movement_speed (the replay player scales it by playback speed 0.5 .. 4).
	var base_speed := actor.movement_speed
	var stair_bottom := Vector3i(6, 0, 15)
	var stair_top := Vector3i(6, 3, 12)
	var durations := {}
	for playback in [0.5, 2.0]:
		f.place(actor, stair_bottom)
		f.ready_actor(actor, 6, 4)
		actor.movement_speed = base_speed * playback
		var t0 := Time.get_ticks_msec()
		var ok: bool = await f.battle.try_move(actor, stair_top)
		durations[playback] = (Time.get_ticks_msec() - t0) / 1000.0
		check(ok and actor.grid_position == stair_top, "At playback x%.1f the stair move completes on its cell" % playback)
	actor.movement_speed = base_speed
	var ratio := float(durations[0.5]) / maxf(float(durations[2.0]), 0.001)
	print("  stair move: %.2f s at 0.5x, %.2f s at 2.0x (ratio %.2f)" % [durations[0.5], durations[2.0], ratio])
	check(ratio > 3.2 and ratio < 4.8, "The shown duration scales with the playback speed (4x ratio expected, %.2f)" % ratio)

	# ---- The estimate (and so the presenter's deadline) follows the replay scale: half the speed, twice the time.
	var route := PackedVector3Array()
	for cell in [stair_bottom, Vector3i(6, 1, 14), Vector3i(6, 2, 13), stair_top]:
		route.append(f.grid.grid_to_world(cell) + Vector3.UP * actor.standing_height)
	var estimates := {}
	for scale in [1.0, 0.5]:
		if actor.grid_position != stair_bottom:
			f.place(actor, stair_bottom)
		actor.movement_speed = base_speed * scale
		actor.move_along_path(route)
		estimates[scale] = actor.estimated_move_seconds()
		actor.is_moving = false
	actor.movement_speed = base_speed
	var estimate_ratio := float(estimates[0.5]) / maxf(float(estimates[1.0]), 0.001)
	print("  stair estimate %.2f s at 1x, %.2f s at 0.5x" % [estimates[1.0], estimates[0.5]])
	check(estimate_ratio > 1.8 and estimate_ratio < 2.2, "The estimate doubles at half speed (ratio %.2f), so the presenter's deadline (30 s or 3x the estimate) scales with the replay speed" % estimate_ratio)

	await f.dispose(self)
	print("Traversal timing contract: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
