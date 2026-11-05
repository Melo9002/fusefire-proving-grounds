extends SceneTree

const PlotCatalog = preload("res://systems/generation/urban_plot_catalog.gd")
const ParcelCatalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const SlotContract = preload("res://systems/generation/parcel_slot_contract.gd")
const Compiler = preload("res://systems/generation/authored_scene_map_compiler.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var plot := PlotCatalog.definition(PlotCatalog.COURTYARD_B)
	check(not plot.is_empty(), "Second urban plot is registered")
	var plot_root: Node3D = plot.scene.instantiate()
	root.add_child(plot_root)
	check(StringName(plot_root.get_meta("plot_id", &"")) == plot.plot_id, "Courtyard scene identity matches its catalog contract")
	check(plot.road_rects.is_empty(), "Courtyard plot honestly owns no city-road network")
	check(plot.slots.size() == 5, "Courtyard composition has a center, two flanks and two north-edge parcels")
	var data := FlatMapGenerator.generate(plot.map_size.x, plot.map_size.y, 1.0, 7331)
	var occupied: Array[Rect2i] = []
	for slot: Dictionary in plot.slots:
		var candidates := ParcelCatalog.candidates(slot.role, slot.size)
		check(not candidates.is_empty(), "%s has registered authored content" % slot.slot_id)
		if candidates.is_empty():
			continue
		var parcel = candidates[0]
		check(SlotContract.validate(slot, parcel).is_empty(), "%s satisfies its exact interface: %s" % [slot.slot_id, SlotContract.validate(slot, parcel)])
		var extent := ParcelTransform.rotated_size(parcel.size, slot.rotation)
		var parcel_rect := Rect2i(slot.origin.x, slot.origin.z, extent.x, extent.y)
		check(Rect2i(Vector2i.ZERO, plot.map_size).encloses(parcel_rect), "%s remains inside the tactical boundary" % slot.slot_id)
		for existing in occupied:
			check(not existing.intersects(parcel_rect), "%s does not overlap another parcel" % slot.slot_id)
		occupied.append(parcel_rect)
		var parcel_root: Node3D = parcel.instantiate()
		parcel_root.transform = ParcelTransform.scene_transform(parcel.size, slot.origin, slot.rotation, plot.map_size)
		Compiler.compile(parcel_root, data, 1.0)
		parcel_root.free()
		var interface: Dictionary = slot.required_interface
		check(data.get_cell(interface.cell) != null and data.get_cell(interface.cell).walkable, "%s preserves its authored interface" % slot.slot_id)
	var central := Rect2i(16, 16, 32, 32)
	for slot: Dictionary in plot.slots:
		if slot.slot_id == &"signal_courtyard":
			continue
		var interface: Dictionary = slot.required_interface
		var adjacent := Vector2i(interface.cell.x + interface.outward.x, interface.cell.z + interface.outward.y)
		check(central.has_point(adjacent), "%s opens into the real central courtyard rather than an inferred edge" % slot.slot_id)
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	check(not graph.calculate_3d_path(Vector3i(28, 0, 55), Vector3i(15, 0, 20)).is_empty(), "South deployment approach reaches the west side of the objective yard")
	check(not graph.calculate_3d_path(Vector3i(28, 0, 55), Vector3i(25, 0, 25)).is_empty(), "South deployment approach reaches the east cover lane")
	var validation := MapValidator.validate(data, graph)
	check(validation.is_valid(), "Courtyard composition compiles to valid tactical data: %s" % validation.describe())
	var galleries: Array = plot.slots.filter(func(slot): return slot.role == ParcelCatalog.URBAN_GALLERY)
	check(galleries.size() == 2 and galleries[0].rotation != galleries[1].rotation, "Mirrored gallery placements create two inward-facing elevated flanks")
	plot_root.free()
	print("Urban courtyard: %d failure(s)" % failures)
	quit(1 if failures else 0)
