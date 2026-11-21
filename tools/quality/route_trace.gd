extends SceneTree
## Deterministic route-presentation trace (Task 07 package 8). On the production Tactical Test Range it takes the legal routes from many starting places (around every traversal link, the ladder foot, the stair foot,
## open ground), feeds each authorised route to TacticalUnit.move_along_path with the path refinement off and on, and records the presented route (waypoints, leg kinds, stair run ids and runs, poses, the
## refinement report, the estimated duration) and a frame-stepped walk of it (frames, the waypoint at which each frame ends, the presented speed and the presentation state at every segment change). Compare two
## outputs (before and after a change) with an exact check on the discrete data and a stated tolerance on floats. Run:
##   godot_console --headless --path . --script res://tools/quality/route_trace.gd -- <output.json>
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
const DT := 1.0 / 60.0
const MAX_DESTINATIONS_PER_START := 45
var routes := {}
var kind_histogram := {}

func _initialize() -> void:
	_run.call_deferred()

func _r(x: float) -> float:
	return snappedf(x, 0.000001)

func _v(v: Vector3) -> Array:
	return [_r(v.x), _r(v.y), _r(v.z)]

## The route state of a unit, read through whichever owner the code under test has (the unit's own fields before Task 07 package 8, its route object after).
func _state(actor: TacticalUnit) -> Dictionary:
	var kinds: Array = []
	var ids: Array = []
	var runs: Array = []
	var report: Dictionary = {}
	var poses: Array = []
	if actor.get("route") != null:
		var route = actor.route
		kinds = route.kinds
		ids = route.stair_ids
		poses = route.poses
		for run in route.stair_runs:
			runs.append([bool(run.ascending), _r(float(run.enter)), _r(float(run.exit)), _r(float(run.model.end_s()))])
		report = route.report
	else:
		kinds = actor.get("_leg_kinds")
		ids = actor.get("_stair_ids")
		poses = actor.get("_visual_segments")
		for run in actor.get("_stair_runs"):
			runs.append([bool(run.ascending), _r(float(run.enter)), _r(float(run.exit)), _r(float(run.model.end_s()))])
		report = actor.last_path_report
	var path: Array = []
	for p in actor.current_path:
		path.append(_v(p))
	return {"path": path, "kinds": Array(kinds).duplicate(), "stair_ids": Array(ids).duplicate(), "poses": Array(poses).map(func(s): return String(s)), "runs": runs,
		"mismatches": Array(report.get("mismatches", [])).size(), "rounded": int(report.get("rounded", 0)), "estimate": _r(actor.estimated_move_seconds())}

## Walks the presented route frame by frame (no engine frames pass: the unit's own update is called directly with a fixed delta).
func _walk(actor: TacticalUnit) -> Dictionary:
	var frames := 0
	var waypoint_frames: Array = []
	var changes: Array = []
	var last_index := -1
	while actor.is_moving and frames < 6000:
		actor._process(DT)
		frames += 1
		if actor.current_waypoint_idx != last_index:
			last_index = actor.current_waypoint_idx
			waypoint_frames.append([last_index, frames])
			changes.append([last_index, _r(float(actor.get("_segment_speed"))), String(actor.visual_adapter.get_presentation_state()), actor.visual_adapter.is_ladder_active(), _r(actor.global_position.y)])
	return {"frames": frames, "waypoint_frames": waypoint_frames, "changes": changes, "end": _v(actor.global_position), "moving": actor.is_moving}

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path := args[0] if args.size() > 0 else "route_trace.json"
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	f.act_as(actor)
	for i in 20:
		await process_frame
	var data: MapData = f.grid.map_data
	var starts: Array[Vector3i] = [Vector3i(12, 0, 4), Vector3i(12, 3, 5), Vector3i(3, 0, 5), Vector3i(8, 0, 9), Vector3i(6, 0, 15), Vector3i(2, 0, 4), Vector3i(21, 0, 9), Vector3i(21, 0, 11)]
	for link in data.traversal_links:
		for cell in [link.from_cell, link.to_cell]:
			if not starts.has(cell):
				starts.append(cell)
	var count := 0
	for start in starts:
		if f.grid.get_cell_data(start) == null:
			continue
		f.place(actor, start)
		f.ready_actor(actor, 10, 4)
		var query: Dictionary = f.battle._query_move_data(actor, Vector3i(-1, -1, -1))
		var destinations: Array = query.get("legal_destinations", [])
		destinations.sort()   # a stable order independent of the query's own
		var tested := 0
		for destination: Vector3i in destinations:
			if tested >= MAX_DESTINATIONS_PER_START:
				break
			var detail: Dictionary = f.battle._query_move_data(actor, destination)
			if not detail.get("accepted", false) or not detail.has("presentation_path"):
				continue
			tested += 1
			var presentation: PackedVector3Array = detail.presentation_path
			var segments: Array[StringName] = []
			segments.assign(detail.visual_segments)
			var input_path: Array = []
			for p in presentation:
				input_path.append(_v(p))
			var entry := {"input": input_path, "segments": Array(segments).map(func(s): return String(s))}
			for mode in ["plain", "refined"]:
				actor.path_presentation.enabled = mode == "refined"
				actor.move_along_path(presentation, segments)
				var state := _state(actor)
				state["walk"] = _walk(actor)
				entry[mode] = state
				for kind in state.kinds:
					kind_histogram[int(kind)] = int(kind_histogram.get(int(kind), 0)) + 1
				actor.is_moving = false
				actor.global_position = presentation[0]
			routes["%s->%s" % [start, destination]] = entry
			count += 1
	actor.path_presentation.enabled = false
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"routes": routes, "kinds": kind_histogram}))
	file.close()
	print("route_trace: %d routes from %d starts written to %s; leg kinds seen: %s" % [count, starts.size(), out_path, kind_histogram])
	quit(0)
