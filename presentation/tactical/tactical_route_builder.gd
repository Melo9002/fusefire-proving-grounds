class_name TacticalRouteBuilder
extends RefCounted
## Presentation-route construction (Task 07 package 8). The tactical layer authorises a route (cells, AP, legality); this turns the authorised waypoints into the route that is SHOWN: the stair runs walked on
## their treads (StairModel), ramps walked along their slope, ladder and vault legs, the corners smoothed within the body's clearance (PathRefiner), each point carrying its pose, its leg kind and the stair
## run it belongs to, and the speeds the walk is presented at. Pure functions of explicit inputs: no node, no TacticalUnit, no visual adapter, no randomness, so the same inputs give the same route (replay-safe).
## It decides nothing the game rules depend on: cells, AP, occupancy, traversal legality and the replay record stay with their authoritative owners; only the time a move takes to SHOW changes with the speeds.
## The algorithms and numbers were moved here unchanged from TacticalUnit.

## The leg kind of a low-cover vault (the other kinds are TraversalLinkData's: 0 plain, RAMP, STAIRS, LADDER).
const VAULT_KIND := 10

## One run of stair links walked as a unit: the model of its treads, the direction, and where along it the route enters and leaves.
class StairRun extends RefCounted:
	var model: StairModel
	var ascending := false
	var enter := 0.0
	var exit := 0.0

## The presented route. `points`, `poses`, `stair_ids` and `kinds` are parallel (one entry per waypoint); an empty `stair_ids` or `kinds` means "none" (an unexpanded route).
class Route extends RefCounted:
	var points := PackedVector3Array()
	var poses: Array[StringName] = []
	var stair_ids: Array[int] = []
	var kinds: Array[int] = []
	var stair_runs: Array[StairRun] = []
	## The refinement's report: {"mismatches": Array[String], "rounded": int}, or {} when the refinement did not run.
	var report := {}

	func pose_at(index: int) -> StringName:
		return poses[index] if index >= 0 and index < poses.size() else &"move"

	func stair_id_at(index: int) -> int:
		return stair_ids[index] if index >= 0 and index < stair_ids.size() else -1

	func kind_at(index: int) -> int:
		return kinds[index] if index >= 0 and index < kinds.size() else 0

## A route that is walked exactly as authorised (no surface data to expand it with).
static func passthrough(path: PackedVector3Array, visual_segments: Array[StringName]) -> Route:
	var route := Route.new()
	route.points = path
	route.poses = visual_segments
	return route

## Expands an authorised route over the map's surfaces. `path` is the tactical waypoints (a unit's standing height above the floor); `visual_segments` the pose of each leg; `standing_height` lifts the
## floor-level geometry back to where the body is. `stair_profile` and `path_presentation` are the unit's presentation settings.
static func expand(data: MapData, path: PackedVector3Array, visual_segments: Array[StringName], standing_height: float, stair_profile: StairProfile, path_presentation: PathPresentationProfile) -> Route:
	var route := Route.new()
	var up := Vector3.UP * standing_height
	var expanded := PackedVector3Array([path[0]])
	var poses: Array[StringName] = [visual_segments[0] if not visual_segments.is_empty() else &"move"]
	var stair_ids: Array[int] = [-1]
	var kinds: Array[int] = [0]
	var index := 1
	while index < path.size():
		# A run of authored stair links in one direction is walked ON its treads (StairModel), not as vertical-then-level legs.
		var run_end := _stair_run_end(data, path, index, standing_height, stair_profile)
		if run_end >= index:
			var model := _stair_model(data, path, index, run_end, standing_height)
			if model != null:
				var ascending := path[run_end].y > path[index - 1].y
				var points := model.path_points(ascending, stair_profile.riser_ramp, stair_profile.landing_tail)
				for point_index in range(1, points.size()):
					expanded.append(points[point_index] + up)
					poses.append(&"move")
					stair_ids.append(route.stair_runs.size())
					kinds.append(TraversalLinkData.STAIRS)
				var stair_run := StairRun.new()
				stair_run.model = model
				stair_run.ascending = ascending
				stair_run.enter = model.progress_of(path[index - 1] - up)
				stair_run.exit = model.progress_of(path[run_end] - up)
				route.stair_runs.append(stair_run)
				index = run_end + 1
				continue
		var from_floor := path[index - 1] - up
		var to_floor := path[index] - up
		var link := SurfaceNavigation.link_between(data, from_floor, to_floor)
		if link != null and link.surface_kind == TraversalLinkData.RAMP:
			# A ramp is a continuous incline: the walk follows the slope, never a vertical pop; it is walked, not climbed. Where the physical ramp ends at the cell boundary
			# (the link's `step_at_to`: a step up onto the deck) the slope runs to that boundary and the step is made there, so the body never goes below the deck.
			var step_up := link.step_at_to
			var toward_to := data.get_cell(link.to_cell).world_position.is_equal_approx(to_floor)   # walking in the link's own direction (entry -> exit)
			var points: Array[Vector3] = []
			if step_up:
				var middle := (from_floor + to_floor) * 0.5
				var upper := to_floor if toward_to else from_floor
				var lower_y := from_floor.y if toward_to else to_floor.y
				var slope_end := Vector3(middle.x, (from_floor.y + to_floor.y) * 0.5, middle.z)
				var lip_top := Vector3(middle.x, upper.y, middle.z)
				if toward_to:
					points = [slope_end, lip_top, to_floor]
				else:
					points = [lip_top, slope_end, to_floor]
				if lower_y > upper.y:
					points = [to_floor]   # defensive: malformed data keeps the plain slope
			else:
				points = [to_floor]
			for point in points:
				expanded.append(point + up)
				poses.append(&"move")
				stair_ids.append(-1)
				kinds.append(TraversalLinkData.RAMP)
			index += 1
			continue
		var leg_route := SurfaceNavigation.traversal_route(data, from_floor, to_floor)
		var kind: int = link.surface_kind if link != null else 0
		if leg_route.size() == 4:
			kind = VAULT_KIND
		for waypoint in range(1, leg_route.size()):
			expanded.append(leg_route[waypoint] + up)
			var pose: StringName = visual_segments[index] if index < visual_segments.size() else &"move"
			if leg_route.size() == 4: pose = &"vault"
			poses.append(pose)
			stair_ids.append(-1)
			kinds.append(kind)
		index += 1
	if path_presentation != null and path_presentation.enabled:
		var refined := _refine_flat_runs(data, expanded, poses, stair_ids, kinds, standing_height, path_presentation)
		expanded = refined.points
		poses = refined.poses
		stair_ids = refined.stair_ids
		kinds = refined.kinds
		route.report = refined.report
	route.points = expanded
	route.poses = poses
	route.stair_ids = stair_ids
	route.kinds = kinds
	return route

## The speed at which a route segment is PRESENTED. The tactical route is walked at `movement_speed` (5 m/s by default), which would take a 4 m ladder 0.8 s; a ladder or stair segment is slower
## (`segment_speed`, from TraversalProfile.climb_speed / descend_speed or StairProfile.speed), scaled by how far movement_speed is from its default so replay playback speeds still apply.
## Only the time the move takes to show changes: cells, AP, positions and the replay record are untouched.
static func presented_speed(segment_speed: float, movement_speed: float, default_movement_speed: float) -> float:
	if segment_speed <= 0.0:
		return movement_speed
	return minf(movement_speed, segment_speed * movement_speed / default_movement_speed)

## The segment speed of a stair run's legs (0 when slow stairs are off: the ordinary walking speed applies).
static func stair_segment_speed(stair_profile: StairProfile) -> float:
	return stair_profile.speed if stair_profile.slow_stairs_enabled else 0.0

## How long the rest of a route will take to PRESENT, in seconds, from waypoint `from_index` (the walk is at `start`), at the speeds the walk will use (route speed, stair speed, ladder speeds; all scaled by
## movement_speed as in presented_speed). The action presenter uses it so a slow traversal is never mistaken for a stuck one.
static func estimated_seconds(route: Route, from_index: int, start: Vector3, movement_speed: float, default_movement_speed: float, stair_profile: StairProfile, traversal_profile: TraversalProfile) -> float:
	var total := 0.0
	var from := start
	for index in range(from_index, route.points.size()):
		var to: Vector3 = route.points[index]
		var speed := movement_speed
		var speed_scale := movement_speed / default_movement_speed
		if route.stair_id_at(index) >= 0 and index < route.stair_ids.size() and stair_profile.slow_stairs_enabled:
			speed = minf(movement_speed, stair_profile.speed * speed_scale)
		elif route.kind_at(index) == TraversalLinkData.LADDER and absf(to.y - from.y) > 0.05 and traversal_profile != null and traversal_profile.slow_ladder_enabled:
			var ladder_speed: float = traversal_profile.climb_speed if to.y > from.y else traversal_profile.descend_speed
			speed = minf(movement_speed, ladder_speed * speed_scale)
		total += from.distance_to(to) / maxf(speed, 0.01)
		from = to
	return total

## For a vertical ladder segment, the horizontal direction from the ladder toward its top deck: the next waypoint after a climb (the step onto the deck) or the previous one before a descent (the step off it).
## ZERO when the segment is not part of such a route.
static func ladder_toward_deck(path: PackedVector3Array, index: int) -> Vector3:
	if index < 0 or index >= path.size():
		return Vector3.ZERO
	var here: Vector3 = path[index]
	var before: Vector3 = path[index - 1] if index > 0 else here
	var rising := here.y > before.y
	if rising and index + 1 < path.size():
		return path[index + 1] - here
	if not rising and index > 0 and index - 1 > 0:
		return path[index - 2] - before
	return Vector3.ZERO

## The last path index of the run of consecutive stair links starting at `index` (the leg path[index-1] -> path[index]), or index - 1 when that leg is not a stair link.
static func _stair_run_end(data: MapData, path: PackedVector3Array, index: int, standing_height: float, stair_profile: StairProfile) -> int:
	if stair_profile == null or not stair_profile.enabled:
		return index - 1
	var up := Vector3.UP * standing_height
	var first := SurfaceNavigation.stair_link(data, path[index - 1] - up, path[index] - up)
	if first == null:
		return index - 1
	var direction := (path[index] - path[index - 1])
	var end := index
	while end + 1 < path.size():
		var next := SurfaceNavigation.stair_link(data, path[end] - up, path[end + 1] - up)
		if next == null or next.treads_per_step != first.treads_per_step:
			break
		var step := path[end + 1] - path[end]
		if not is_equal_approx(step.y, direction.y) or not Vector2(step.x, step.z).is_equal_approx(Vector2(direction.x, direction.z)):
			break   # a turn or a different rise: a separate run (or the ordinary route)
		end += 1
	return end

static func _stair_model(data: MapData, path: PackedVector3Array, first: int, last: int, standing_height: float) -> StairModel:
	var up := Vector3.UP * standing_height
	var from_floor := path[first - 1] - up
	var to_floor := path[last] - up
	var link := SurfaceNavigation.stair_link(data, path[first - 1] - up, path[first] - up)
	var links := last - first + 1
	var leg := path[first] - path[first - 1]
	var run := Vector2(leg.x, leg.z).length()
	var low := from_floor if from_floor.y < to_floor.y else to_floor
	var high := to_floor if from_floor.y < to_floor.y else from_floor
	return StairModel.from_links(low, high, run, absf(leg.y), link.treads_per_step, links)

## Smooths the corners of each horizontal run of the route within the body clearance (PathRefiner). Points inherit the pose and stair id of the original point they replace; a route
## the physical geometry does not support is reported (`report`) and left exactly as it was.
static func _refine_flat_runs(data: MapData, points: PackedVector3Array, poses: Array[StringName], stair_ids: Array[int], kinds: Array[int], standing_height: float, path_presentation: PathPresentationProfile) -> Dictionary:
	var up := Vector3.UP * standing_height
	var radius := data.body_radius + data.body_clearance - data.surface_unit / 10000.0
	var out := PackedVector3Array([points[0]])
	var out_poses: Array[StringName] = [poses[0]]
	var out_ids: Array[int] = [stair_ids[0]]
	var out_kinds: Array[int] = [kinds[0]]
	var mismatches: Array[String] = []
	var rounded := 0
	var i := 0
	var count := points.size()
	while i < count - 1:
		var j := i + 1
		if absf(points[i + 1].y - points[i].y) <= PathRefiner.FLAT:
			while j + 1 < count and absf(points[j + 1].y - points[i].y) <= PathRefiner.FLAT:
				j += 1
		if j - i >= 2:
			var run := PackedVector3Array()
			for k in range(i, j + 1):
				run.append(points[k] - up)
			var result := PathRefiner.refine(run, data.movement_parts, radius, data.body_height, path_presentation)
			mismatches.append_array(result.mismatches)
			rounded += int(result.rounded)
			for k in range(1, result.path.size()):
				var original := i + int(result.sources[k])
				out.append(result.path[k] + up)
				out_poses.append(poses[original])
				out_ids.append(stair_ids[original])
				out_kinds.append(kinds[original])
		else:
			out.append(points[j])
			out_poses.append(poses[j])
			out_ids.append(stair_ids[j])
			out_kinds.append(kinds[j])
		i = j
	var report := {"mismatches": mismatches, "rounded": rounded}
	if not mismatches.is_empty():
		return {"points": points, "poses": poses, "stair_ids": stair_ids, "kinds": kinds, "report": report}
	return {"points": out, "poses": out_poses, "stair_ids": out_ids, "kinds": out_kinds, "report": report}
