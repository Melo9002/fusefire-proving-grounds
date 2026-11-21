extends SceneTree
## Presentation-route construction (Task 07 package 8). TacticalRouteBuilder turns an authorised route into the route that is shown, from explicit inputs only; TacticalUnit executes the walk and keeps no route
## algorithm. Pure checks of the speeds and the ladder-deck rule, a determinism and delegation check on real ladder and stair routes of the production Tactical Test Range, and a structural check that the
## builder reaches into no node, unit or adapter. The full before/after route equivalence is tools/quality/route_trace.gd.
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

func _same_route(a: TacticalRouteBuilder.Route, b: TacticalRouteBuilder.Route) -> bool:
	if a.points != b.points or a.poses != b.poses or a.stair_ids != b.stair_ids or a.kinds != b.kinds or a.stair_runs.size() != b.stair_runs.size():
		return false
	for i in a.stair_runs.size():
		if a.stair_runs[i].ascending != b.stair_runs[i].ascending or not is_equal_approx(a.stair_runs[i].enter, b.stair_runs[i].enter) or not is_equal_approx(a.stair_runs[i].exit, b.stair_runs[i].exit):
			return false
	return a.report.hash() == b.report.hash()

func _run() -> void:
	# ---- The builder reaches into nothing: no node, no unit, no adapter, no scene tree.
	var code_lines: Array[String] = []
	for line in FileAccess.get_file_as_string("res://presentation/tactical/tactical_route_builder.gd").split("
"):
		var cut := line.find("#")
		code_lines.append(line if cut < 0 else line.substr(0, cut))
	var text := "
".join(code_lines)   # comments describe what the builder does not touch; only code counts
	var forbidden := RegEx.create_from_string("TacticalUnit|visual_adapter|UnitVisualAdapter|get_node|get_tree|add_child|extends Node|\\.new\\(\\)\\s*#\\s*node")
	check(text.contains("extends RefCounted") and forbidden.search(text) == null, "The builder is a RefCounted of pure functions: no unit, adapter or scene-tree access")

	# ---- Presented speeds: a segment speed slows the walk only; replay playback scales it with the movement speed; no segment speed means the ordinary walk.
	check(is_equal_approx(TacticalRouteBuilder.presented_speed(0.0, 5.0, 5.0), 5.0), "No segment speed: the ordinary walking speed")
	check(is_equal_approx(TacticalRouteBuilder.presented_speed(2.5, 5.0, 5.0), 2.5), "A segment speed slows the walk")
	check(is_equal_approx(TacticalRouteBuilder.presented_speed(2.5, 10.0, 5.0), 5.0), "A faster replay scales the segment speed with it")
	check(is_equal_approx(TacticalRouteBuilder.presented_speed(9.0, 5.0, 5.0), 5.0), "A segment speed never exceeds the movement speed")
	var stairs := StairProfile.new()
	stairs.slow_stairs_enabled = true
	check(is_equal_approx(TacticalRouteBuilder.stair_segment_speed(stairs), stairs.speed), "Slow stairs: the stair profile's speed")
	stairs.slow_stairs_enabled = false
	check(TacticalRouteBuilder.stair_segment_speed(stairs) == 0.0, "Slow stairs off: no segment speed")

	# ---- The estimate follows the same speeds (a synthetic route: 5 m on the level, then a 3 m ladder climb).
	var synthetic := TacticalRouteBuilder.Route.new()
	synthetic.points = PackedVector3Array([Vector3(0, 0, 5), Vector3(0, 3, 5)])
	synthetic.kinds = [0, TraversalLinkData.LADDER]
	var ladder_profile := TraversalProfile.new()
	ladder_profile.slow_ladder_enabled = true
	stairs.slow_stairs_enabled = true
	var plain := TacticalRouteBuilder.estimated_seconds(synthetic, 0, Vector3.ZERO, 5.0, 5.0, stairs, null)
	var slowed := TacticalRouteBuilder.estimated_seconds(synthetic, 0, Vector3.ZERO, 5.0, 5.0, stairs, ladder_profile)
	check(is_equal_approx(plain, 1.0 + 3.0 / 5.0), "Without a traversal profile the ladder leg is walked at the route speed (%.2f s)" % plain)
	check(is_equal_approx(slowed, 1.0 + 3.0 / minf(5.0, ladder_profile.climb_speed)), "With one the climb leg uses the climb speed (%.2f s)" % slowed)
	check(is_equal_approx(TacticalRouteBuilder.estimated_seconds(synthetic, 1, Vector3(0, 0, 5), 5.0, 5.0, stairs, ladder_profile), 3.0 / minf(5.0, ladder_profile.climb_speed)), "The estimate counts only the rest of the route")

	# ---- The ladder's deck direction (the step onto the deck after a climb, off it before a descent).
	var climb := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 3, 0), Vector3(1, 3, 0)])
	check(TacticalRouteBuilder.ladder_toward_deck(climb, 1).is_equal_approx(Vector3(1, 0, 0)), "After a climb the deck is toward the next waypoint")
	var descent := PackedVector3Array([Vector3(-1, 3, 0), Vector3(0, 3, 0), Vector3(0, 0, 0)])
	check(TacticalRouteBuilder.ladder_toward_deck(descent, 2).is_equal_approx(Vector3(-1, 0, 0)), "Before a descent the deck is toward the waypoint before the top (the step off it)")
	var bare := PackedVector3Array([Vector3(0, 3, 0), Vector3(0, 0, 0)])
	check(TacticalRouteBuilder.ladder_toward_deck(bare, 1) == Vector3.ZERO and TacticalRouteBuilder.ladder_toward_deck(climb, 9) == Vector3.ZERO, "Out of range, or no deck beside the segment: zero")

	# ---- A route with no surface data is walked exactly as authorised.
	var raw := PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 0)])
	var raw_segments: Array[StringName] = [&"move", &"move"]
	var through := TacticalRouteBuilder.passthrough(raw, raw_segments)
	check(through.points == raw and through.poses == raw_segments and through.stair_ids.is_empty() and through.kinds.is_empty() and through.report.is_empty() and through.pose_at(5) == &"move" and through.kind_at(5) == 0 and through.stair_id_at(5) == -1,
		"A passthrough route is the authorised path with no stair runs, kinds or report")

	# ---- Real routes of the production map: determinism, and TacticalUnit delegates (its route IS the builder's).
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	f.act_as(actor)
	for i in 20:
		await process_frame
	var data: MapData = f.grid.map_data
	var found := {"ladder": false, "stairs": false, "ramp": false}
	var starts: Array[Vector3i] = [Vector3i(12, 0, 4), Vector3i(6, 0, 15), Vector3i(3, 0, 5), Vector3i(8, 0, 9)]
	for link in data.traversal_links:
		starts.append(link.from_cell)
		starts.append(link.to_cell)
	for start in starts:
		if f.grid.get_cell_data(start) == null:
			continue
		if found.ladder and found.stairs and found.ramp:
			break
		f.place(actor, start)
		f.ready_actor(actor, 10, 4)
		var destinations: Array = f.battle._query_move_data(actor, Vector3i(-1, -1, -1)).get("legal_destinations", [])
		destinations.sort()
		var tried := 0
		for destination: Vector3i in destinations:
			if tried >= 60:
				break
			var detail: Dictionary = f.battle._query_move_data(actor, destination)
			if not detail.get("accepted", false) or not detail.has("presentation_path"):
				continue
			tried += 1
			var segments: Array[StringName] = []
			segments.assign(detail.visual_segments)
			var built := TacticalRouteBuilder.expand(data, detail.presentation_path, segments, actor.standing_height, actor.stair_profile, actor.path_presentation)
			var kind_name := "ladder" if built.kinds.has(TraversalLinkData.LADDER) else ("stairs" if built.kinds.has(TraversalLinkData.STAIRS) else ("ramp" if built.kinds.has(TraversalLinkData.RAMP) else ""))
			if kind_name.is_empty() or found[kind_name]:
				continue
			found[kind_name] = true
			var again := TacticalRouteBuilder.expand(data, detail.presentation_path, segments, actor.standing_height, actor.stair_profile, actor.path_presentation)
			check(_same_route(built, again), "A %s route builds identically twice (same inputs, same route)" % kind_name)
			actor.move_along_path(detail.presentation_path, segments)
			check(_same_route(actor.route, built) and actor.current_path == built.points, "TacticalUnit's route for that move IS the builder's, and the unit walks its points (%s)" % kind_name)
			if kind_name == "stairs":
				check(built.stair_runs.size() >= 1 and built.stair_ids.has(0) and built.stair_runs[0].model != null, "Stair legs carry their run: a model, a direction, where the route enters and leaves")
			actor.is_moving = false
	check(found.ladder and found.stairs and found.ramp, "The production map offered a ladder, a stair and a ramp route to check (%s)" % [found])

	# ---- The estimate the unit reports is the builder's, and authority is untouched by building a route.
	f.place(actor, Vector3i(12, 0, 4))
	f.ready_actor(actor, 6, 4)
	var ap_before := actor.stats.current_ap
	var cell_before := actor.grid_position
	var ladder_detail: Dictionary = f.battle._query_move_data(actor, Vector3i(12, 3, 5))
	var ladder_segments: Array[StringName] = []
	ladder_segments.assign(ladder_detail.visual_segments)
	actor.move_along_path(ladder_detail.presentation_path, ladder_segments)
	var expected := TacticalRouteBuilder.estimated_seconds(actor.route, actor.current_waypoint_idx, actor.global_position, actor.movement_speed, TacticalUnit.DEFAULT_MOVEMENT_SPEED, actor.stair_profile, actor.visual_adapter.traversal_profile)
	check(is_equal_approx(actor.estimated_move_seconds(), expected) and expected > 2.0, "The unit's estimate is the builder's (%.2f s for the ladder)" % expected)
	check(actor.stats.current_ap == ap_before and actor.grid_position == cell_before, "Building and showing a route changes neither AP nor the committed cell")
	actor.is_moving = false
	await f.dispose(self)

	print("Tactical route builder: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
