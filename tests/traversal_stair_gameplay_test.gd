extends SceneTree
## A unit walks the Tactical Test Range's real staircase (six 0.5 m treads, authored as stairs on the ElevationPath) through the normal Move action, up and down: the root
## follows the treads instead of rising 1 m in the air, the feet land on the treads and are locked in stance, the leg IK puts the ankles there, the pelvis stays inside the
## legs' reach, the move costs and ends exactly as before, and nothing of the stair is left afterwards.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
var failures := 0
var checks := 0
var snap := {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _grab(adapter) -> void:
	var sk: Skeleton3D = adapter.skeleton
	for n in ["LeftFoot", "RightFoot", "Hips", "Spine2", "Head", "LeftUpLeg", "RightUpLeg", "LeftLeg", "RightLeg"]:
		snap[n] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_" + n)).origin

func _walk(f, actor: TacticalUnit, adapter: UnitVisualAdapter, destination: Vector3i, log: Dictionary) -> bool:
	var done := []
	var go := func() -> void:
		done.append(await f.battle.try_move(actor, destination))
	go.call()
	var started := Time.get_ticks_msec()
	var last_weight := 0.0
	var last_planted := [Vector3.INF, Vector3.INF]
	var last_hold := [-1, -1]
	var last_upper := {}
	while done.is_empty() and Time.get_ticks_msec() - started < 40000:
		await process_frame
		if adapter.stair_state.is_empty() or adapter.stair_pose.is_empty():
			continue
		log.frames += 1
		var model: StairModel = adapter.stair_state.model
		var pose: Dictionary = adapter.stair_pose
		var floor_position := actor.global_position - Vector3.UP * actor.standing_height
		var s: float = model.progress_of(floor_position)
		# The root reference rides the line through the cell centres (each on the foot of a riser): never above the physical tread under it, at most one riser below it. The visible body
		# is placed by the feet and the pelvis (see traversal_surface_alignment_test, against physics rays), not by this reference.
		var above := floor_position.y - model.height_at(s)
		log.max_float = maxf(float(log.max_float), above)
		log.max_sink = minf(float(log.max_sink), above)
		# The pose is a pure function of the progress: the planner agrees with what the rig holds.
		var holds: Array = StairFootPlanner.holds(model, bool(adapter.stair_state.ascending), int(pose.step))
		for foot in 2:
			var expected := StairFootPlanner.foot_at(model, adapter.stair_profile, holds, bool(adapter.stair_state.ascending), float(pose.s), foot)
			if (expected.position as Vector3).distance_to(pose.feet[foot].position) > 0.0001:
				log.mismatch += 1
			var info: Dictionary = pose.feet[foot]
			if info.planted and last_hold[foot] == info.hold and last_planted[foot] != Vector3.INF:
				log.slide = maxf(float(log.slide), (info.position as Vector3).distance_to(last_planted[foot]))
			last_planted[foot] = info.position
			last_hold[foot] = info.hold if info.planted else -1
			# The ankle bone is on the target when the stair pose is fully on.
			if float(pose.weight) > 0.99 and info.planted:
				var bone: Vector3 = snap.LeftFoot if foot == 0 else snap.RightFoot
				log.worst_ankle = maxf(float(log.worst_ankle), bone.distance_to(info.position))
		if not bool(pose.pelvis.ok):
			log.pelvis_unreachable += 1
		# Upper-body continuity: the pelvis, chest and head move smoothly from frame to frame (a frame is about 7 ms here; a stair step is a metre long).
		for bone in ["Hips", "Spine2", "Head"]:
			var here: Vector3 = snap[bone]
			if last_upper.has(bone):
				log.worst_upper_step = maxf(float(log.worst_upper_step), here.distance_to(last_upper[bone]))
			last_upper[bone] = here
		log.max_weight = maxf(float(log.max_weight), float(pose.weight))
		log.worst_weight_step = maxf(float(log.worst_weight_step), absf(float(pose.weight) - last_weight))
		last_weight = pose.weight
	return bool(done[0]) if not done.is_empty() else false

func _log() -> Dictionary:
	return {"frames": 0, "max_float": 0.0, "max_sink": 0.0, "mismatch": 0, "slide": 0.0, "worst_ankle": 0.0, "pelvis_unreachable": 0, "max_weight": 0.0, "worst_weight_step": 0.0, "worst_upper_step": 0.0}

func _run() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var bottom := Vector3i(6, 0, 15)
	var top := Vector3i(6, 3, 12)
	var link := SurfaceNavigation.stair_link(f.grid.map_data, f.grid.map_data.get_cell(Vector3i(6, 0, 15)).world_position, f.grid.map_data.get_cell(Vector3i(6, 1, 14)).world_position)
	check(link != null and link.surface_kind == 2 and link.treads_per_step == 2, "The authored stairs are declared on the map: stairs, two treads per step")
	var ramp_link := SurfaceNavigation.stair_link(f.grid.map_data, f.grid.map_data.get_cell(Vector3i(11, 0, 15)).world_position, f.grid.map_data.get_cell(Vector3i(11, 1, 14)).world_position)
	check(ramp_link == null, "The neighbouring ramp is not a stair (it keeps the old presentation)")
	f.place(actor, bottom)
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	var adapter: UnitVisualAdapter = actor.visual_adapter
	adapter.skeleton.skeleton_updated.connect(func() -> void: _grab(adapter))
	for i in 20: await process_frame
	var ap_before := actor.stats.current_ap

	var up := _log()
	var started := Time.get_ticks_msec()
	var up_result := await _walk(f, actor, adapter, top, up)
	var up_seconds := (Time.get_ticks_msec() - started) / 1000.0
	check(up_result and actor.grid_position == top, "The unit walks up the stairs through the normal Move action and ends on the committed cell")
	var ap_up := ap_before - actor.stats.current_ap
	check(ap_up > 0, "The move was paid for as before (%d AP)" % ap_up)
	check(is_equal_approx(actor.global_position.y - actor.standing_height, 3.0), "It ends exactly on the top cell's floor height (%.3f m)" % (actor.global_position.y - actor.standing_height))
	print("  up: %d stair frames in %.1f s; root float above the tread beneath max %.2f m, sink %.3f m; stance slide %.5f m; ankle error %.3f m; pelvis unreachable %d; weight step %.2f; worst upper-body step %.3f m" % [up.frames, up_seconds, up.max_float, up.max_sink, up.slide, up.worst_ankle, up.pelvis_unreachable, up.worst_weight_step, up.worst_upper_step])
	check(up.frames > 150, "The ascent is presented over time (%d frames)" % up.frames)
	check(float(up.max_float) <= 0.001 and float(up.max_sink) >= -0.5 - 0.001, "The root reference never rises above the tread beneath it (it was up to 1.50 m above with the vertical-then-level route) and stays within one riser below it: float %.3f m, deepest %.3f m" % [up.max_float, up.max_sink])
	check(int(up.mismatch) == 0, "The feet are exactly the planner's for the unit's progress (a pure function of position): %d differences" % up.mismatch)
	check(float(up.slide) < 0.0001, "A planted foot does not slide (%.5f m)" % up.slide)
	check(float(up.worst_ankle) < 0.05, "The ankle bones reach the planted footholds (worst %.3f m)" % up.worst_ankle)
	check(float(up.worst_upper_step) < 0.04, "The pelvis, chest and head move smoothly: no frame moves any of them more than %.3f m (limit 0.04 m)" % up.worst_upper_step)
	check(int(up.pelvis_unreachable) == 0, "The pelvis stays inside the legs' reach through the whole ascent (%d unreachable frames)" % up.pelvis_unreachable)
	check(float(up.max_weight) > 0.99 and float(up.worst_weight_step) < 0.25, "The stair pose comes in and goes out smoothly (peak %.2f, worst step %.2f per frame)" % [up.max_weight, up.worst_weight_step])
	await create_timer(0.6).timeout
	check(adapter.stair_state.is_empty() and adapter.stair_pose.is_empty() and not adapter.leg_ik.active, "On the landing nothing of the stair is left: no stair state, the leg IK is off")
	check(adapter.traversal.is_empty() and adapter.get_presentation_state() != &"climb", "...and no placeholder climb clip was used")

	# ---- Down.
	f.ready_actor(actor, 6, 4)
	var ap_mid := actor.stats.current_ap
	var down := _log()
	var down_result := await _walk(f, actor, adapter, bottom, down)
	check(down_result and actor.grid_position == bottom, "The unit walks back down and ends on the bottom cell")
	check(ap_mid - actor.stats.current_ap == ap_up, "Down costs what up cost (%d AP)" % (ap_mid - actor.stats.current_ap))
	print("  down: %d stair frames; root float max %.2f m, sink %.3f m; stance slide %.5f m; ankle error %.3f m; pelvis unreachable %d" % [down.frames, down.max_float, down.max_sink, down.slide, down.worst_ankle, down.pelvis_unreachable])
	check(float(down.max_float) <= 0.001 and float(down.max_sink) >= -0.5 - 0.001 and int(down.mismatch) == 0 and float(down.slide) < 0.0001, "Down: the same guarantees (float %.2f, sink %.3f, %d differences, slide %.5f)" % [down.max_float, down.max_sink, down.mismatch, down.slide])
	check(float(down.worst_ankle) < 0.05 and int(down.pelvis_unreachable) == 0, "Down: ankles on the footholds (%.3f m), pelvis in reach (%d)" % [down.worst_ankle, down.pelvis_unreachable])
	await create_timer(0.6).timeout
	check(adapter.stair_state.is_empty() and not adapter.leg_ik.active, "At the bottom the stair state is cleaned up too")

	# ---- Interruption: defeat mid-stair leaves nothing behind.
	f.ready_actor(actor, 6, 4)
	var go := func() -> void:
		await f.battle.try_move(actor, top)
	go.call()
	var guard := 0
	while (adapter.stair_state.is_empty() or float(adapter.stair_pose.get("s", 0.0)) < 1.2) and guard < 900:
		guard += 1
		await process_frame
	check(not adapter.stair_state.is_empty(), "Mid-stair: the stair state is active")
	adapter.present_defeat()
	await process_frame
	check(adapter.stair_state.is_empty() and adapter.stair_pose.is_empty() and not adapter.leg_ik.active, "Defeat mid-stair clears the stair state and the leg IK")

	await f.dispose(self)
	print("Traversal stair gameplay: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
