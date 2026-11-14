class_name BattlefieldCatalog
extends RefCounted
## Service Depot is the only normal menu map. Other supported IDs are internal
## mechanics fixtures. Retired identities reject explicitly. Legacy boolean
## fields remain readable in BattleConfiguration, but new code resolves here.

const GENERATED_COVER := &"generated_cover"
const REFINERY := &"legacy_refinery"
const INDUSTRIAL_WAREHOUSE := &"industrial_warehouse"
const REFINERY_2 := &"refinery_2"
const LOADING_YARD := &"loading_yard"
const REFINERY_FAMILY := &"refinery_family"
const URBAN_FAMILY := &"urban_family"
const PARKING_GARAGE := &"parking_garage"
const SERVICE_DEPOT := &"service_depot"
const TACTICAL_TEST_RANGE := &"tactical_test_range"
const CurrentGenerator = preload("res://systems/generation2/generator.gd")


const DEFINITIONS := {
	SERVICE_DEPOT: {"label": "Service Depot", "source_kind": CurrentGenerator.DEPOT_SOURCE, "fixed_size": CurrentGenerator.DEPOT_SIZE},
	TACTICAL_TEST_RANGE: {"label": "Tactical Test Range", "source_kind": CurrentGenerator.RANGE_SOURCE, "fixed_size": CurrentGenerator.RANGE_SIZE},
	PARKING_GARAGE: {"label": "Authored proof — Two-level Parking Garage", "source_kind": "authored_parking_garage", "fixed_size": Vector2i(32, 32)},
	GENERATED_COVER: {"label": "Generated cover", "source_kind": "generated_cover", "fixed_size": Vector2i.ZERO},
	REFINERY: {"label": "Special — Refinery", "source_kind": "generated_refinery", "fixed_size": Vector2i(40, 30)},
	INDUSTRIAL_WAREHOUSE: {"label": "Special — Industrial Warehouse", "source_kind": "generated_industrial_warehouse", "fixed_size": Vector2i(40, 30)},
}

# Internal battle fixtures retain their explicit IDs for the mechanics tests.
const PLAYABLE := [SERVICE_DEPOT]

static func uses_population(id: StringName) -> bool:
	return id in [SERVICE_DEPOT, TACTICAL_TEST_RANGE, PARKING_GARAGE]

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
	return _fixtures().map_size(requested) if id in [GENERATED_COVER, REFINERY, INDUSTRIAL_WAREHOUSE] else requested

static func resolve_legacy_id(refinery: bool, warehouse: bool, refinery_2: bool, loading_yard: bool) -> StringName:
	if loading_yard: return LOADING_YARD
	if refinery_2: return REFINERY_2
	if warehouse: return INDUSTRIAL_WAREHOUSE
	if refinery: return REFINERY
	return GENERATED_COVER

static func generate(id: StringName, requested_size: Vector2i, map_seed: int, cell_size: float, requested_manifest: Dictionary = {}) -> MapData:
	var size := map_size(id, requested_size)
	match id:
		SERVICE_DEPOT:
			return CurrentGenerator.generate(CurrentGenerator.DEPOT_SOURCE, map_seed, cell_size, requested_manifest)
		TACTICAL_TEST_RANGE:
			return CurrentGenerator.generate(CurrentGenerator.RANGE_SOURCE, map_seed, cell_size, requested_manifest)
		PARKING_GARAGE, REFINERY, INDUSTRIAL_WAREHOUSE, GENERATED_COVER:
			return _fixtures().generate(id, size, map_seed, cell_size, requested_manifest)
		_:
			var rejected := MapData.new()
			rejected.generation_errors.append({"code": "UNKNOWN_BATTLEFIELD", "detail": String(id)})
			return rejected

## Returns true when this catalog supplied the complete special presentation.
static func present_special(data: MapData, parent: Node3D, cell_size: float) -> bool:
	match data.source_kind:
		CurrentGenerator.DEPOT_SOURCE, CurrentGenerator.RANGE_SOURCE: return CurrentGenerator.present(data, parent, cell_size)
		"authored_parking_garage": return _fixtures().present_garage(data, parent, cell_size)
		_: return false

## Current maps bypass the old procedural renderer entirely.
static func present(data: MapData, parent: Node3D, cell_size: float) -> bool:
	if data.source_kind in [CurrentGenerator.DEPOT_SOURCE, CurrentGenerator.RANGE_SOURCE, "authored_parking_garage"]:
		return present_special(data, parent, cell_size)
	if data.source_kind in ["generated_cover", "generated_refinery", "generated_industrial_warehouse", "generated_flat"]:
		_fixtures().present(data, parent, cell_size)
		return true
	return false
static func _fixtures():
	return load("res://tests/fixtures/legacy_battlefields.gd")
