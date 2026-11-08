extends RefCounted
## Compact maps reuse the same plot resolver and compiler as the other families.

const Resolver := preload("res://systems/generation/refinery_plot_resolver.gd")
const SharedLayout := preload("res://systems/generation/refinery_family_layout.gd")
const Parcels := preload("res://systems/generation/authored_parcel_catalog.gd")
const DEPOT_SOURCE := "authored_service_depot"
const RANGE_SOURCE := "authored_tactical_test_range"
const DEPOT_SIZE := Vector2i(40, 40)
const RANGE_SIZE := Vector2i(32, 32)

class DepotPlots:
	const EAST_WEST := &"depot_loading_crossing"
	const NORTH_SOUTH := &"depot_service_spine"
	const CrossingScene := preload("res://art/environments/authored/plots/depot_loading_crossing.tscn")
	const SpineScene := preload("res://art/environments/authored/plots/depot_service_spine.tscn")

	static func choose(map_seed: int) -> Dictionary:
		return get_definition(EAST_WEST if posmod(map_seed, 2) == 0 else NORTH_SOUTH)

	static func get_definition(id: StringName) -> Dictionary:
		match id:
			EAST_WEST:
				return {"plot_id": id, "revision": 1, "map_size": DEPOT_SIZE, "scene": CrossingScene,
					"road_rects": [Rect2i(0, 32, 40, 5)],
					"circulation_rects": [Rect2i(19, 0, 3, 32)],
					"slots": [
						_slot(&"loading", Parcels.LOADING_SERVICE, Vector2i(16, 32), Vector3i(3, 0, 0), 0, Vector3i(9, 0, 31), Vector2i.DOWN, 4),
						_slot(&"process", Parcels.PROCESS, Vector2i(16, 16), Vector3i(22, 0, 16), 0, Vector3i(29, 0, 31), Vector2i.DOWN, 2),
						_slot(&"storage", Parcels.STORAGE, Vector2i(16, 16), Vector3i(22, 0, 0), 1, Vector3i(22, 0, 6), Vector2i.LEFT, 4),
					]}
			NORTH_SOUTH:
				return {"plot_id": id, "revision": 1, "map_size": DEPOT_SIZE, "scene": SpineScene,
					"road_rects": [Rect2i(0, 0, 5, 40)],
					"circulation_rects": [Rect2i(5, 19, 32, 4)],
					"slots": [
						_slot(&"loading", Parcels.LOADING_SERVICE, Vector2i(16, 32), Vector3i(5, 0, 3), 1, Vector3i(5, 0, 9), Vector2i.LEFT, 4),
						_slot(&"storage", Parcels.STORAGE, Vector2i(16, 16), Vector3i(5, 0, 23), 1, Vector3i(5, 0, 29), Vector2i.LEFT, 4),
						_slot(&"process", Parcels.PROCESS, Vector2i(16, 16), Vector3i(21, 0, 23), 2, Vector3i(29, 0, 23), Vector2i.UP, 2),
					]}
		return {}

	static func _slot(id: StringName, role: StringName, size: Vector2i, origin: Vector3i, rotation: int, access: Vector3i, outward: Vector2i, width: int) -> Dictionary:
		return {"slot_id": id, "role": role, "size": size, "origin": origin, "rotation": rotation,
			"required_interface": {"kind": &"service", "cell": access, "outward": outward, "width": width}}

class RangePlot:
	const SITE := &"tactical_test_range"
	const Surroundings := preload("res://art/environments/authored/plots/tactical_test_range_site.tscn")

	static func choose(_map_seed: int) -> Dictionary:
		return get_definition(SITE)

	static func get_definition(id: StringName) -> Dictionary:
		if id != SITE:
			return {}
		return {"plot_id": SITE, "revision": 1, "map_size": RANGE_SIZE, "scene": Surroundings, "slots": [{
			"slot_id": &"range", "role": Parcels.TACTICAL_RANGE, "size": RANGE_SIZE,
			"origin": Vector3i.ZERO, "rotation": 0, "required_interface": {
				"kind": &"range_entry", "cell": Vector3i(12, 0, 31), "outward": Vector2i.DOWN, "width": 8, "external": true,
			},
		}]}

static func generate(source_kind: String, map_seed: int, cell_size: float, requested: Dictionary) -> MapData:
	var plots = RangePlot if source_kind == RANGE_SOURCE else DepotPlots
	var enabled := bool(requested.get("population_enabled", source_kind != RANGE_SOURCE))
	var resolved := Resolver.resolve(map_seed, enabled, requested, plots)
	return SharedLayout.compile_resolved(resolved, map_seed, cell_size, source_kind, 1)

static func present(data: MapData, parent: Node3D, cell_size: float) -> bool:
	var plots = RangePlot if data.source_kind == RANGE_SOURCE else DepotPlots
	var manifest := data.content_manifest
	var checked := Resolver.resolve(data.generation_seed, bool(manifest.get("population_enabled", false)), manifest, plots)
	if not Resolver.is_valid(checked) or checked.placements != manifest.get("placements", []):
		return false
	var plot: Dictionary = plots.get_definition(manifest.plot_id)
	return SharedLayout.present_resolved(data, parent, cell_size, plot.scene)
