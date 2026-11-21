extends SceneTree
## Prototype fits/contact hints must stay separate from live tactical permission.
const Fit = preload("res://systems/grid/surface_placement.gd")
const Pose = preload("res://presentation/tactical/tactical_pose_context.gd")
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
	var intrusion := AABB(Vector3(0.15, 0, -2), Vector3(2, 2, 4))
	for scale: float in [1.0, 0.5]:
		for turn in 4:
			var transform := Transform3D(Basis(Vector3.UP, turn * PI * 0.5).scaled(Vector3.ONE * scale), Vector3(3, 0.4, -2))
			var center := transform * Vector3.ZERO
			var solids: Array[AABB] = [transform * intrusion]
			var result := Fit.resolve(center, solids, 0.28 * scale, 1.8 * scale, 0.04 * scale, scale)
			check(result.fits, "A partly occupied tile has a tested body-sized fit; scale %s, turn %d" % [scale, turn])
			if not result.fits: continue
			check(result.position.is_equal_approx(transform * Vector3(-0.17, 0, 0)), "The fit follows the actual edge, not a snapped full-tile reservation")
			var contact := Fit.contact(result.position, solids[0], 0.28 * scale, 1.8 * scale, 0.04 * scale)
			check(contact.found and contact.body_clear, "Resolved body clears the selected surface")
			check(contact.surface_position.is_equal_approx(transform * Vector3(0.15, 0.9, 0)), "Contact target lies on the real box face")
			check(contact.surface_normal.is_equal_approx((transform.basis * Vector3.LEFT).normalized()), "Outward contact direction rotates with the object")
			check(contact.desired_stand_point.is_equal_approx(result.position), "Contact target preserves body radius plus clearance")
	var corridor: Array[AABB] = [AABB(Vector3(-2, 0, -2), Vector3(1.8, 2, 4)), AABB(Vector3(0.2, 0, -2), Vector3(1.8, 2, 4))]
	check(not Fit.resolve(Vector3.ZERO, corridor).fits, "An undersized passage is rejected instead of relying on animation to hide clipping")
	var reversed := corridor.duplicate()
	reversed.reverse()
	check(Fit.resolve(Vector3.ZERO, corridor) == Fit.resolve(Vector3.ZERO, reversed), "Obstacle ordering does not change the prototype result")
	check(not Fit.resolve(Vector3.ZERO, [AABB(Vector3(-2, 0, -2), Vector3(4, 2, 4))]).fits, "A fully occupied cell has no false standing point")
	check(not Fit.resolve(Vector3.ZERO, [AABB(Vector3(-2, 0, -2), Vector3(4, 2, 4))], 0.0001, 1.8, 0).fits, "Small body radii do not turn collision tolerance into permission to stand inside a solid")
	check(Fit.resolve(Vector3.ZERO, [AABB(Vector3(-2, 2.3, -2), Vector3(4, 0.5, 4))]).position == Vector3.ZERO, "A safely overhead beam does not consume ground standing room")
	var wish := Fit.contact(Vector3(-0.7, 0, 0), intrusion)
	var close := Fit.resolve(Vector3.ZERO, [intrusion], 0.28, 1.8, 0.04, 1, wish.desired_stand_point)
	check(close.fits and close.position.is_equal_approx(Vector3(-0.17, 0, 0)), "Requested close-to-cover position is validated, not blindly applied")
	check(not Fit.contact(Vector3(0.3, 0, 0), intrusion).found, "A point inside an object cannot invent an outward pose target")
	check(not Fit.contact(Vector3.ZERO, AABB(Vector3(-1, 3, -1), Vector3(2, 1, 2))).found, "An unreachable overhead part is not an arm contact")
	check(not Fit.resolve(Vector3.ZERO, [], -1).fits, "Invalid body dimensions reject")
	check(not Fit.resolve(Vector3.ZERO, [AABB(Vector3.ZERO, Vector3.ZERO)]).fits, "Degenerate obstacle data rejects")
	var crowded: Array[AABB] = []
	for i in Fit.MAX_PARTS + 1: crowded.append(intrusion)
	check(Fit.resolve(Vector3.ZERO, crowded).reason == "Local geometry budget exceeded", "Crowded geometry returns an explicit bounded-search reason")
	var grid := GridManager.new()
	grid.map_data = TacticalMapBuilder.generate(8, 8, 1, 17)
	var cell := Vector3i(3, 0, 3)
	var ground := grid.get_cell_data(cell)
	var adjacent := grid.get_cell_data(cell + Vector3i.RIGHT)
	adjacent.cover_type = MapCellData.CoverType.LOW
	adjacent.cover_height = 0.8
	adjacent.authored_shot_parts.assign([AABB(ground.world_position + Vector3(0.65, 0, -0.45), Vector3(0.9, 0.8, 0.9))])
	var original := ground.world_position
	var pose := Pose.cover_at(grid, cell, Vector3.RIGHT)
	check(pose.type == MapCellData.CoverType.LOW and pose.has("surface_position"), "Existing authored-pose context exposes physical surface hints")
	check(is_equal_approx(pose.surface_position.x, original.x + 0.65), "Pose contact follows the object face rather than the tile edge at 0.5")
	check(grid.get_cell_data(cell).world_position == original and grid.occupancy_map.is_empty(), "Contact selection does not move a tactical anchor or change occupancy")
	var before := CombatRules.get_support_position(cell, grid)
	Fit.resolve(original, adjacent.authored_shot_parts)
	check(CombatRules.get_support_position(cell, grid) == before, "A prototype fit cannot silently change live LOS origins")
	# Explicitly install an anchor only in this isolated test map: CombatRules
	# already supports real XYZ surface positions, not just floor-height offsets.
	var fit := Fit.resolve(original, adjacent.authored_shot_parts)
	ground.world_position = fit.position
	var unit := TacticalUnit.new()
	unit.grid_position = cell
	check(CombatRules.get_shot_origin(unit, grid).is_equal_approx(fit.position + Vector3.UP * unit.standing_height), "An explicitly committed fixture anchor also moves the authoritative shot origin")
	unit.free()
	grid.free()
	print("Surface placement foundation: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
