extends SceneTree

const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const Compiler = preload("res://systems/generation/authored_scene_map_compiler.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func definition_for(scene_root: Node3D):
	var scene := PackedScene.new()
	check(scene.pack(scene_root) == OK, "Authored test scene packs")
	return AuthoredParcelDefinition.new(Catalog.INDUSTRIAL_OFFICE_PARKING_A, "Two-level population fixture", Catalog.URBAN_FRONTAGE, 1, Vector2i(32, 32), scene)

func _run() -> void:
	var source = Catalog.get_definition(Catalog.INDUSTRIAL_OFFICE_PARKING_A)
	var scene_root: Node3D = source.instantiate()
	var deck := Node3D.new()
	deck.name = "ParkingDeck"
	deck.set_meta("deck_local_rect", Rect2i(2, 4, 28, 8))
	deck.set_meta("deck_level", 4)
	deck.set_meta("population_surface_id", &"parking_deck")
	var column := Node3D.new()
	column.name = "Column"
	column.position = Vector3(9, 2, 9)
	column.set_meta("solid_size", Vector3(0.6, 4, 0.6))
	scene_root.add_child(column)
	column.owner = scene_root
	var approach := Node.new()
	approach.name = "Approach"
	approach.set_meta("ladder_local_bottom", Vector3i(3, 0, 3))
	approach.set_meta("ladder_local_top", Vector3i(3, 4, 4))
	scene_root.add_child(approach)
	approach.owner = scene_root
	# The deck follows its occupants in the scene tree.
	scene_root.add_child(deck)
	deck.owner = scene_root
	var upper := scene_root.get_node("PopulationRegions/ParkingBays").duplicate()
	upper.name = "UpperBays"
	upper.set_meta("population_region_id", &"upper_parking")
	upper.set_meta("population_surface_id", &"parking_deck")
	scene_root.get_node("PopulationRegions").add_child(upper)
	upper.owner = scene_root
	var car := scene_root.get_node("SedanWest") as Node3D
	car.position.y = 4
	car.set_meta("population_surface_id", &"parking_deck")
	car.set_meta("population_region_id", &"upper_parking")
	var definition = definition_for(scene_root)
	check(definition.validate().is_empty(), "Overlapping ground and upper regions resolve distinct authored surfaces: %s" % definition.validate())
	for turn in 4:
		var instance: Node3D = definition.instantiate()
		instance.transform = ParcelTransform.scene_transform(Vector2i(32, 32), Vector3i.ZERO, turn, Vector2i(32, 32))
		var data := FlatMapGenerator.generate(32, 32, 1.0, 42)
		Compiler.compile(instance, data, 1.0)
		var lower := ParcelTransform.cell(Vector3i(6, 0, 8), Vector2i(32, 32), Vector3i.ZERO, turn)
		var top := lower + Vector3i(0, 4, 0)
		check(data.get_cell(lower).walkable and data.get_cell(lower).can_stop, "rotation %d upper car leaves the ground below open" % turn)
		check(not data.get_cell(top).walkable and not data.get_cell(top).can_stop, "rotation %d imported car blocks its actual deck cells" % turn)
		check(is_equal_approx(data.get_cell(top).cover_height, 1.8), "rotation %d cover height is relative to the occupied floor" % turn)
		var support := ParcelTransform.cell(Vector3i(9, 0, 9), Vector2i(32, 32), Vector3i.ZERO, turn)
		check(not data.get_cell(support).can_stop and data.get_cell(support + Vector3i(0, 4, 0)).can_stop, "rotation %d column blocks ground and supports an open deck" % turn)
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		var base := ParcelTransform.cell(Vector3i(3, 0, 3), Vector2i(32, 32), Vector3i.ZERO, turn)
		var landing := ParcelTransform.cell(Vector3i(3, 4, 4), Vector2i(32, 32), Vector3i.ZERO, turn)
		check(not graph.calculate_3d_path(base, landing).is_empty(), "rotation %d retains the ground-to-deck approach" % turn)
		instance.move_child(instance.get_node("ParkingDeck"), 0)
		var reordered := FlatMapGenerator.generate(32, 32, 1.0, 42)
		Compiler.compile(instance, reordered, 1.0)
		check(_same_tactical_cells(data, reordered), "rotation %d deck and occupant sibling order produces identical tactical cells" % turn)
		instance.free()
	car.position.y = 0
	check(definition_for(scene_root).validate().has("POPULATION_SOCKET_HEIGHT_MISMATCH: parking_west"), "Wrong physical floor rejects")
	car.position.y = 4
	car.set_meta("population_surface_id", &"ground")
	check(definition_for(scene_root).validate().has("POPULATION_SOCKET_SURFACE_MISMATCH: parking_west"), "Wrong surface ownership rejects")
	car.set_meta("population_surface_id", &"parking_deck")
	upper.set_meta("population_surface_id", &"missing")
	check(definition_for(scene_root).validate().has("UNKNOWN_POPULATION_SURFACE: upper_parking"), "Unknown surface rejects")
	scene_root.free()
	print("Population surfaces: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _same_tactical_cells(first: MapData, second: MapData) -> bool:
	if first.cells.size() != second.cells.size(): return false
	for position in first.cells:
		var a := first.get_cell(position)
		var b := second.get_cell(position)
		if b == null or a.can_stop != b.can_stop or a.walkable != b.walkable or a.cover_height != b.cover_height or a.blocks_line_of_sight != b.blocks_line_of_sight:
			return false
	return true
