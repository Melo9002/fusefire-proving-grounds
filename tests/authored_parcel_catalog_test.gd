extends SceneTree

const Catalog = preload("res://systems/generation/authored_parcel_catalog.gd")
const Compiler = preload("res://systems/generation/authored_scene_map_compiler.gd")
const PopulationRegion = preload("res://systems/generation/parcel_population_region.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for parcel in Catalog.all():
		check(parcel.validate().is_empty(), "%s contract validates: %s" % [parcel.parcel_id, parcel.validate()])
		for turn in parcel.allowed_rotations():
			_check_compilation(parcel, turn)
	var parcels := Catalog.candidates(Catalog.LOADING_SERVICE, Vector2i(16, 32))
	check(parcels.size() == 2, "Loading/service role has two interchangeable 16x32 variants")
	for parcel in parcels:
		check(parcel.allowed_rotations().size() == 4, "%s explicitly supports four quarter-turns" % parcel.parcel_id)
		var regions = parcel.population_regions()
		check(regions.size() == 2, "%s authors depot-container and loading-vehicle population regions" % parcel.parcel_id)
		check(regions[0].region_id == &"depot_containers" and regions[1].region_id == &"loading_vehicles", "%s population identities are stable and deterministic" % parcel.parcel_id)
		for region in regions:
			check(region.validate(parcel.size).is_empty(), "%s region %s stays inside its parcel and has a curated allow-list" % [parcel.parcel_id, region.region_id])
	var first = Catalog.choose(Catalog.LOADING_SERVICE, Vector2i(16, 32), 100)
	var repeated = Catalog.choose(Catalog.LOADING_SERVICE, Vector2i(16, 32), 100)
	var alternate = Catalog.choose(Catalog.LOADING_SERVICE, Vector2i(16, 32), 101)
	check(first != null and first.parcel_id == repeated.parcel_id, "Same seed resolves the same registered parcel")
	check(alternate != null and alternate.parcel_id != first.parcel_id, "Adjacent pilot seeds exercise both registered variants")
	check(parcels[0].asset_ids() != parcels[1].asset_ids(), "Variants use genuinely different imported content")
	var connection = parcels[0].connection()
	var alternate_connection = parcels[1].connection()
	check(connection.kind == alternate_connection.kind and connection.cell == alternate_connection.cell and connection.outward == alternate_connection.outward and connection.width == alternate_connection.width, "Interchangeable variants expose the same measured service interface")
	check(Catalog.candidates(Catalog.PROCESS, Vector2i(16, 16)).size() == 1, "Process role has one supported 16x16 parcel")
	check(Catalog.candidates(Catalog.STORAGE, Vector2i(16, 16)).size() == 1, "Storage role has one supported 16x16 parcel")
	var galleries := Catalog.candidates(Catalog.ELEVATED_PROCESS, Vector2i(16, 32))
	check(galleries.size() == 1, "Catalog contains one dedicated 16x32 elevated maintenance parcel")
	var gallery = galleries[0]
	for turn in 4:
		var map_size := Vector2i(64, 64)
		var origin := Vector3i(16, 0, 16)
		var data := FlatMapGenerator.generate(map_size.x, map_size.y, 1.0, 810 + turn)
		var root: Node3D = gallery.instantiate()
		root.transform = ParcelTransform.scene_transform(gallery.size, origin, turn, map_size)
		Compiler.compile(root, data, 1.0)
		var bottom := ParcelTransform.cell(Vector3i(7, 0, 7), gallery.size, origin, turn)
		var top := ParcelTransform.cell(Vector3i(7, 4, 8), gallery.size, origin, turn)
		check(data.traversal_links.any(func(link): return link.from_cell == bottom and link.to_cell == top), "maintenance gallery rotation %d preserves ladder access" % turn)
		var graph := Pathfinder.new()
		MapGraphBuilder.build(data, graph)
		var far_deck := ParcelTransform.cell(Vector3i(8, 4, 23), gallery.size, origin, turn)
		check(not graph.calculate_3d_path(bottom, far_deck).is_empty(), "maintenance gallery rotation %d connects ground access to the complete elevated route" % turn)
		root.free()
	var urban_frontages := Catalog.candidates(Catalog.URBAN_FRONTAGE, Vector2i(32, 32))
	check(urban_frontages.size() == 1, "Catalog contains one bounded 32x32 urban-frontage proof")
	var frontage = urban_frontages[0]
	check(frontage.connection().kind == &"street_frontage" and frontage.connection().outward == Vector2i(0, -1) and frontage.connection().width == 8, "Urban parcel authors a measured street-facing frontage instead of inferring adjacency")
	var parking_regions = frontage.population_regions()
	check(parking_regions.size() == 1 and parking_regions[0].region_id == &"visitor_parking" and parking_regions[0].role == &"parked_vehicle", "Urban parcel owns a semantic visitor-parking population region")
	check(parking_regions[0].allowed_asset_ids == PackedStringArray(["car_kit/sedan", "car_kit/suv", "car_kit/taxi"]), "Parking population uses a curated vehicle allow-list")
	var urban_root: Node3D = frontage.instantiate()
	var urban_assets: PackedStringArray = frontage.asset_ids(urban_root)
	check(urban_assets.has("city_kit_industrial/building-a"), "Urban frontage uses a reviewed complete imported building shell")
	frontage.apply_population(urban_root, [])
	check(frontage.population_sockets(urban_root).is_empty() and frontage.asset_ids(urban_root).has("city_kit_industrial/building-a"), "Population-off removes parked cars without removing the complete fixed frontage")
	urban_root.free()
	var invalid_region = PopulationRegion.new()
	invalid_region.region_id = &"bad"
	invalid_region.role = &"shipping_container"
	invalid_region.local_rect = Rect2i(15, 30, 2, 3)
	invalid_region.allowed_asset_ids = PackedStringArray(["city_kit_industrial/shipping-container-a"])
	invalid_region.max_count = 1
	check(invalid_region.validate(Vector2i(16, 32)) == "POPULATION_REGION_OUT_OF_BOUNDS", "Population regions cannot escape their owning parcel")
	invalid_region.local_rect = Rect2i(1, 1, 2, 3)
	invalid_region.allowed_asset_ids = PackedStringArray()
	check(invalid_region.validate(Vector2i(16, 32)) == "EMPTY_POPULATION_ALLOW_LIST", "Population regions require curated eligible content")
	print("Authored parcel catalog: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_compilation(parcel, turn: int) -> void:
	var map_size := Vector2i(48, 48)
	var rotated_size := ParcelTransform.rotated_size(parcel.size, turn)
	var origin := Vector3i((map_size.x - rotated_size.x) / 2, 0, (map_size.y - rotated_size.y) / 2)
	var data := FlatMapGenerator.generate(map_size.x, map_size.y, 1.0, 700 + turn)
	var root: Node3D = parcel.instantiate()
	root.transform = ParcelTransform.scene_transform(parcel.size, origin, turn, map_size)
	Compiler.compile(root, data, 1.0)
	root.free()
	var graph := Pathfinder.new()
	MapGraphBuilder.build(data, graph)
	var validation := MapValidator.validate(data, graph)
	check(validation.is_valid(), "%s rotation %d compiles to valid tactical data: %s" % [parcel.parcel_id, turn, validation.describe()])
	var connection = parcel.connection()
	for offset in connection.width:
		var local_cell: Vector3i = connection.cell + Vector3i(offset if connection.outward.y != 0 else 0, 0, offset if connection.outward.x != 0 else 0)
		var world_cell := ParcelTransform.cell(local_cell, parcel.size, origin, turn)
		check(data.get_cell(world_cell) != null and data.get_cell(world_cell).walkable, "%s rotation %d keeps access interface cell %s open" % [parcel.parcel_id, turn, world_cell])
