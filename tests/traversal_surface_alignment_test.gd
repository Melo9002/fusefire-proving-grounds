extends SceneTree
## Presentation against the REAL physical geometry of the Tactical Test Range (physics rays against the authored CSG stairs and ramp, not the tactical block stand-ins):
## the stair model's treads and risers lie where the physical treads are, the planted feet stand on them, a declared ramp is walked along its real slope, and the ramp's lip below its
## exit deck is stepped, not walked through. A walk is judged by the surface under the unit, never by the model it was generated from.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
var failures := 0
var checks := 0
var space: PhysicsDirectSpaceState3D
var snap := {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## The height of the physical surface (the authored CSG, collision layer 2) under world x/z, or NAN.
func _surface(x: float, z: float) -> float:
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 8.0, z), Vector3(x, -2.0, z), 2))
	return hit.position.y if not hit.is_empty() else NAN

func _grab(adapter) -> void:
	var sk: Skeleton3D = adapter.rig.skeleton
	for n in ["LeftFoot", "RightFoot"]:
		snap[n] = sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_" + n)).origin

func _run() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	for i in 10: await process_frame
	space = f.level.get_world_3d().direct_space_state
	var data: MapData = f.grid.map_data

	# ---- The stair model against the physical treads (column x of the stairs).
	var stair_x: float = f.grid.grid_to_world(Vector3i(6, 0, 15)).x
	var low := data.get_cell(Vector3i(6, 0, 15)).world_position
	var model := StairModel.from_links(low, data.get_cell(Vector3i(6, 3, 12)).world_position, 1.0, 1.0, 2, 3)
	var worst_tread := 0.0
	for k in range(1, 7):
		var s := (float(k) - 0.5) * 0.5   # the middle of tread k
		var physical := _surface(stair_x, low.z - s)
		worst_tread = maxf(worst_tread, absf(physical - model.height_at(s)))
	print("  stairs: model vs physical tread top at mid-tread, worst difference %.4f m" % worst_tread)
	check(worst_tread < 0.015, "The stair model's tread tops equal the physical treads' (worst difference %.4f m)" % worst_tread)
	var riser_ok := true
	for k in range(1, 7):
		var edge := model.riser_s(k)
		var before := _surface(stair_x, low.z - (edge - 0.1)) if k > 1 else 0.0
		var after := _surface(stair_x, low.z - (edge + 0.1))
		if absf(after - before - 0.5) > 0.015 or absf(after - model.height_at(edge + 0.1)) > 0.015:
			riser_ok = false
	check(riser_ok, "Every riser (at s = 0, 0.5 ... 2.5 from the foot cell centre) is a 0.5 m step exactly where the model says")
	check(absf(_surface(stair_x, low.z - 1.0) - model.height_at(1.0) - 0.5) < 0.015 and is_equal_approx(model.height_at(1.0), data.get_cell(Vector3i(6, 1, 14)).world_position.y), "A cell centre is the foot of a riser: the model's floor there is the cell's floor (1.0 m), one tread below the surface at the riser line")

	# ---- The ramp: its real slope, and the lip below the exit deck.
	var ramp_x: float = f.grid.grid_to_world(Vector3i(11, 0, 15)).x
	var worst_slope := 0.0
	for z in [-0.6, -1.0, -1.4, -1.9, -2.3, -2.9]:
		worst_slope = maxf(worst_slope, absf(_surface(ramp_x, z) - (-0.5 - z)))
	print("  ramp: physical surface vs the 1:1 slope through the cell centres, worst difference %.4f m" % worst_slope)
	check(worst_slope < 0.015, "The ramp body is the straight 45 degree slope through the cell centres (worst %.4f m)" % worst_slope)
	var lip_before := _surface(ramp_x, -2.95)
	var lip_after := _surface(ramp_x, -3.05)
	check(absf(lip_before - 2.45) < 0.02 and absf(lip_after - 3.0) < 0.01, "The physical ramp ends at the cell boundary and the exit deck is %.2f m higher (%.3f below, %.3f above): a step, not a slope" % [lip_after - lip_before, lip_before, lip_after])
	var ramp_links := []
	for link in data.traversal_links:
		if link.surface_kind == TraversalLinkData.RAMP:
			ramp_links.append(link)
	var lipped := 0
	for link in ramp_links:
		lipped += 1 if link.step_at_to else 0
	check(ramp_links.size() == 3 and lipped == 1, "Exactly the last ramp link (into the deck) is marked as stepping at its end (%d of %d)" % [lipped, ramp_links.size()])

	# ---- Walk the ramp up and down: the unit stays on the real surface and steps up at the lip.
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(11, 0, 15))
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	var adapter: TacticalCharacterAdapter = actor.visual_adapter
	adapter.rig.skeleton.skeleton_updated.connect(func() -> void: _grab(adapter))
	for i in 20: await process_frame
	for leg in [[Vector3i(11, 3, 12), "up"], [Vector3i(11, 0, 15), "down"]]:
		f.ready_actor(actor, 6, 4)
		var done := []
		var go := func() -> void:
			done.append(await f.battle.try_move(actor, leg[0]))
		go.call()
		var worst_float := 0.0
		var worst_sink := 0.0
		var lip_frames := 0
		var path_vertical_segments := 0
		var guard := 0
		var previous_path: PackedVector3Array = actor.current_path
		while done.is_empty() and guard < 3000:
			guard += 1
			await process_frame
			var floor_position := actor.global_position - Vector3.UP * actor.standing_height
			if absf(floor_position.z - (-3.0)) < 0.07:
				lip_frames += 1   # at the lip plane the unit is stepping between the two surfaces
				continue
			var surface := _surface(floor_position.x, floor_position.z)
			worst_float = maxf(worst_float, floor_position.y - surface)
			worst_sink = minf(worst_sink, floor_position.y - surface)
		var walked: PackedVector3Array = actor.current_path
		for i in range(1, walked.size()):
			if absf(walked[i].y - walked[i - 1].y) > 0.05 and Vector2(walked[i].x - walked[i - 1].x, walked[i].z - walked[i - 1].z).length() < 0.01:
				path_vertical_segments += 1
		print("  ramp %s: float %.3f m, sink %.3f m above/below the physical surface, %d waypoints, %d vertical step(s)" % [leg[1], worst_float, worst_sink, walked.size(), path_vertical_segments])
		check(bool(done[0]) and actor.grid_position == leg[0], "Ramp %s: the move completes on its committed cell" % leg[1])
		check(worst_float < 0.02 and worst_sink > -0.02, "Ramp %s: the unit stays on the physical surface (float %.3f, sink %.3f) except at the lip plane" % [leg[1], worst_float, worst_sink])
		check(path_vertical_segments == 1, "Ramp %s: the only vertical step in the walk is the one at the lip (%d)" % [leg[1], path_vertical_segments])

	# ---- Walk the stairs up and down: the planted foot soles are on the physical treads.
	f.place(actor, Vector3i(6, 0, 15))
	for leg in [[Vector3i(6, 3, 12), "up"], [Vector3i(6, 0, 15), "down"]]:
		f.ready_actor(actor, 6, 4)
		var done := []
		var go := func() -> void:
			done.append(await f.battle.try_move(actor, leg[0]))
		go.call()
		var worst_sole := 0.0
		var samples := 0
		var worst_ankle := 0.0
		var worst_lift := 0.0
		var guard := 0
		while done.is_empty() and guard < 3500:
			guard += 1
			await process_frame
			if adapter.rig.stairs == null or adapter.rig.stairs.pose == null or adapter.rig.stairs.pose.weight < 0.99:
				continue
			for foot in 2:
				var info: StairPose.Foot = adapter.rig.stairs.pose.feet[foot]
				if not info.planted:
					continue
				var target: Vector3 = info.position
				var surface := _surface(target.x, target.z)
				# A planted foot's heel comes up toward toe-off by the planner's own lift (StairProfile.heel_lift, on purpose since the toes stopped sinking into the treads): the sole is on the tread EXCEPT
				# for that lift, which is measured and bounded separately below.
				var lift := maxf(target.y - info.tread_top - adapter.rig.stair_profile.ankle_height, 0.0)
				worst_lift = maxf(worst_lift, lift)
				worst_sole = maxf(worst_sole, absf((target.y - adapter.rig.stair_profile.ankle_height - lift) - surface))
				worst_ankle = maxf(worst_ankle, (snap.LeftFoot if foot == 0 else snap.RightFoot).distance_to(target))
				samples += 1
		print("  stairs %s: %d planted samples, sole-to-physical-tread difference %.4f m, ankle error %.4f m" % [leg[1], samples, worst_sole, worst_ankle])
		check(bool(done[0]) and actor.grid_position == leg[0], "Stairs %s: the move completes on its committed cell" % leg[1])
		check(samples > 100 and worst_sole < 0.02, "Stairs %s: every planted sole is on the physical tread beneath it, apart from the planned heel lift (%d samples, worst %.4f m)" % [leg[1], samples, worst_sole])
		check(worst_lift <= adapter.rig.stair_profile.heel_lift + 0.002, "Stairs %s: the planted heel lift stays within the profile's limit (%.4f m of %.4f m)" % [leg[1], worst_lift, adapter.rig.stair_profile.heel_lift])
		check(worst_ankle < 0.05, "Stairs %s: the ankle bones reach those footholds (worst %.4f m)" % [leg[1], worst_ankle])

	await f.dispose(self)
	print("Traversal surface alignment: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
