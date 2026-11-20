extends SceneTree
## Clearance-aware path presentation on the real Tactical Test Range: the opt-in refinement smooths a legal route's corners within the body clearance of the real physical parts,
## reports (and leaves alone) a route the geometry does not support, and a real Move with it on ends on the same cell for the same AP as with it off.
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

func _floor_path(f, actor: TacticalUnit, cells: Array) -> PackedVector3Array:
	var path := PackedVector3Array()
	for cell: Vector3i in cells:
		path.append(f.grid.grid_to_world(cell) + Vector3.UP * actor.standing_height)
	return path

func _clearance(f, actor: TacticalUnit, path: PackedVector3Array) -> float:
	var data: MapData = f.grid.map_data
	var best := INF
	for i in range(1, path.size()):
		var a := path[i - 1] - Vector3.UP * actor.standing_height
		var b := path[i] - Vector3.UP * actor.standing_height
		if absf(a.y - b.y) <= 0.01:
			best = minf(best, PathRefiner.segment_clearance(a, b, data.movement_parts, data.body_height))
	return best

func _walk(f, actor: TacticalUnit, destination: Vector3i) -> int:
	var before := actor.stats.current_ap
	var result: bool = await f.battle.try_move(actor, destination)
	return (before - actor.stats.current_ap) if result else -1

func _run() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(2, 0, 4))
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	for i in 20: await process_frame
	var data: MapData = f.grid.map_data
	var radius := data.body_radius + data.body_clearance - data.surface_unit / 10000.0
	check(not actor.path_presentation.enabled, "The refinement is off by default")

	# ---- A legal L-shaped route beside a support column (clearance 0.76 m): smoothed, same endpoints, clearance kept.
	var cells := [Vector3i(2, 0, 4), Vector3i(3, 0, 4), Vector3i(3, 0, 5), Vector3i(3, 0, 6)]
	var tactical := _floor_path(f, actor, cells)
	actor.path_presentation.enabled = false
	actor.move_along_path(tactical, [&"move", &"move", &"move", &"move"])
	var plain := actor.current_path.duplicate()
	actor.is_moving = false
	actor.path_presentation.enabled = true
	actor.move_along_path(tactical, [&"move", &"move", &"move", &"move"])
	var smooth := actor.current_path.duplicate()
	var report: Dictionary = actor.last_path_report.duplicate()
	actor.is_moving = false
	check(plain.size() == 4 and smooth.size() > plain.size(), "With it on the corner gains curve points (%d -> %d waypoints)" % [plain.size(), smooth.size()])
	check(smooth[0].is_equal_approx(plain[0]) and smooth[smooth.size() - 1].is_equal_approx(plain[plain.size() - 1]), "The start and the end are exactly the tactical ones")
	check(report.mismatches.is_empty() and int(report.rounded) >= 1, "No mismatch was reported and a corner was rounded (%d)" % int(report.rounded))
	var clear_smooth := _clearance(f, actor, smooth)
	check(clear_smooth >= radius - 0.0001, "The smoothed walk keeps the body's clearance from every physical part (%.3f m of %.3f)" % [clear_smooth, radius])
	var cut_most := 0.0
	for p in smooth:
		var near := INF
		for i in range(1, plain.size()):
			near = minf(near, p.distance_to(Geometry3D.get_closest_point_to_segment(p, plain[i - 1], plain[i])))
		cut_most = maxf(cut_most, near)
	check(cut_most < 0.25, "The curve never strays more than %.2f m from the authorized route" % cut_most)
	var length_plain := 0.0
	var length_smooth := 0.0
	for i in range(1, plain.size()):
		length_plain += plain[i].distance_to(plain[i - 1])
	for i in range(1, smooth.size()):
		length_smooth += smooth[i].distance_to(smooth[i - 1])
	print("  refined route: %.3f m (tactical polyline %.3f m), clearance %.3f m" % [length_smooth, length_plain, clear_smooth])

	# ---- A route the physical geometry does not support (straight through the column cell): reported, left exactly as it was, never rerouted.
	var through := _floor_path(f, actor, [Vector3i(2, 0, 5), Vector3i(3, 0, 5), Vector3i(4, 0, 5), Vector3i(5, 0, 5)])
	actor.move_along_path(through, [&"move", &"move", &"move", &"move"])
	var kept := actor.current_path.duplicate()
	var bad_report: Dictionary = actor.last_path_report.duplicate()
	actor.is_moving = false
	check(not bad_report.mismatches.is_empty(), "A route through the column is reported as a geometry/tactical mismatch (%d)" % bad_report.mismatches.size())
	check(kept.size() == 4 and kept[0].is_equal_approx(through[0]) and kept[3].is_equal_approx(through[3]), "...and the walk is exactly the tactical route (no reroute, no teleport)")

	# ---- A real Move: the same destination, with and without the refinement, ends on the same cell for the same AP; occupancy and the replay request are the same.
	actor.path_presentation.enabled = false
	f.ready_actor(actor, 6, 4)
	var cost_off := await _walk(f, actor, Vector3i(3, 0, 6))
	var cell_off := actor.grid_position
	f.place(actor, Vector3i(2, 0, 4))
	actor.path_presentation.enabled = true
	f.ready_actor(actor, 6, 4)
	var cost_on := await _walk(f, actor, Vector3i(3, 0, 6))
	check(cost_off > 0 and cost_on == cost_off, "The move costs the same with the refinement on (%d and %d AP)" % [cost_off, cost_on])
	check(actor.grid_position == cell_off and actor.grid_position == Vector3i(3, 0, 6), "...and ends on the same committed cell")
	check(f.grid.get_unit_at(Vector3i(3, 0, 6)) == actor and f.grid.get_unit_at(Vector3i(2, 0, 4)) == null, "Occupancy is exactly the tactical one")
	check(is_equal_approx(actor.global_position.y - actor.standing_height, f.grid.grid_to_world(Vector3i(3, 0, 6)).y), "The unit stands on the floor of its cell")

	# ---- Every legal route from three starting places (beside the support columns, open ground, the stair foot), refined and measured densely along the WHOLE smoothed path:
	# endpoints exact, no mismatch between the tactical sweep and the refiner, the body clearance kept at every 2 cm, no unauthorized point further than the corner cut from the route.
	var routes := 0
	var rounded_routes := 0
	var mismatching := 0
	var worst_dense := INF
	var worst_stray := 0.0
	var endpoints_ok := true
	for start in [Vector3i(3, 0, 5), Vector3i(8, 0, 9), Vector3i(6, 0, 15)]:
		if actor.grid_position != start:
			f.place(actor, start)
		f.ready_actor(actor, 6, 4)
		var query: Dictionary = f.battle._query_move_data(actor, Vector3i(-1, -1, -1))
		var destinations: Array = query.get("legal_destinations", [])
		var tested := 0
		for destination: Vector3i in destinations:
			if tested >= 40:
				break
			var detail: Dictionary = f.battle._query_move_data(actor, destination)
			if not detail.get("accepted", false) or not detail.has("presentation_path"):
				continue
			tested += 1
			routes += 1
			var presentation: PackedVector3Array = detail.presentation_path
			var segments: Array[StringName] = []
			segments.assign(detail.visual_segments)
			actor.path_presentation.enabled = false
			actor.move_along_path(presentation, segments)
			var tactical_walk := actor.current_path.duplicate()
			actor.is_moving = false
			actor.path_presentation.enabled = true
			actor.move_along_path(presentation, segments)
			var walk := actor.current_path.duplicate()
			var walk_kinds := actor._leg_kinds.duplicate()
			var walk_report: Dictionary = actor.last_path_report.duplicate()
			actor.is_moving = false
			if not walk_report.get("mismatches", []).is_empty():
				mismatching += 1
				continue
			if int(walk_report.get("rounded", 0)) > 0:
				rounded_routes += 1
			if not walk[0].is_equal_approx(tactical_walk[0]) or not walk[walk.size() - 1].is_equal_approx(tactical_walk[tactical_walk.size() - 1]):
				endpoints_ok = false
			for i in range(1, walk.size()):
				var a: Vector3 = walk[i - 1] - Vector3.UP * actor.standing_height
				var b: Vector3 = walk[i] - Vector3.UP * actor.standing_height
				if absf(a.y - b.y) > 0.01 or (i < walk_kinds.size() and int(walk_kinds[i]) != 0):
					continue   # a stair, ramp, ladder or vault leg legitimately touches its own blocks; ordinary walking must keep clear
				var length := a.distance_to(b)
				var steps := maxi(1, int(ceil(length / 0.02)))
				for k in range(steps + 1):
					var p := a.lerp(b, float(k) / float(steps))
					var dense := PathRefiner.segment_clearance(p, p, data.movement_parts, data.body_height)
					if dense < radius - 0.0005 and worst_dense > radius - 0.0005:
						print("  first violation: start %s -> %s at %s (segment %d of %d), tactical clearance of the same segment %.3f, smoothed %.3f, floor y %.2f" % [start, destination, p, i, walk.size(), PathRefiner.segment_clearance(a, b, data.movement_parts, data.body_height), dense, a.y])
					worst_dense = minf(worst_dense, dense)
			for p in walk:
				var near := INF
				for i in range(1, tactical_walk.size()):
					near = minf(near, p.distance_to(Geometry3D.get_closest_point_to_segment(p, tactical_walk[i - 1], tactical_walk[i])))
				worst_stray = maxf(worst_stray, near)
	print("  scanned %d legal routes: %d smoothed, %d mismatches, densest clearance %.3f m (body %.3f), strays at most %.3f m from the route" % [routes, rounded_routes, mismatching, worst_dense, radius, worst_stray])
	check(routes >= 40, "A real scan: %d legal routes refined" % routes)
	check(mismatching == 0, "No legal tactical route is reported as unsupported by the physical parts (%d mismatches): the refiner and the tactical sweep agree" % mismatching)
	check(endpoints_ok and rounded_routes > 0, "Every refined walk starts and ends exactly where the tactical one does, and some were actually smoothed (%d)" % rounded_routes)
	check(worst_dense >= radius - 0.0005, "Sampled every 2 cm along every smoothed path, the body clearance holds (%.3f m of %.3f)" % [worst_dense, radius])
	check(worst_stray < 0.5, "No smoothed point strays more than the corner cut from the authorized route (%.3f m)" % worst_stray)

	await f.dispose(self)
	print("Traversal path gameplay: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
