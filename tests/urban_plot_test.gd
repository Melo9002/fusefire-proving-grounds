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
	var plot := PlotCatalog.definition()
	var plot_root: Node3D = plot.scene.instantiate()
	root.add_child(plot_root)
	check(StringName(plot_root.get_meta("plot_id", &"")) == plot.plot_id and int(plot_root.get_meta("revision", 0)) == plot.revision, "Urban plot scene identity matches its catalog contract")
	check(plot.road_rects == [Rect2i(0, 27, 64, 5)], "Urban proof owns one fixed five-cell east-west street")
	var slot_rects: Array[Rect2i] = []
	var data := FlatMapGenerator.generate(64, 64, 1.0, 411)
	for slot: Dictionary in plot.slots:
		var candidates := ParcelCatalog.candidates(slot.role, slot.size)
		check(not candidates.is_empty(), "%s has registered content" % slot.slot_id)
		if candidates.is_empty():
			continue
		var parcel = candidates[0]
		check(SlotContract.validate(slot, parcel).is_empty(), "%s parcel satisfies exact role, size, rotation and interface" % slot.slot_id)
		var rotated_size := ParcelTransform.rotated_size(parcel.size, slot.rotation)
		var slot_rect := Rect2i(slot.origin.x, slot.origin.z, rotated_size.x, rotated_size.y)
		check(Rect2i(Vector2i.ZERO, plot.map_size).encloses(slot_rect), "%s remains inside the playable plot" % slot.slot_id)
		for road_rect: Rect2i in plot.road_rects:
			check(not road_rect.intersects(slot_rect), "%s does not overlap the street" % slot.slot_id)
		var required: Dictionary = slot.required_interface
		var adjacent := Vector2i(required.cell.x + required.outward.x, required.cell.z + required.outward.y)
		check(plot.road_rects.any(func(rect: Rect2i): return rect.has_point(adjacent)), "%s interface meets an actual adjacent road cell" % slot.slot_id)
		for existing: Rect2i in slot_rects:
			check(not existing.intersects(slot_rect), "%s does not overlap another parcel" % slot.slot_id)
		slot_rects.append(slot_rect)
		var parcel_root: Node3D = parcel.instantiate()
		parcel_root.transform = ParcelTransform.scene_transform(parcel.size, slot.origin, slot.rotation, plot.map_size)
		Compiler.compile(parcel_root, data, 1.0)
		parcel_root.free()
		var access: Vector3i = required.cell
		check(data.get_cell(access) != null and data.get_cell(access).walkable, "%s keeps its road interface tactically open" % slot.slot_id)
	var lights := plot_root.find_children("*", "Node3D", true, false).filter(func(node): return String(node.get_meta("asset_id", "")) == "city_kit_roads/light-curved")
	check(lights.size() == 4, "Urban plot owns four deliberate streetlights")
	for light: Node3D in lights:
		var head_direction := light.global_basis * Vector3(0, 0, -1)
		var road_direction := Vector3(0, 0, -2.5 - light.global_position.z).normalized()
		check(head_direction.dot(road_direction) > 0.95, "%s lamp head faces the street" % light.name)
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var validation := MapValidator.validate(data, graph)
	check(validation.is_valid(), "Urban parcel composition compiles to valid tactical data: %s" % validation.describe())
	plot_root.free()
	print("Urban plot: %d failure(s)" % failures)
	quit(1 if failures else 0)
