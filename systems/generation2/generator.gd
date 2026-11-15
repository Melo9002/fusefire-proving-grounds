class_name Generation2
extends RefCounted
## Current generator: MapData + exact content_manifest, and imported presentation.
## Never imports or invokes a legacy generator.

const Resolver := preload("res://systems/generation2/authored_plot_resolver.gd")
const SharedLayout := preload("res://systems/generation2/authored_battlefield_layout.gd")
const Parcels := preload("res://systems/generation2/authored_parcel_catalog.gd")
const ParcelTest := preload("res://systems/generation2/parcel_test_layout.gd")
const DEPOT_SOURCE := "authored_service_depot"
const FREIGHT_SOURCE := "authored_freight_yard"
const FLEET_SOURCE := "authored_fleet_station"
const FREIGHT_SIZE := Vector2i(40, 40)
const FLEET_SIZE := Vector2i(40, 40)
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

class FreightPlots:
	const WEST := &"freight_staging_west"
	const EAST := &"freight_staging_east"
	const Site = preload("res://art/environments/authored/plots/freight_yard_site.tscn")
	static func choose(map_seed: int) -> Dictionary:
		return get_definition(WEST if posmod(map_seed, 2) == 0 else EAST)
	static func get_definition(id: StringName) -> Dictionary:
		if id not in [WEST, EAST]: return {}
		return {"plot_id": id, "revision": 1, "map_size": FREIGHT_SIZE, "scene": Site,
			"road_rects": [Rect2i(0, 32, 40, 5)], "circulation_rects": [Rect2i(18, 0, 4, 32)],
			"slots": [
				_apron(&"west", Vector3i(2, 0, 0), Parcels.CONTAINER_STAGING if id == WEST else Parcels.FLEET_APRON),
				_apron(&"east", Vector3i(22, 0, 0), Parcels.FLEET_APRON if id == WEST else Parcels.CONTAINER_STAGING),
			]}
	static func _apron(id: StringName, origin: Vector3i, parcel: StringName) -> Dictionary:
		return {"slot_id": id, "role": Parcels.FREIGHT_APRON_ROLE, "size": Vector2i(16, 32), "origin": origin, "rotation": 0, "preferred_parcel_id": parcel,
			"required_interface": {"kind": &"service", "cell": origin + Vector3i(6, 0, 31), "outward": Vector2i.DOWN, "width": 4}}

class FleetPlots:
	const NORTH := &"fleet_station_north"
	const SOUTH := &"fleet_station_south"
	const NorthScene = preload("res://art/environments/authored/plots/fleet_station_north.tscn")
	const SouthScene = preload("res://art/environments/authored/plots/fleet_station_south.tscn")
	static func choose(map_seed: int) -> Dictionary:
		return get_definition(NORTH if posmod(map_seed, 2) == 0 else SOUTH)
	static func get_definition(id: StringName) -> Dictionary:
		if id not in [NORTH, SOUTH]: return {}
		var north := id == NORTH
		return {"plot_id": id, "revision": 1, "map_size": FLEET_SIZE, "scene": NorthScene if north else SouthScene,
			"road_rects": [Rect2i(0, 0, 40, 5) if north else Rect2i(0, 33, 40, 5)],
			"circulation_rects": [Rect2i(4, 5, 32, 1) if north else Rect2i(4, 32, 32, 1)],
			"slots": [{"slot_id": &"service_court", "role": Parcels.FLEET_COURT_ROLE, "size": Vector2i(32, 32), "preferred_parcel_id": Parcels.FLEET_COURT,
				"origin": Vector3i(4, 0, 6) if north else Vector3i(4, 0, 0), "rotation": 0 if north else 2,
				"required_interface": {"kind": &"street_frontage", "cell": Vector3i(16, 0, 6) if north else Vector3i(23, 0, 31), "outward": Vector2i.UP if north else Vector2i.DOWN, "width": 8}}]}

static func _plots_for(source_kind: String):
	match source_kind:
		DEPOT_SOURCE: return DepotPlots
		FREIGHT_SOURCE: return FreightPlots
		FLEET_SOURCE: return FleetPlots
		RANGE_SOURCE: return RangePlot
	return null

static func generate(source_kind: String, map_seed: int, cell_size: float, requested: Dictionary) -> MapData:
	if source_kind == ParcelTest.SOURCE: return ParcelTest.generate(map_seed, cell_size, requested)
	if _plots_for(source_kind) == null:
		var rejected := MapData.new()
		rejected.generation_errors.append({"code": "UNSUPPORTED_GENERATION2_SOURCE", "detail": source_kind})
		return rejected
	var plots = _plots_for(source_kind)
	var enabled := bool(requested.get("population_enabled", source_kind != RANGE_SOURCE))
	var resolved := Resolver.resolve(plots, map_seed, enabled, requested)
	return SharedLayout.compile_resolved(resolved, map_seed, cell_size, source_kind, 1)

static func present(data: MapData, parent: Node3D, cell_size: float, world_environment: WorldEnvironment = null) -> bool:
	if data.source_kind == ParcelTest.SOURCE: return ParcelTest.present(data, parent, cell_size, world_environment)
	if _plots_for(data.source_kind) == null: return false
	var plots = _plots_for(data.source_kind)
	var manifest := data.content_manifest
	var checked := Resolver.resolve(plots, data.generation_seed, bool(manifest.get("population_enabled", false)), manifest)
	if not Resolver.is_valid(checked) or checked.placements != manifest.get("placements", []):
		return false
	var plot: Dictionary = plots.get_definition(manifest.plot_id)
	return SharedLayout.present_resolved(data, parent, cell_size, plot.scene, world_environment)
