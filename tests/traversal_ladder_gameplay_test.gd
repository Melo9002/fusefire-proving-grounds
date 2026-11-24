extends SceneTree
## A unit climbs and descends a real authored ladder (the Tactical Test Range's 3 m ladder) through the normal Move action: the presentation follows the unit's tactical
## height (a pure function of it), the rifle is slung while the hands are on the rungs, the move costs what it always did, and nothing of the traversal is left afterwards.
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
	var adapter: TacticalCharacterAdapter = actor.visual_adapter
	for i in 20: await process_frame
	var query := f.battle.query_move(actor, top) if f.battle.has_method("query_move") else null
	var ap_before := actor.stats.current_ap

	# ---- Up.
	var log := {"frames": 0, "max_weight": 0.0, "stowed_on_ladder": true, "height_error": 0.0, "yaw_error": 0.0, "poses": [], "turn_started": false}
	var up_result := await _move_and_watch(f, actor, adapter, top, log)
	check(bool(up_result) and actor.grid_position == top, "The unit climbs the ladder through the normal Move action and arrives on the deck")
	check(log.frames > 100, "The climb is presented over time, not in a blink (%d ladder frames)" % log.frames)
	check(float(log.max_weight) > 0.99 and bool(log.stowed_on_ladder), "Fully on the ladder the pose is complete and the rifle is slung (weight %.2f)" % log.max_weight)
	check(float(log.height_error) < 0.012, "The pose follows the unit's tactical height exactly (worst difference %.4f m)" % log.height_error)
	check(float(log.yaw_error) < 1.0, "The climber faces the ladder (worst yaw error once mounted %.1f deg)" % log.yaw_error)
	check(not (&"climb" in log.poses) and not (&"land" in log.poses), "The ladder uses no placeholder climb/landing clip")
	check(actor.stats.current_ap == ap_before - (ap_before - actor.stats.current_ap) and ap_before - actor.stats.current_ap > 0, "The move was paid for (AP %d -> %d)" % [ap_before, actor.stats.current_ap])
	var ap_up := ap_before - actor.stats.current_ap
	await create_timer(0.6).timeout
	check(adapter.rig.ladder == null and not adapter.is_ladder_active() and not adapter.rig.is_weapon_stowed() and not adapter.rig.leg_ik.active, "On the deck nothing of the traversal is left: no ladder state, the rifle is in the hand, the leg IK is off")
	check(adapter.rig.crouch_modifier.aim_lean_degrees < 5.0 and adapter.rig._cover_yaw == 0.0, "...no stale trunk lean or yaw offset")

	# ---- Down. The same cost, the same height-driven pose, the unit faces the ladder going down.
	f.ready_actor(actor, 6, 4)
	var ap_mid := actor.stats.current_ap
	var down_log := {"frames": 0, "max_weight": 0.0, "stowed_on_ladder": true, "height_error": 0.0, "yaw_error": 0.0, "poses": [], "turn_started": false}
	var down_result := await _move_and_watch(f, actor, adapter, bottom, down_log)
	check(bool(down_result) and actor.grid_position == bottom, "The unit climbs back down to the floor")
	check(float(down_log.max_weight) > 0.99 and float(down_log.height_error) < 0.012 and float(down_log.yaw_error) < 1.0, "Going down: complete pose, height-driven, facing the ladder (yaw %.1f deg)" % float(down_log.yaw_error))
	check(ap_mid - actor.stats.current_ap == ap_up, "Down costs what up cost (%d and %d AP)" % [ap_up, ap_mid - actor.stats.current_ap])
	await create_timer(0.6).timeout
	check(adapter.rig.ladder == null and not adapter.rig.is_weapon_stowed(), "At the bottom the traversal is cleaned up too")

	# ---- Interruption: a unit that loses its movement mid-ladder (defeat) leaves no ladder state or slung rifle behind the visual cleanup.
	f.ready_actor(actor, 6, 4)
	var interrupted := []
	var go := func() -> void:
		interrupted.append(await f.battle.try_move(actor, top))
	go.call()
	var guard := 0
	while not adapter.is_ladder_active() or (adapter.rig.ladder.climbed if adapter.rig.ladder != null else 0.0) < 1.0:
		guard += 1
		await process_frame
		if guard > 900: break
	check(adapter.is_ladder_active() and adapter.rig.is_weapon_stowed(), "Mid-ladder: climbing with the rifle slung")
	adapter.present_defeat()
	await process_frame
	check(adapter.rig.ladder == null and not adapter.is_ladder_active(), "Defeat mid-ladder clears the ladder state")
	await create_timer(adapter.rig.traversal_release_seconds + 0.2).timeout   # the climbing pose eases out (issue 67) rather than dropping the body in one frame
	check(not adapter.rig.leg_ik.active, "...and the leg IK once the climbing pose has eased out")

	await f.dispose(self)
	print("Traversal ladder gameplay: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _move_and_watch(f, actor: TacticalUnit, adapter: TacticalCharacterAdapter, destination: Vector3i, log: Dictionary) -> bool:
	var done := []
	var go := func() -> void:
		done.append(await f.battle.try_move(actor, destination))
	go.call()
	var started := Time.get_ticks_msec()
	while done.is_empty() and Time.get_ticks_msec() - started < 40000:
		await process_frame
		var state := adapter.get_presentation_state()
		if not (state in log.poses):
			log.poses.append(state)
		if adapter.is_ladder_active() and adapter.rig.ladder != null:
			log.frames += 1
			var weight: float = (adapter.rig.ladder.pose.weight if adapter.rig.ladder != null and adapter.rig.ladder.pose != null else 0.0)
			log.max_weight = maxf(float(log.max_weight), weight)
			if weight > 0.5:
				log.stowed_on_ladder = bool(log.stowed_on_ladder) and adapter.rig.is_weapon_stowed()
				log.yaw_error = maxf(float(log.yaw_error), rad_to_deg(absf(angle_difference(adapter.rotation.y, float(adapter._ladder.yaw)))))
			# The pose height is the unit's height above the ladder's bottom, whatever the frame rate.
			var expected := clampf(actor.global_position.y - float(adapter._ladder.low_y), 0.0, float(adapter._ladder.length))
			log.height_error = maxf(float(log.height_error), absf(adapter.rig.ladder.climbed - expected))
	return bool(done[0]) if not done.is_empty() else false
