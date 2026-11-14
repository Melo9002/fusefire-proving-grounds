extends SceneTree
## Clearance must use the same current shapes as compilation, not archived envelopes.
const Catalog = preload("res://systems/generation2/authored_parcel_catalog.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	for id in [Catalog.LOADING_YARD_A, Catalog.LOADING_YARD_B]:
		var definition = Catalog.get_definition(id)
		var scene: Node3D = definition.instantiate()
		var warehouse := scene.get_node("Warehouse") as Node3D
		var obstacles: Array[AABB] = definition.fixed_population_obstacles(scene)
		var open_probe := warehouse.transform * Vector3(-4.8, 1.0, 5.5)
		check(not obstacles.any(func(bounds): return bounds.has_point(open_probe)), "%s clearance leaves the mesh-verified open side free" % id)
		var wall_probe := warehouse.transform * Vector3(0, 1, 0)
		check(obstacles.any(func(bounds): return bounds.has_point(wall_probe)), "%s warehouse body still reserves clearance" % id)
		var planter_probe := warehouse.transform * Vector3(-4.5, 0.25, -2.5)
		check(obstacles.any(func(bounds): return bounds.has_point(planter_probe)), "%s low planter remains an obstacle" % id)
		# Independently measured shell/planter union. Historical width/depth were
		# 10.281378 / 13.000001; the current union is 9.7 / 12 metres.
		var current_union := AABB(Vector3(-5.140629, 0, -6), Vector3(9.7, 7.33541, 12)) if id == Catalog.LOADING_YARD_A else AABB(Vector3(-5.13405, 0, -6), Vector3(9.7, 8.611458, 12))
		var expected := warehouse.transform * current_union
		var actual: AABB = definition._population_bounds(warehouse, warehouse.transform)
		check(actual.position.is_equal_approx(expected.position) and actual.size.is_equal_approx(expected.size), "%s population bounds exclude obsolete solids: expected %s, got %s" % [id, expected, actual])
		scene.free()
	print("Active shape clearance: %d failure(s)" % failures)
	quit(1 if failures else 0)
