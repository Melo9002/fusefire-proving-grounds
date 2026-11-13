extends SceneTree

const Contract = preload("res://systems/generation/parcel_slot_contract.gd")
const PlotCatalog = preload("res://systems/generation/refinery_plot_catalog.gd")
const Resolver = preload("res://systems/generation/refinery_plot_resolver.gd")
const Layout = preload("res://systems/generation/refinery_family_layout.gd")
const Site = preload("res://art/environments/authored/plots/refinery_site_a.tscn")
var failures := 0

class ShortRoadCatalog:
	static func choose(_map_seed: int) -> Dictionary:
		var plot := PlotCatalog.get_definition(PlotCatalog.SITE_A)
		plot.road_rects = [Rect2i(0, 24, 16, 5)]
		return plot

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var connection := ParcelConnection.new()
	connection.cell = Vector3i(4, 2, 0)
	connection.width = 3
	var expected := [
		[Vector3i(14, 3, 20), Vector3i(15, 3, 20), Vector3i(16, 3, 20)],
		[Vector3i(41, 3, 24), Vector3i(41, 3, 25), Vector3i(41, 3, 26)],
		[Vector3i(21, 3, 51), Vector3i(20, 3, 51), Vector3i(19, 3, 51)],
		[Vector3i(10, 3, 31), Vector3i(10, 3, 30), Vector3i(10, 3, 29)],
	]
	for turn in 4:
		var span := connection.world_span(Vector2i(16, 32), Vector3i(10, 1, 20), turn)
		_check(span == expected[turn], "Rectangular elevated rotation %d: expected %s, got %s" % [turn, expected[turn], span])

	var short := Resolver.resolve(16, true, {}, ShortRoadCatalog)
	_check(not Resolver.is_valid(short) and _has_failure(short.errors, "MISSING_INTERFACE_APPROACH", "process at (16, 0, 23)"), "Runtime rejects a road that meets the anchor but misses the next interface cell")
	var plot := PlotCatalog.get_definition(PlotCatalog.SITE_A)
	plot.slots[1].origin = plot.slots[0].origin
	_check(Contract.validate_plot_footprints(plot).get("code") == "OVERLAPPING_PLOT_SLOTS", "Runtime rejects parcel overlap before compiling")
	plot = PlotCatalog.get_definition(PlotCatalog.SITE_A)
	plot.slots[0].origin.z += 1
	_check(Contract.validate_plot_footprints(plot).get("code") == "SLOT_OVERLAPS_ROAD", "Runtime rejects a parcel crossing a reserved road")
	plot.slots[0].origin.x = -1
	_check(Contract.validate_plot_footprints(plot).get("code") == "SLOT_OUTSIDE_PLOT", "Runtime rejects a slot outside the plot")

	var map := FlatMapGenerator.generate(16, 16, 1.0, 16)
	var span: Array[Vector3i] = [Vector3i(4, 3, 8), Vector3i(5, 3, 8), Vector3i(6, 3, 8)]
	for inside in span:
		_add_deck_cell(map, inside)
		_add_deck_cell(map, inside + Vector3i.FORWARD)
	_check(Contract.validate_compiled_span(map, "example/elevated", span, Vector2i.UP).is_empty(), "A complete elevated span passes")
	var graph := Pathfinder.new()
	MapGraphBuilder.build(map, graph)
	_check(graph.calculate_3d_path(Vector3i(5, 3, 8), Vector3i(5, 3, 7)).size() == 2, "The supported elevated seam has a direct tactical crossing")
	var blocked := map.get_cell(Vector3i(6, 3, 8))
	blocked.can_stop = false
	var error := Contract.validate_compiled_span(map, "example/elevated", span, Vector2i.UP)
	_check(error.get("code") == "BLOCKED_PARCEL_INTERFACE" and "(6, 3, 8)" in error.get("detail", ""), "A non-anchor low-cover cell fails the promised width")
	blocked.can_stop = true
	map.get_cell(Vector3i(5, 3, 7)).walkable = false
	error = Contract.validate_compiled_span(map, "example/elevated", span, Vector2i.UP)
	_check(error.get("code") == "BLOCKED_INTERFACE_APPROACH" and "(5, 3, 7)" in error.get("detail", ""), "A blocked adjoining cell fails on the plot side")
	map.get_cell(Vector3i(5, 3, 7)).walkable = true
	map.cells.erase(Vector3i(5, 3, 7))
	_check(Contract.validate_compiled_span(map, "example/elevated", span, Vector2i.UP).get("code") == "BLOCKED_INTERFACE_APPROACH", "Walkable ground cannot substitute for a missing elevated approach")

	# Bypass the footprint gate only in this fixture to check that a real
	# imported parcel solid still triggers the independent compilation gate.
	var conflicting := Resolver.resolve(16)
	for placement: Dictionary in conflicting.placements:
		if placement.slot_id == &"storage":
			placement.origin = Vector3i(21, 0, 17)
	var compiled := Layout.compile_resolved(conflicting, 16, 1.0, Layout.SOURCE_KIND)
	_check(_has_failure(compiled.generation_errors, "BLOCKED_PARCEL_INTERFACE", "refinery_site_a/loading") or _has_failure(compiled.generation_errors, "BLOCKED_INTERFACE_APPROACH", "refinery_site_a/loading"), "The compile boundary rejects a real obstruction on the loading seam: %s" % [compiled.generation_errors])
	var parent := Node3D.new()
	_check(not Layout.present_resolved(compiled, parent, 1.0, Site) and parent.get_child_count() == 0, "A failed compile cannot present a partial plot")
	parent.free()
	print("Parcel interface validation: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _add_deck_cell(map: MapData, position: Vector3i) -> void:
	var ground := map.get_cell(Vector3i(position.x, 0, position.z))
	map.add_cell(MapCellData.new(position, ground.world_position + Vector3.UP * position.y))

func _has_failure(errors: Array, code: String, detail: String) -> bool:
	return errors.any(func(error): return error.code == code and detail in error.detail)

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
