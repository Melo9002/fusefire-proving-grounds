class_name BattlefieldCatalog
extends RefCounted
## The three normal sites and the selectable authored test range share Generation 2.
## Other supported IDs are internal mechanics fixtures. Retired identities reject explicitly. Legacy boolean
## fields are translated at compatibility inputs; current code uses one ID.

const GENERATED_COVER := &"generated_cover"
const REFINERY := &"legacy_refinery"
const INDUSTRIAL_WAREHOUSE := &"industrial_warehouse"
const REFINERY_2 := &"refinery_2"
const LOADING_YARD := &"loading_yard"
const REFINERY_FAMILY := &"refinery_family"
const URBAN_FAMILY := &"urban_family"
const PARKING_GARAGE := &"parking_garage"
const FREIGHT_YARD := &"freight_yard"
const FLEET_STATION := &"fleet_station"
const SERVICE_DEPOT := &"service_depot"
const TACTICAL_TEST_RANGE := &"tactical_test_range"
const INTERACTION_RANGE := &"interaction_range"
const CONTEXTUAL_BAY := &"contextual_firing_bay"
# Named rules variants preserve historical recordings for the ordinary sites.
const CONTEXTUAL_DEPOT := &"service_depot_contextual_v1"
const CONTEXTUAL_SHOWCASE := &"service_depot_contextual_showcase_v1"
const CONTEXTUAL_FREIGHT := &"freight_yard_contextual_v1"
const ContextualBay = preload("res://systems/generation/contextual_firing_bay.gd")
const PARCEL_TEST := &"parcel_editor_test"
const CurrentGenerator = preload("res://systems/generation2/generator.gd")


const DEFINITIONS := {
	CONTEXTUAL_SHOWCASE: {"label": "Depot Crossfire", "source_kind": CurrentGenerator.DEPOT_SOURCE, "fixed_size": CurrentGenerator.DEPOT_SIZE},
	CONTEXTUAL_DEPOT: {"label": "Service Depot — Contextual Firing", "source_kind": CurrentGenerator.DEPOT_SOURCE, "fixed_size": CurrentGenerator.DEPOT_SIZE},
	CONTEXTUAL_FREIGHT: {"label": "Freight Yard — Contextual Firing", "source_kind": CurrentGenerator.FREIGHT_SOURCE, "fixed_size": CurrentGenerator.FREIGHT_SIZE},
	CONTEXTUAL_BAY: {"label": "Contextual Firing Bay", "source_kind": CONTEXTUAL_BAY, "fixed_size": Vector2i(12, 12)},
	FREIGHT_YARD: {"label": "Freight Yard", "source_kind": CurrentGenerator.FREIGHT_SOURCE, "fixed_size": CurrentGenerator.FREIGHT_SIZE},
	FLEET_STATION: {"label": "Fleet Station", "source_kind": CurrentGenerator.FLEET_SOURCE, "fixed_size": CurrentGenerator.FLEET_SIZE},
	PARCEL_TEST: {"label": "Local parcel test", "source_kind": CurrentGenerator.ParcelTest.SOURCE, "fixed_size": Vector2i.ZERO},
	SERVICE_DEPOT: {"label": "Service Depot", "source_kind": CurrentGenerator.DEPOT_SOURCE, "fixed_size": CurrentGenerator.DEPOT_SIZE},
	TACTICAL_TEST_RANGE: {"label": "Tactical Test Range", "source_kind": CurrentGenerator.RANGE_SOURCE, "fixed_size": CurrentGenerator.RANGE_SIZE},
	INTERACTION_RANGE: {"label": "Interaction Range", "source_kind": CurrentGenerator.INTERACTION_SOURCE, "fixed_size": CurrentGenerator.INTERACTION_SIZE},
	PARKING_GARAGE: {"label": "Authored proof — Two-level Parking Garage", "source_kind": "authored_parking_garage", "fixed_size": Vector2i(32, 32)},
	GENERATED_COVER: {"label": "Generated cover", "source_kind": "generated_cover", "fixed_size": Vector2i.ZERO},
	REFINERY: {"label": "Special — Refinery", "source_kind": "generated_refinery", "fixed_size": Vector2i(40, 30)},
	INDUSTRIAL_WAREHOUSE: {"label": "Special — Industrial Warehouse", "source_kind": "generated_industrial_warehouse", "fixed_size": Vector2i(40, 30)},
}

# Curated-site release/mission matrices keep their existing scope. The menu
# additionally exposes the same authored range; no scene/content copy is made.
const PLAYABLE := [SERVICE_DEPOT, FREIGHT_YARD, FLEET_STATION]
const SELECTABLE := PLAYABLE + [TACTICAL_TEST_RANGE, CONTEXTUAL_SHOWCASE, INTERACTION_RANGE]
const REPLAYABLE := SELECTABLE + [CONTEXTUAL_DEPOT, CONTEXTUAL_FREIGHT, CONTEXTUAL_BAY]

static func contextual_variant(id: StringName) -> StringName:
	match id:
		SERVICE_DEPOT: return CONTEXTUAL_DEPOT
		FREIGHT_YARD: return CONTEXTUAL_FREIGHT
		CONTEXTUAL_SHOWCASE: return CONTEXTUAL_SHOWCASE
		_: return &""

static func uses_population(id: StringName) -> bool:
	return id in [SERVICE_DEPOT, FREIGHT_YARD, CONTEXTUAL_DEPOT, CONTEXTUAL_FREIGHT, CONTEXTUAL_SHOWCASE, FLEET_STATION, TACTICAL_TEST_RANGE, INTERACTION_RANGE, PARKING_GARAGE, PARCEL_TEST]

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

## Compatibility input only. Once selected, a named identity is authoritative.
static func id_from_configuration(data: Dictionary, fallback: StringName = GENERATED_COVER) -> StringName:
	var named := StringName(data.get("battlefield_id", &""))
	if not named.is_empty(): return named
	var legacy := resolve_legacy_id(bool(data.get("refinery", false)), bool(data.get("industrial_warehouse", false)), bool(data.get("refinery_2", false)), bool(data.get("loading_yard", false)))
	return legacy if legacy != GENERATED_COVER else fallback

static func generate(id: StringName, requested_size: Vector2i, map_seed: int, cell_size: float, requested_manifest: Dictionary = {}) -> MapData:
	var size := map_size(id, requested_size)
	match id:
		CONTEXTUAL_BAY: return ContextualBay.generate(map_seed, cell_size)
		CONTEXTUAL_DEPOT, CONTEXTUAL_FREIGHT, CONTEXTUAL_SHOWCASE:
			var source := CurrentGenerator.DEPOT_SOURCE if id != CONTEXTUAL_FREIGHT else CurrentGenerator.FREIGHT_SOURCE
			var map := CurrentGenerator.generate(source, map_seed, cell_size, requested_manifest)
			map.contextual_discovery_enabled = true
			if id == CONTEXTUAL_SHOWCASE and map.generation_errors.is_empty():
				_configure_crossfire_deployment(map)
			return map
		FREIGHT_YARD:
			return CurrentGenerator.generate(CurrentGenerator.FREIGHT_SOURCE, map_seed, cell_size, requested_manifest)
		FLEET_STATION:
			return CurrentGenerator.generate(CurrentGenerator.FLEET_SOURCE, map_seed, cell_size, requested_manifest)
		PARCEL_TEST:
			return CurrentGenerator.generate(CurrentGenerator.ParcelTest.SOURCE, map_seed, cell_size, requested_manifest)
		SERVICE_DEPOT:
			return CurrentGenerator.generate(CurrentGenerator.DEPOT_SOURCE, map_seed, cell_size, requested_manifest)
		TACTICAL_TEST_RANGE:
			return CurrentGenerator.generate(CurrentGenerator.RANGE_SOURCE, map_seed, cell_size, requested_manifest)
		INTERACTION_RANGE:
			return CurrentGenerator.generate(CurrentGenerator.INTERACTION_SOURCE, map_seed, cell_size, requested_manifest)
		PARKING_GARAGE, REFINERY, INDUSTRIAL_WAREHOUSE, GENERATED_COVER:
			return _fixtures().generate(id, size, map_seed, cell_size, requested_manifest)
		_:
			var rejected := MapData.new()
			rejected.generation_errors.append({"code": "UNKNOWN_BATTLEFIELD", "detail": String(id)})
			return rejected

## Start squads near surveyed geometry using the standard deployment contract.
## Preserve the other authored spawn options for larger rosters.
static func _configure_crossfire_deployment(map: MapData) -> void:
	for faction in [TacticalUnit.Faction.PLAYER, TacticalUnit.Faction.ENEMY]:
		var zone := map.get_zone(StringName("deployment_%d" % faction))
		if not zone: continue
		var starts := [Vector3i(11, 0, 25), Vector3i(23, 0, 21)] if faction == TacticalUnit.Faction.PLAYER else [Vector3i(17, 0, 22), Vector3i(30, 0, 22)]
		for index in range(starts.size() - 1, -1, -1):
			var cell := map.get_cell(starts[index])
			if not cell or not cell.can_stop: continue
			zone.cells.erase(starts[index])
			zone.cells.push_front(starts[index])

## Returns true when this catalog supplied the complete special presentation.
static func present_special(data: MapData, parent: Node3D, cell_size: float, world_environment: WorldEnvironment = null) -> bool:
	match data.source_kind:
		CurrentGenerator.DEPOT_SOURCE, CurrentGenerator.FREIGHT_SOURCE, CurrentGenerator.FLEET_SOURCE, CurrentGenerator.RANGE_SOURCE, CurrentGenerator.INTERACTION_SOURCE, CurrentGenerator.ParcelTest.SOURCE: return CurrentGenerator.present(data, parent, cell_size, world_environment)
		"authored_parking_garage": return _fixtures().present_garage(data, parent, cell_size, world_environment)
		_: return false

## Current maps bypass the old procedural renderer entirely.
static func present(data: MapData, parent: Node3D, cell_size: float, world_environment: WorldEnvironment = null) -> bool:
	if data.source_kind == CONTEXTUAL_BAY:
		ContextualBay.present(data, parent)
		return true
	if data.source_kind in [CurrentGenerator.DEPOT_SOURCE, CurrentGenerator.FREIGHT_SOURCE, CurrentGenerator.FLEET_SOURCE, CurrentGenerator.RANGE_SOURCE, CurrentGenerator.INTERACTION_SOURCE, CurrentGenerator.ParcelTest.SOURCE, "authored_parking_garage"]:
		return present_special(data, parent, cell_size, world_environment)
	if data.source_kind in ["generated_cover", "generated_refinery", "generated_industrial_warehouse", "generated_flat"]:
		_fixtures().present(data, parent, cell_size)
		return true
	return false
static func _fixtures():
	return load("res://tests/fixtures/legacy_battlefields.gd")
