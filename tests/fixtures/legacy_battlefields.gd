extends RefCounted
## Explicit compatibility adapter for retained mechanics/replay fixtures only.
## Generation2 never imports or calls this file.
const Garage = preload("res://tests/fixtures/legacy_generation/parking_garage_layout.gd")

static func map_size(requested: Vector2i) -> Vector2i:
	return requested if requested in FlatMapGenerator.MAP_SIZES else FlatMapGenerator.MAP_SIZES[1]

static func generate(id: StringName, size: Vector2i, map_seed: int, cell_size: float, manifest: Dictionary) -> MapData:
	if id == &"parking_garage":
		return Garage.generate(map_seed, cell_size, manifest, bool(manifest.get("population_enabled", true)))
	return FlatMapGenerator.generate_with_cover(size.x, size.y, cell_size, map_seed, 5, id == &"legacy_refinery", id == &"industrial_warehouse")

static func present_garage(data: MapData, parent: Node3D, cell_size: float, world_environment: WorldEnvironment = null) -> bool:
	return Garage.present(data, parent, cell_size, world_environment)

static func present(data: MapData, parent: Node3D, cell_size: float) -> void:
	GeneratedTerrainPresenter.build(data, parent, cell_size)
