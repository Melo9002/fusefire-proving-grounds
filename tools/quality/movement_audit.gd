extends SceneTree
## Movement foundations audit (diagnostic, not a test): measures how the tactical movement representation relates to the physical geometry on the Tactical Test Range.
## godot --headless --path . --script res://tools/quality/movement_audit.gd
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")


func _initialize() -> void:
	_run.call_deferred()


func _top_at(parts: Array, x: float, z: float) -> float:
	var best := -INF
	for part: AABB in parts:
		if x >= part.position.x and x <= part.end.x and z >= part.position.z and z <= part.end.z:
			best = maxf(best, part.end.y)
	return best


func _run() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var data: MapData = f.grid.map_data
	print("RES map: cell %.2f m, body radius %.2f clearance %.2f height %.2f, %d movement parts, %d links" % [data.surface_unit, data.body_radius, data.body_clearance, data.body_height, data.movement_parts.size(), data.traversal_links.size()])

	# ---- A. Stairs: tactical links vs the physical treads.
	print("RES --- A. staircase (TrainingGallery/Stairs: six 0.5 m treads of depth 0.5 m, four tactical steps of 1 m)")
	for link in data.traversal_links:
		var a := data.get_cell(link.from_cell)
		var b := data.get_cell(link.to_cell)
		if link.from_cell.x == 6 and abs(a.world_position.x - b.world_position.x) < 0.01 and absf(b.world_position.y - a.world_position.y) < 1.5:
			var route := SurfaceNavigation.traversal_route(data, a.world_position, b.world_position)
			var descr: Array[String] = []
			for p in route:
				descr.append("(%.2f,%.2f,%.2f)" % [p.x, p.y, p.z])
			print("RES link %s -> %s  cell floors y %.2f -> %.2f  route %s" % [link.from_cell, link.to_cell, a.world_position.y, b.world_position.y, " ".join(descr)])
	for z in [14.75, 14.25, 13.75, 13.25, 12.75, 12.25]:
		print("RES tread top at z=%.2f (x=6.0 in map space is %.1f): %.2f" % [z, 6.0, _top_at(data.movement_parts, -9.5 + 0.0, z - 15.0 + 0.0)])
	# ---- B. Partially obstructed tiles: how much of a blocked cell is really occupied?
	print("RES --- B. partially obstructed tiles (obstacle parts: footprint overlap of each cell, level-0 floor)")
	var half := Vector2(data.map_size) * 0.5
	var blocked_small := 0
	var blocked_total := 0
	var legal_partial := 0
	var examples: Array[String] = []
	var worst_ratio := 0.0
	for key: Vector2i in data.columns.keys():
		for cell: MapCellData in data.columns[key]:
			if cell.grid_position.y != 0 or not cell.support_surface:
				continue
			var min_x := (key.x - half.x) * data.surface_unit
			var min_z := (key.y - half.y) * data.surface_unit
			var covered := 0.0
			var tallest := 0.0
			for part: AABB in data.movement_parts:
				if part.position.y > 0.3 or part.end.y < 0.3:
					continue   # not an obstacle standing on level 0
				var ox := minf(part.end.x, min_x + data.surface_unit) - maxf(part.position.x, min_x)
				var oz := minf(part.end.z, min_z + data.surface_unit) - maxf(part.position.z, min_z)
				if ox > 0.0 and oz > 0.0:
					covered += ox * oz
					tallest = maxf(tallest, part.end.y)
			if covered <= 0.0:
				continue
			if cell.walkable:
				legal_partial += 1
			else:
				blocked_total += 1
				if covered < 0.4:
					blocked_small += 1
					if examples.size() < 4:
						examples.append("%s covered %.0f%% of the cell, obstacle height %.2f m" % [cell.grid_position, covered * 100.0, tallest])
				worst_ratio = maxf(worst_ratio, covered)
	print("RES level-0 cells overlapped by an obstacle: %d blocked, %d still walkable; of the blocked, %d are less than 40%% covered" % [blocked_total, legal_partial, blocked_small])
	for e in examples:
		print("RES   example blocked cell ", e)

	# ---- C. Round obstacles: footprint the movement code uses vs the real circle.
	print("RES --- C. round / small-footprint obstacles")
	var small := 0
	for part: AABB in data.movement_parts:
		if part.position.y < 0.3 and part.end.y > 1.0 and part.size.x < 0.8 and part.size.z < 0.8 and part.size.x > 0.05:
			small += 1
			if small <= 4:
				var reach := data.body_radius + data.body_clearance
				var expanded_area := (part.size.x + 2.0 * reach) * (part.size.z + 2.0 * reach)
				var cells_hit := 0
				for key: Vector2i in data.columns.keys():
					var min_x := (key.x - half.x) * data.surface_unit
					var min_z := (key.y - half.y) * data.surface_unit
					var cx := clampf(part.get_center().x, min_x, min_x + data.surface_unit)
					var cz := clampf(part.get_center().z, min_z, min_z + data.surface_unit)
					if Vector2(cx - part.get_center().x, cz - part.get_center().z).length() < maxf(part.size.x, part.size.z) * 0.5 + reach:
						cells_hit += 1
				print("RES   column %.2f x %.2f x %.2f m at (%.1f, %.1f): body-expanded footprint %.2f m2 (%.1f m wide), %d floor cells within body reach of it" % [part.size.x, part.size.y, part.size.z, part.get_center().x, part.get_center().z, expanded_area, part.size.x + 2.0 * reach, cells_hit])
	print("RES   %d thin vertical parts in total" % small)
	# ---- D. What the unit actually does going up the staircase: floor height of the unit vs the physical tread top beneath it (treads: world z centres -1.25..-3.75, 0.5 m deep, tops 0.5..3.0).
	print("RES --- D. measured trajectory of a real Move up the staircase")
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(6, 0, 15))
	f.ready_actor(actor, 6, 4)
	f.act_as(actor)
	for i in 20: await process_frame
	var done := []
	var go := func() -> void:
		done.append(await f.battle.try_move(actor, Vector3i(6, 3, 12)))
	go.call()
	var max_air := 0.0
	var max_sink := 0.0
	var frames := 0
	var max_rate := 0.0
	var last_y := actor.global_position.y
	var started := Time.get_ticks_msec()
	while done.is_empty() and Time.get_ticks_msec() - started < 20000:
		await process_frame
		var floor_y := actor.global_position.y - actor.standing_height
		var z := actor.global_position.z
		var tread_top := 0.0
		if z < -1.0:
			tread_top = clampf(0.5 * ceilf((-1.0 - z) / 0.5), 0.0, 3.0)
		max_air = maxf(max_air, floor_y - tread_top)
		max_sink = minf(max_sink, floor_y - tread_top)
		max_rate = maxf(max_rate, absf(actor.global_position.y - last_y) / maxf(get_root().get_process_delta_time(), 0.001))
		last_y = actor.global_position.y
		frames += 1
	print("RES moved %s in %d frames; floor height above the tread beneath: worst float %.2f m, worst sink %.2f m" % [done, frames, max_air, max_sink])
	# ---- E. Round objects: the current stamping (every cell the footprint touches becomes a whole-cell block) vs the exact CylinderPart queries (pure geometry, no map).
	print("RES --- E. a round obstacle of radius r on a 1 m grid: current whole-cell stamping vs CylinderPart exact queries (body radius 0.28 + 0.04)")
	for case in [[0.5, "centred on a cell"], [1.0, "centred on a cell"], [1.5, "centred on a cell"], [1.0, "on a cell corner"]]:
		var radius: float = case[0]
		var centre := Vector3(0.5, 0, 0.5) if case[1] == "centred on a cell" else Vector3(1.0, 0, 1.0)
		var cylinder := CylinderPart.create(Vector3(centre.x, 0.0, centre.z), radius, 2.5)
		var stamped := 0
		var standable := 0
		var blocked_edges_box := 0
		var blocked_edges_exact := 0
		for cx in range(-4, 6):
			for cz in range(-4, 6):
				var cell_centre := Vector3(cx + 0.5, 0, cz + 0.5)
				# Stamped: the cell overlaps the circle's footprint (the volume touches it).
				var nearest := Vector2(clampf(centre.x, cx, cx + 1.0), clampf(centre.z, cz, cz + 1.0))
				if nearest.distance_to(Vector2(centre.x, centre.z)) < radius:
					stamped += 1
				var fit := CylinderPart.resolve(cell_centre, [cylinder], 0.28, 1.8, 0.04, 1.0)
				if fit.get("fits", false) and Vector2(fit.position.x - cell_centre.x, fit.position.z - cell_centre.z).length() < 0.001:
					standable += 1
				# Edges between horizontally adjacent cell centres.
				var neighbour := cell_centre + Vector3(1, 0, 0)
				var box_blocked: bool = nearest.distance_to(Vector2(centre.x, centre.z)) < radius or Vector2(clampf(centre.x, cx + 1.0, cx + 2.0), clampf(centre.z, cz, cz + 1.0)).distance_to(Vector2(centre.x, centre.z)) < radius
				if box_blocked:
					blocked_edges_box += 1
				if not cylinder.segment_clear(cell_centre, neighbour, 0.28, 1.8, 0.04):
					blocked_edges_exact += 1
		print("RES   r=%.1f %s: %d cells stamped as blocks; %d cells where the cell centre itself is a legal stand point (exact); +x edges blocked: %d by the stamping, %d exactly" % [radius, case[1], stamped, standable, blocked_edges_box, blocked_edges_exact])
	await f.dispose(self)
	quit(0)
