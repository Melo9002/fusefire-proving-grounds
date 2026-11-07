class_name BattlefieldCatalog
extends RefCounted
## Stable identity boundary for every selectable battlefield. Legacy boolean
## fields remain readable in BattleConfiguration, but new code resolves here.

const GENERATED_COVER := &"generated_cover"
const REFINERY := &"legacy_refinery"
const INDUSTRIAL_WAREHOUSE := &"industrial_warehouse"
const REFINERY_2 := &"refinery_2"
const LOADING_YARD := &"loading_yard"
const REFINERY_FAMILY := &"refinery_family"
const URBAN_FAMILY := &"urban_family"
const PARKING_GARAGE := &"parking_garage"
const ParkingGarageLayoutData = preload("res://systems/generation/parking_garage_layout.gd")
const UrbanFamilyLayoutData = preload("res://systems/generation/urban_family_layout.gd")
const Refinery2LayoutData = preload("res://systems/generation/refinery_2_layout.gd")
const LoadingYardLayoutData = preload("res://systems/generation/loading_yard_layout.gd")
const RefineryFamilyLayoutData = preload("res://systems/generation/refinery_family_layout.gd")

const DEFINITIONS := {
	PARKING_GARAGE: {"label": "Authored proof — Two-level Parking Garage", "source_kind": ParkingGarageLayoutData.SOURCE_KIND, "fixed_size": ParkingGarageLayoutData.MAP_SIZE},
	URBAN_FAMILY: {"label": "Generated authored parcels — Urban family (preview)", "source_kind": "authored_urban_family", "fixed_size": Vector2i(64, 64)},
	GENERATED_COVER: {"label": "Generated cover", "source_kind": "generated_cover", "fixed_size": Vector2i.ZERO},
	REFINERY: {"label": "Special — Refinery", "source_kind": "generated_refinery", "fixed_size": Vector2i(40, 30)},
	INDUSTRIAL_WAREHOUSE: {"label": "Special — Industrial Warehouse", "source_kind": "generated_industrial_warehouse", "fixed_size": Vector2i(40, 30)},
	REFINERY_2: {"label": "Authored — Refinery 2.0", "source_kind": "authored_refinery_2", "fixed_size": Vector2i(96, 80)},
	LOADING_YARD: {"label": "Authored proof — Loading Yard", "source_kind": "authored_loading_yard", "fixed_size": Vector2i(40, 48)},
	REFINERY_FAMILY: {"label": "Generated authored parcels — Refinery family", "source_kind": "authored_refinery_family", "fixed_size": Vector2i(64, 64)},
}

static func has(id: StringName) -> bool:
	return DEFINITIONS.has(id)

static func definition(id: StringName) -> Dictionary:
	return DEFINITIONS.get(id, {}).duplicate(true)

static func label(id: StringName) -> String:
	return definition(id).get("label", String(id))

static func map_size(id: StringName, requested: Vector2i) -> Vector2i:
	var fixed: Vector2i = definition(id).get("fixed_size", Vector2i.ZERO)
	if fixed != Vector2i.ZERO:
		return fixed
	return requested if requested in FlatMapGenerator.MAP_SIZES else FlatMapGenerator.MAP_SIZES[1]

static func resolve_legacy_id(refinery: bool, warehouse: bool, refinery_2: bool, loading_yard: bool) -> StringName:
	if loading_yard: return LOADING_YARD
	if refinery_2: return REFINERY_2
	if warehouse: return INDUSTRIAL_WAREHOUSE
	if refinery: return REFINERY
	return GENERATED_COVER

static func generate(id: StringName, requested_size: Vector2i, map_seed: int, cell_size: float, requested_manifest: Dictionary = {}) -> MapData:
	var size := map_size(id, requested_size)
	match id:
		PARKING_GARAGE:
			return ParkingGarageLayoutData.generate(map_seed, cell_size, requested_manifest, bool(requested_manifest.get("population_enabled", true)))
		URBAN_FAMILY:
			return UrbanFamilyLayoutData.generate(map_seed, cell_size, requested_manifest, bool(requested_manifest.get("population_enabled", true)))
		REFINERY:
			return FlatMapGenerator.generate_with_cover(size.x, size.y, cell_size, map_seed, 5, true, false)
		INDUSTRIAL_WAREHOUSE:
			return FlatMapGenerator.generate_with_cover(size.x, size.y, cell_size, map_seed, 5, false, true)
		REFINERY_2:
			return Refinery2LayoutData.generate(map_seed, cell_size)
		LOADING_YARD:
			return LoadingYardLayoutData.generate(map_seed, cell_size)
		REFINERY_FAMILY:
			return RefineryFamilyLayoutData.generate(map_seed, cell_size, requested_manifest, bool(requested_manifest.get("population_enabled", true)))
		_:
			return FlatMapGenerator.generate_with_cover(size.x, size.y, cell_size, map_seed)

## Returns true when this catalog supplied the complete special presentation.
static func present_special(data: MapData, parent: Node3D, cell_size: float) -> bool:
	match data.source_kind:
		ParkingGarageLayoutData.SOURCE_KIND: return ParkingGarageLayoutData.present(data, parent, cell_size)
		"authored_urban_family": return UrbanFamilyLayoutData.present(data, parent, cell_size)
		"authored_loading_yard": LoadingYardLayoutData.present(parent, cell_size)
		"authored_refinery_2": Refinery2LayoutData.present(parent, cell_size)
		"authored_refinery_family": return RefineryFamilyLayoutData.present(data, parent, cell_size)
		_: return false
	return true
