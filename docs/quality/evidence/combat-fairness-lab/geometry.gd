extends SceneTree
## Analytic geometry fixture. Engine segment intersection is independent of
## CombatRules' indexed obstacle lookup, endpoint and seam code.

var _checked := 0
var _errors := 0
var _opportunity_rejections := [0, 0, 0, 0]
var _directions_open := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var grid := GridManager.new()
	var a := TacticalUnit.new()
	var b := TacticalUnit.new()
	a.stats = UnitStats.new()
	b.stats = UnitStats.new()
	a.attack_range = 20
	b.attack_range = 20
	a.standing_height = 1.0
	b.standing_height = 1.0
	var fixtures := [
		{"id":"open", "parts":[]},
		{"id":"full_wall", "parts":[AABB(Vector3(-0.25, -0.1, -0.45), Vector3(0.5, 3, 0.9))]},
		{"id":"low_cover", "parts":[AABB(Vector3(-0.25, -0.1, -0.45), Vector3(0.5, 0.8, 0.9))]},
		{"id":"near_edge_one_way", "parts":[AABB(Vector3(-1.9, -0.1, -0.19), Vector3(0.2, 3, 0.38))]},
		{"id":"chest_and_head_occluded", "parts":[AABB(Vector3(-0.20, 1.02, -0.45), Vector3(0.4, 1.3, 0.9))]},
		{"id":"diagonal_clear", "parts":[AABB(Vector3(-0.2, -0.1, 0.25), Vector3(0.4, 3, 0.3))], "target":Vector3(3, 0, -2)},
		{"id":"diagonal_blocked", "parts":[AABB(Vector3(-0.2, -0.1, -1.19), Vector3(0.4, 3, 0.38))], "target":Vector3(3, 0, -2)},
		{"id":"narrow_window", "parts":[AABB(Vector3(-0.2, -0.1, -0.45), Vector3(0.4, 1.02, 0.9)),
			AABB(Vector3(-0.2, 1.17, -0.45), Vector3(0.4, 1.5, 0.9))]},
		{"id":"raised_clear", "parts":[AABB(Vector3(-0.25, -0.1, -0.45), Vector3(0.5, 1.45, 0.9))], "target":Vector3(3, 1.8, 0)},
		{"id":"cylinder_core", "parts":[], "cylinder":[Vector3.ZERO, 0.6]},
		{"id":"cylinder_clear_edge", "parts":[], "cylinder":[Vector3(0, 0, 0.72), 0.55]},
	]
	for fixture in fixtures:
		for turn in 4:
			for mirrored in [false, true]:
				_compare(fixture, turn, mirrored, grid, a, b)
	print("[GeometrySummary] ", JSON.stringify({"queries":_checked, "oracle_mismatches":_errors,
		"physically_open_directed_states":_directions_open, "physical_opportunities_rejected_by_policy":_opportunity_rejections}))
	a.free()
	b.free()
	grid.free()
	quit(int(_errors > 0))

func _compare(fixture: Dictionary, turn: int, mirrored: bool, grid: GridManager, a: TacticalUnit, b: TacticalUnit) -> void:
	var rotation := Basis(Vector3.UP, turn * PI * 0.5)
	var reflection := Basis.from_scale(Vector3(-1, 1, 1) if mirrored else Vector3.ONE)
	var xf := Transform3D(rotation * reflection, Vector3.ZERO)
	var from := xf * Vector3(-3, 0, 0)
	var to := xf * (fixture.get("target", Vector3(3, 0, 0)) as Vector3)
	grid.map_data = MapData.new()
	grid.map_data.map_size = Vector2i(12,12)
	grid.map_data.surface_placement_enabled = true
	a.grid_position = Vector3i(roundi(from.x) + 6, roundi(from.y), roundi(from.z) + 6)
	b.grid_position = Vector3i(roundi(to.x) + 6, roundi(to.y), roundi(to.z) + 6)
	grid.map_data.add_cell(MapCellData.new(a.grid_position, from))
	grid.map_data.add_cell(MapCellData.new(b.grid_position, to))
	var parts: Array[AABB] = []
	for authored in fixture.parts:
		var box: AABB = xf * (authored as AABB)
		parts.append(box)
		var obstacle := MapCellData.new(Vector3i(6, 0, 6), Vector3(box.get_center().x, box.position.y, box.get_center().z))
		obstacle.authored_shot_bounds = box
		obstacle.cover_height = box.size.y + 0.002
		obstacle.blocks_line_of_sight = true
		grid.map_data.add_shot_obstacle(obstacle)
	var circle := []
	if fixture.has("cylinder"):
		circle = [xf * fixture.cylinder[0], fixture.cylinder[1]]
		var cylinder := CylinderPart.new()
		cylinder.center = circle[0]
		cylinder.radius = circle[1]
		cylinder.height = 2.0
		grid.map_data.add_curved_obstacle(cylinder, 1)
	grid.map_data.rebuild_los_index()
	var oracle := [_rays(from, to, parts, circle), _rays(to, from, parts, circle)]
	var policy_rows := []
	for mode in 4:
		grid.map_data.engagement_policy = mode
		var central := mode == 1 or mode == 3
		var mutual := mode >= 2
		var eligible := []
		for ray_set in oracle:
			eligible.append((ray_set[0] or ray_set[1]) if central else true in ray_set)
		var evaluations := []
		for swapped in [false, true]:
			a.faction = TacticalUnit.Faction.ENEMY if swapped else TacticalUnit.Faction.PLAYER
			b.faction = TacticalUnit.Faction.PLAYER if swapped else TacticalUnit.Faction.ENEMY
			for dir in 2:
				var actor := a if dir == 0 else b
				var victim := b if dir == 0 else a
				var actual := CombatRules.evaluate_attack(actor, victim, grid, null)
				var expected: bool = eligible[dir] and (not mutual or eligible[1-dir])
				var physical: bool = true in oracle[dir]
				if mode == 0: _directions_open += int(physical)
				_opportunity_rejections[mode] += int(physical and not actual.is_legal)
				_checked += 1
				if expected != actual.is_legal:
					_errors += 1
					push_error("%s turn=%d reflected=%s swapped=%s mode=%d dir=%d expected=%s actual=%s" % [
						fixture.id, turn, mirrored, swapped, mode, dir, expected, actual.reason])
				evaluations.append({"legal":actual.is_legal,"reason":actual.reason,"chance":actual.hit_chance})
		policy_rows.append(evaluations)
	print("[GeometryCase] ", JSON.stringify({"fixture":fixture.id,"rotation":turn,"reflection":mirrored,"direct_rays":oracle,"modes":policy_rows}))

func _rays(from: Vector3, to: Vector3, parts: Array[AABB], circle: Array) -> Array[bool]:
	var start := from + Vector3.UP
	var heading := to - from
	var perpendicular := Vector3(-heading.z, 0, heading.x).normalized() * 0.28
	var samples := [to + Vector3.UP * 1.2, to + Vector3.UP * 1.75,
		to + Vector3.UP * 0.9 + perpendicular, to + Vector3.UP * 0.9 - perpendicular, to + Vector3.UP * 0.5]
	var open: Array[bool] = []
	for dest: Vector3 in samples:
		var hit := false
		for box in parts: hit = hit or box.intersects_segment(start, dest) != null
		if not circle.is_empty():
			# These cylinder fixtures fully enclose the rays' vertical interval.
			var center := Vector2(circle[0].x, circle[0].z)
			var closest := Geometry2D.get_closest_point_to_segment(center, Vector2(start.x, start.z), Vector2(dest.x, dest.z))
			hit = hit or center.distance_to(closest) < float(circle[1])
		open.append(not hit)
	return open

