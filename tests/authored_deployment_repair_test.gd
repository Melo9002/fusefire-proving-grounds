extends SceneTree

const Repair = preload("res://systems/generation/authored_deployment_repair.gd")
const Urban = preload("res://systems/generation/urban_family_layout.gd")
const Refinery = preload("res://systems/generation/refinery_family_layout.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	# Exercise a real compiled gallery support rather than invented mesh geometry.
	var data := Urban.generate(17)
	var blocked := Vector3i(-1, 0, -1)
	for position: Vector3i in data.cells:
		var cell := data.get_cell(position)
		if position.y == 0 and position.z > 1 and position.z < 62 and not cell.can_stop:
			blocked = position
			break
	check(blocked.x >= 0, "Real courtyard contains authored non-stopping terrain")
	var zone := data.get_zone(&"deployment_2")
	zone.cells = [blocked]
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	check(not MapValidator.validate(data, graph).is_valid(), "Baseline detects a deployment placed inside real authored terrain")
	var original_column := blocked.x
	check(Repair.apply(data), "Blocked deployment can be repaired within its original column")
	check(zone.cells[0] != blocked and zone.cells[0].x == original_column, "Repair preserves the deployment edge/column")
	MapGraphBuilder.build(data, graph)
	check(MapValidator.validate(data, graph).is_valid(), "Repaired deployment passes actual tactical validation")
	var accepted := zone.cells.duplicate()
	check(Repair.apply(data) and zone.cells == accepted, "Repair preserves valid deployment and is idempotent")
	for row in range(data.map_size.y):
		var cell := data.get_cell(Vector3i(original_column, 0, row))
		cell.walkable = false
		cell.can_stop = false
	zone.cells = [blocked]
	check(not Repair.apply(data) and zone.cells == [blocked], "Unsatisfiable column fails without partial zone changes")
	for layout in [Urban, Refinery]:
		for map_seed in range(16):
			var compiled: MapData = layout.generate(map_seed)
			var repeated: MapData = layout.generate(map_seed)
			check(compiled.generation_errors.is_empty(), "%s seed %d constructs successfully" % [layout.SOURCE_KIND, map_seed])
			MapGraphBuilder.build(compiled, graph)
			check(MapValidator.validate(compiled, graph).is_valid(), "%s seed %d validates all three deployment factions" % [layout.SOURCE_KIND, map_seed])
			for faction in [0, 1, 2]:
				check(compiled.get_spawn_cells(faction) == repeated.get_spawn_cells(faction), "Deployment repair is deterministic")
	print("Authored deployment repair: %d failure(s)" % failures)
	quit(1 if failures else 0)
