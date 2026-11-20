extends SceneTree
## A loaded rescue carrier on the Tactical Test Range's stairs, ramp and ladder. The tactical rules allow all of them (carrying only lowers the movement budget); the presentation
## supports stairs and ramps as a path (the carrier rides the surface in the carry gait) but NOT the stair feet or the ladder contacts, which would compete with the passenger for
## the legs and hands. This pins the documented fallback: the passenger stays on the carrier, nothing of the unsupported presentation is applied, and the move completes.
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

func _carry_walk(f, actor: TacticalUnit, adapter: UnitVisualAdapter, destination: Vector3i, surface: Callable) -> Dictionary:
	var done := []
	var go := func() -> void:
		done.append(await f.battle.try_move(actor, destination))
	var started := Time.get_ticks_msec()
	go.call()
	var log := {"seconds": 0.0, "stairs": false, "ladder": false, "leg_ik": false, "stowed_always": true, "drift_min": INF, "drift_max": 0.0, "float": 0.0, "sink": 0.0, "contacts_on": true, "frames": 0}
	var guard := 0
	while done.is_empty() and guard < 4000:
		guard += 1
		await process_frame
		log.frames += 1
		log.stairs = bool(log.stairs) or not adapter.stair_state.is_empty()
		log.ladder = bool(log.ladder) or adapter.is_ladder_active() or not adapter.traversal.is_empty()
		log.leg_ik = bool(log.leg_ik) or adapter.leg_ik.active
		log.stowed_always = bool(log.stowed_always) and adapter.is_weapon_stowed()
		if is_instance_valid(adapter.carry_passenger):
			var chest: Vector3 = adapter.skeleton.global_transform * adapter.skeleton.get_bone_global_pose(adapter.skeleton.find_bone("mixamorig_Spine2")).origin
			var drift: float = (adapter.carry_passenger as Node3D).global_position.distance_to(chest)
			log.drift_min = minf(float(log.drift_min), drift)
			log.drift_max = maxf(float(log.drift_max), drift)
		var floor_position := actor.global_position - Vector3.UP * actor.standing_height
		var delta: float = surface.call(floor_position)
		log.float = maxf(float(log.float), delta)
		log.sink = minf(float(log.sink), delta)
	log.seconds = (Time.get_ticks_msec() - started) / 1000.0
	log.ok = bool(done[0]) if not done.is_empty() else false
	return log

func _run() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var data: MapData = f.grid.map_data
	f.place(actor, Vector3i(6, 0, 15))
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	var adapter: UnitVisualAdapter = actor.visual_adapter
	for i in 20: await process_frame
	adapter.preview_carrying = true
	adapter.begin_carry()
	for i in 20: await process_frame
	check(is_instance_valid(adapter.carry_passenger) and adapter.is_weapon_stowed(), "Setup: the carrier holds a passenger with the rifle slung")

	# ---- Stairs: the carrier rides the treads (no vertical pop) in the carry gait; the stair feet are NOT applied.
	var stair_model := StairModel.from_links(data.get_cell(Vector3i(6, 0, 15)).world_position, data.get_cell(Vector3i(6, 3, 12)).world_position, 1.0, 1.0, 2, 3)
	var stair_surface := func(floor_position: Vector3) -> float:
		return floor_position.y - stair_model.height_at(stair_model.progress_of(floor_position))
	var stairs := await _carry_walk(f, actor, adapter, Vector3i(6, 3, 12), stair_surface)
	print("  loaded on stairs: %.1f s, float %.2f m, sink %.3f m, passenger drift %.3f..%.3f m, stair feet %s, leg IK %s" % [stairs.seconds, stairs.float, stairs.sink, stairs.drift_min, stairs.drift_max, stairs.stairs, stairs.leg_ik])
	check(stairs.ok and actor.grid_position == Vector3i(6, 3, 12), "A loaded carrier can walk the stairs (the tactical move completes on its cell)")
	check(not stairs.stairs and not stairs.leg_ik, "The stair feet are not applied while carrying (unsupported combination, the carry gait is kept)")
	check(float(stairs.float) <= 0.001 and float(stairs.sink) >= -0.5 - 0.001, "...but the carrier still rides the stair surface rather than popping up in the air (float %.3f m, deepest %.3f m below the tread)" % [stairs.float, stairs.sink])
	check(float(stairs.drift_max) - float(stairs.drift_min) < 0.05 and bool(stairs.stowed_always), "The passenger stays on the carrier's chest (drift %.3f m) and the rifle stays slung" % (float(stairs.drift_max) - float(stairs.drift_min)))
	await create_timer(0.4).timeout

	# ---- Ramp: the carrier follows the slope.
	f.place(actor, Vector3i(11, 0, 15))
	f.ready_actor(actor, 6, 4)
	var ramp_surface := func(floor_position: Vector3) -> float:
		if absf(floor_position.z - (-3.0)) < 0.07:
			return 0.0   # the lip plane: stepping between the ramp and the exit deck
		return floor_position.y - (-0.5 - floor_position.z if floor_position.z > -3.0 else 3.0)
	var ramp := await _carry_walk(f, actor, adapter, Vector3i(11, 3, 12), ramp_surface)
	print("  loaded on ramp: %.1f s, float %.3f m, sink %.3f m, passenger drift %.3f..%.3f m" % [ramp.seconds, ramp.float, ramp.sink, ramp.drift_min, ramp.drift_max])
	check(ramp.ok and actor.grid_position == Vector3i(11, 3, 12) and absf(float(ramp.float)) < 0.02 and absf(float(ramp.sink)) < 0.02, "A loaded carrier walks the ramp along its slope (deviation %.3f m)" % maxf(absf(float(ramp.float)), absf(float(ramp.sink))))
	check(float(ramp.drift_max) - float(ramp.drift_min) < 0.05 and not ramp.stairs and not ramp.ladder, "...with the passenger attached and no stair or ladder presentation")
	await create_timer(0.4).timeout

	# ---- Ladder: legal, but with no ladder contacts (they would need both hands that carry the passenger): the placeholder, at the route speed.
	f.place(actor, Vector3i(12, 0, 4))
	f.ready_actor(actor, 6, 4)
	var no_surface := func(_floor_position: Vector3) -> float:
		return 0.0
	var ladder := await _carry_walk(f, actor, adapter, Vector3i(12, 3, 5), no_surface)
	print("  loaded on ladder: %.1f s (unloaded about 3.7 s), ladder pose %s, passenger drift %.3f..%.3f m" % [ladder.seconds, ladder.ladder, ladder.drift_min, ladder.drift_max])
	check(ladder.ok and actor.grid_position == Vector3i(12, 3, 5), "A loaded carrier can take the ladder tactically (no rule forbids it)")
	check(not ladder.ladder and not ladder.leg_ik, "No ladder pose, rung contacts or leg IK are applied while carrying (unsupported: the passenger's contacts own the hands)")
	check(float(ladder.drift_max) - float(ladder.drift_min) < 0.05 and bool(ladder.stowed_always), "The passenger does not detach or clip away from the carrier during the placeholder climb (drift %.3f m)" % (float(ladder.drift_max) - float(ladder.drift_min)))
	check(float(ladder.seconds) < 2.0, "The unsupported climb runs at the route speed (%.1f s), not the slow ladder presentation" % ladder.seconds)
	await create_timer(0.4).timeout
	check(adapter.stair_state.is_empty() and adapter.traversal.is_empty() and not adapter.leg_ik.active and is_instance_valid(adapter.carry_passenger), "Afterwards nothing of stairs or ladder is left and the carry is intact")

	await f.dispose(self)
	print("Traversal loaded carrier: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
