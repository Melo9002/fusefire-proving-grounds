class_name ParkingGarageLayout
extends RefCounted

const Resolver = preload("res://systems/generation/refinery_plot_resolver.gd")
const SharedLayout = preload("res://systems/generation/refinery_family_layout.gd")
const Parcels = preload("res://systems/generation/authored_parcel_catalog.gd")
const Surroundings = preload("res://art/environments/authored/plots/parking_garage_site.tscn")
const SOURCE_KIND := "authored_parking_garage"
const MAP_SIZE := Vector2i(32, 32)
const SITE := &"service_garage"

static func choose(_map_seed: int) -> Dictionary:
	return get_definition(SITE)

static func get_definition(id: StringName) -> Dictionary:
	if id != SITE:
		return {}
	return {
		"plot_id": SITE,
		"revision": 1,
		"map_size": MAP_SIZE,
		"slots": [{
			"slot_id": &"garage",
			"role": Parcels.PARKING_GARAGE,
			"size": MAP_SIZE,
			"origin": Vector3i.ZERO,
			"rotation": 0,
			"required_interface": {"kind": &"garage_driveway", "width": 8, "cell": Vector3i(12, 0, 0), "outward": Vector2i(0, -1)},
		}],
	}

static func generate(map_seed: int, cell_size: float = 1.0, requested: Dictionary = {}, population_enabled: bool = true) -> MapData:
	var resolved := Resolver.resolve(map_seed, population_enabled, requested, ParkingGarageLayout)
	return SharedLayout.compile_resolved(resolved, map_seed, cell_size, SOURCE_KIND)

static func present(data: MapData, parent: Node3D, cell_size: float) -> bool:
	var manifest := data.content_manifest
	var checked := Resolver.resolve(data.generation_seed, bool(manifest.get("population_enabled", true)), manifest, ParkingGarageLayout)
	if not Resolver.is_valid(checked) or checked.placements != manifest.get("placements", []):
		return false
	return SharedLayout.present_resolved(data, parent, cell_size, Surroundings)
