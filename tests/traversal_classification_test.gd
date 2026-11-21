extends SceneTree
## Explicit traversal classification on the Tactical Test Range: ladders, stairs and ramps keep their identity from the authored scene into the map's links; only a DECLARED ladder
## gets rung contacts (an undeclared vertical link keeps the placeholder clips); a ramp is walked along its slope (not a vertical pop, not stair treads); legality and cost are untouched.
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

func _walk_ramp(f, actor: TacticalUnit, adapter: UnitVisualAdapter, destination: Vector3i) -> Dictionary:
	var poses: Array[StringName] = []
	var on_state := func(pose: StringName) -> void: poses.append(pose)
	adapter.presentation_state_changed.connect(on_state)
	var done := []
	var go := func() -> void:
		done.append(await f.battle.try_move(actor, destination))
	go.call()
	var worst := 0.0
	var guard := 0
	var stairs_seen := false
	var ladder_seen := false
	while done.is_empty() and guard < 3000:
		guard += 1
		await process_frame
		var floor_position := actor.global_position - Vector3.UP * actor.standing_height
		# The ramp rises one metre per metre of run from world z -0.5 (floor 0) toward -z up to its lip at z -3.0, where the exit deck (3.0) begins. At the lip plane itself the unit
		# steps between the two, so those frames are not judged.
		if absf(floor_position.z - (-3.0)) > 0.07:
			worst = maxf(worst, absf(floor_position.y - (-0.5 - floor_position.z if floor_position.z > -3.0 else 3.0)))
		stairs_seen = stairs_seen or adapter.stairs != null
		ladder_seen = ladder_seen or adapter.is_ladder_active()
	adapter.presentation_state_changed.disconnect(on_state)
	return {"ok": bool(done[0]) if not done.is_empty() else false, "worst": worst, "poses": poses, "stairs": stairs_seen, "ladder": ladder_seen}

func _run() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var data: MapData = f.grid.map_data
	var counts := {TraversalLinkData.UNSPECIFIED: 0, TraversalLinkData.RAMP: 0, TraversalLinkData.STAIRS: 0, TraversalLinkData.LADDER: 0}
	for link in data.traversal_links:
		counts[link.surface_kind] += 1
	print("  range links: %d ladder, %d stairs, %d ramp, %d unspecified" % [counts[TraversalLinkData.LADDER], counts[TraversalLinkData.STAIRS], counts[TraversalLinkData.RAMP], counts[TraversalLinkData.UNSPECIFIED]])
	check(counts[TraversalLinkData.LADDER] == 3 and counts[TraversalLinkData.STAIRS] == 3 and counts[TraversalLinkData.RAMP] == 3 and counts[TraversalLinkData.UNSPECIFIED] == 0, "The range's nine links keep their identity: 3 ladders, 3 stair steps, 3 ramp steps, none undeclared")
	var ladder_link := SurfaceNavigation.link_between(data, data.get_cell(Vector3i(12, 0, 4)).world_position, data.get_cell(Vector3i(12, 3, 5)).world_position)
	check(ladder_link != null and ladder_link.surface_kind == TraversalLinkData.LADDER and ladder_link.treads_per_step == 0, "A ladder link is a LADDER and has no treads")
	check(SurfaceNavigation.stair_link(data, data.get_cell(Vector3i(12, 0, 4)).world_position, data.get_cell(Vector3i(12, 3, 5)).world_position) == null, "A ladder is never reported as a stair")
	var ramp_from := data.get_cell(Vector3i(11, 0, 15)).world_position
	var ramp_to := data.get_cell(Vector3i(11, 1, 14)).world_position
	check(SurfaceNavigation.stair_link(data, ramp_from, ramp_to) == null and SurfaceNavigation.link_between(data, ramp_from, ramp_to).surface_kind == TraversalLinkData.RAMP, "A ramp is a RAMP and never a stair")

	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(11, 0, 15))
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	var adapter: UnitVisualAdapter = actor.visual_adapter
	for i in 20: await process_frame
	var ap_before := actor.stats.current_ap

	# ---- Ramp as declared: walked along the slope.
	var ramp := await _walk_ramp(f, actor, adapter, Vector3i(11, 3, 12))
	var ramp_cost := ap_before - actor.stats.current_ap
	check(ramp.ok and actor.grid_position == Vector3i(11, 3, 12), "The ramp is walked through the normal Move action and ends on its cell")
	check(float(ramp.worst) < 0.02, "The unit stays on the ramp's slope (worst deviation %.3f m; with the old vertical-then-level route it was up to 1 m)" % ramp.worst)
	check(not ramp.stairs and not ramp.ladder and not (&"climb" in ramp.poses) and not (&"vault" in ramp.poses), "A ramp triggers no stair contacts, no ladder pose and no climb clip (states %s)" % [ramp.poses])

	# ---- The same ramp with its identity removed: the old presentation (a measurable difference), identical cost and cell.
	for link in data.traversal_links:
		if link.surface_kind == TraversalLinkData.RAMP:
			link.surface_kind = TraversalLinkData.UNSPECIFIED
	f.place(actor, Vector3i(11, 0, 15))
	f.ready_actor(actor, 6, 4)
	var before := actor.stats.current_ap
	var undeclared := await _walk_ramp(f, actor, adapter, Vector3i(11, 3, 12))
	check(float(undeclared.worst) > 0.4, "Undeclared, the old route returns (deviation %.2f m): the metadata is what fixes it" % undeclared.worst)
	check(before - actor.stats.current_ap == ramp_cost and actor.grid_position == Vector3i(11, 3, 12), "Declaring or not changes nothing tactical: same AP (%d) and same cell" % ramp_cost)

	# ---- A ladder whose declaration is removed is an undeclared vertical link: no rung contacts, the placeholder climb clip (no guessing from height).
	ladder_link.surface_kind = TraversalLinkData.UNSPECIFIED
	f.place(actor, Vector3i(12, 0, 4))
	f.ready_actor(actor, 6, 4)
	var generic := await _walk_ramp(f, actor, adapter, Vector3i(12, 3, 5))
	check(generic.ok and actor.grid_position == Vector3i(12, 3, 5), "An undeclared vertical link is still walkable (legality untouched)")
	check(not generic.ladder and (&"climb" in generic.poses), "...but gets no ladder presentation, only the placeholder climb clip (%s)" % [generic.poses])

	await f.dispose(self)
	print("Traversal classification: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
