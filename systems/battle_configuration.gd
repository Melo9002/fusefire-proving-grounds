class_name BattleConfiguration
extends RefCounted

const BattlefieldCatalogData = preload("res://systems/generation/battlefield_catalog.gd")

## Named inputs used to start a battle. Keep match setup, simulations, and
## replay restoration readable by assigning these fields before configuration.

# Keep retired numeric IDs for explicit rejection of saved configurations.
enum BattlefieldPreset {
	LEGACY,
	GENERATION_2_INDUSTRIAL,
	AUTHORED_PLOT,
}

var player_count: int = 2
var enemy_count: int = 2
var ally_count: int = 0
var player_archetypes: Array[StringName] = []
var enemy_archetypes: Array[StringName] = []
var ally_archetypes: Array[StringName] = []
## Old replay configurations omit this and retain pre-SP attack semantics.
var supply_points_enabled := true
## Old replay configurations omit this and retain pre-Aim accuracy/fingerprints.
var aim_enabled := true
## Old replay configurations omit this and retain pre-Shield semantics.
var shield_enabled := true
## Old replay configurations omit this and retain pre-Overwatch semantics.
var overwatch_enabled := true
## Old replay configurations omit this and retain pre-condition semantics.
var conditions_enabled := true
## Old replay configurations omit this and retain the pre-tempo fingerprint shape.
var tactical_tempo_enabled := true
var generated_map := false
var battlefield_preset: BattlefieldPreset = BattlefieldPreset.LEGACY
var battlefield_id: StringName = BattlefieldCatalogData.GENERATED_COVER
var battle_seed: int = 1
var map_size := Vector2i(32, 24)
var include_vip := false
var vip_behavior: MissionActor.VIPBehavior = MissionActor.VIPBehavior.PLAYER_CONTROLLED
var mission: MissionDefinition
var difficulty: AIDifficultyPolicy.Tier = AIDifficultyPolicy.Tier.NORMAL
var player_commander: AICommanderPolicy.Profile = AICommanderPolicy.Profile.DEFAULT
var enemy_commander: AICommanderPolicy.Profile = AICommanderPolicy.Profile.DEFAULT
var refinery := false
var industrial_warehouse := false
var refinery_2 := false
var loading_yard := false
## Exact accepted authored content for generated parcel maps. Empty means a new
## resolution may be made; replay stores the resolved value after generation.
var content_manifest: Dictionary = {}


func apply_replay(data: Dictionary) -> void:
	player_count = data.get("player_count", 2)
	enemy_count = data.get("enemy_count", 2)
	ally_count = data.get("ally_count", 0)
	player_archetypes = _ids_from_data(data.get("player_archetypes", []))
	enemy_archetypes = _ids_from_data(data.get("enemy_archetypes", []))
	ally_archetypes = _ids_from_data(data.get("ally_archetypes", []))
	supply_points_enabled = bool(data.get("supply_points_enabled", false))
	aim_enabled = bool(data.get("aim_enabled", false))
	shield_enabled = bool(data.get("shield_enabled", false))
	overwatch_enabled = bool(data.get("overwatch_enabled", false))
	conditions_enabled = bool(data.get("conditions_enabled", false))
	tactical_tempo_enabled = bool(data.get("tactical_tempo_enabled", false))
	normalize_rosters()
	generated_map = data.get("generated_map", false)
	battlefield_preset = int(data.get("battlefield_preset", BattlefieldPreset.LEGACY)) as BattlefieldPreset
	battle_seed = data.get("seed", 1)
	map_size = data.get("map_size", Vector2i(32, 24))
	include_vip = data.get("include_vip", false)
	vip_behavior = data.get("vip_behavior", MissionActor.VIPBehavior.PLAYER_CONTROLLED)
	var saved_mission: MissionDefinition = data.get("mission")
	mission = saved_mission.duplicate(true) if saved_mission else null
	difficulty = data.get("difficulty", AIDifficultyPolicy.Tier.NORMAL)
	player_commander = int(data.get("player_commander", AICommanderPolicy.Profile.DEFAULT)) as AICommanderPolicy.Profile
	enemy_commander = int(data.get("enemy_commander", AICommanderPolicy.Profile.DEFAULT)) as AICommanderPolicy.Profile
	refinery = data.get("refinery", false)
	industrial_warehouse = data.get("industrial_warehouse", false)
	refinery_2 = data.get("refinery_2", false)
	loading_yard = data.get("loading_yard", false)
	battlefield_id = StringName(data.get("battlefield_id", BattlefieldCatalogData.resolve_legacy_id(refinery, industrial_warehouse, refinery_2, loading_yard)))
	content_manifest = data.get("content_manifest", {}).duplicate(true)


func to_replay() -> Dictionary:
	normalize_rosters()
	return {
		"player_count": player_count,
		"enemy_count": enemy_count,
		"generated_map": generated_map,
		"battlefield_preset": battlefield_preset,
		"battlefield_id": resolved_battlefield_id(),
		"seed": battle_seed,
		"ally_count": ally_count,
		"player_archetypes": player_archetypes.duplicate(),
		"enemy_archetypes": enemy_archetypes.duplicate(),
		"ally_archetypes": ally_archetypes.duplicate(),
		"supply_points_enabled": supply_points_enabled,
		"aim_enabled": aim_enabled,
		"shield_enabled": shield_enabled,
		"overwatch_enabled": overwatch_enabled,
		"conditions_enabled": conditions_enabled,
		"tactical_tempo_enabled": tactical_tempo_enabled,
		"map_size": map_size,
		"include_vip": include_vip,
		"vip_behavior": vip_behavior,
		"mission": mission.duplicate(true) if mission else null,
		"difficulty": difficulty,
		"player_commander": player_commander,
		"enemy_commander": enemy_commander,
		"refinery": refinery,
		"industrial_warehouse": industrial_warehouse,
		"refinery_2": refinery_2,
		"loading_yard": loading_yard,
		"content_manifest": content_manifest.duplicate(true),
	}

func validate_generation_selection() -> Array[Dictionary]:
	var failures: Array[Dictionary] = []
	if battlefield_preset != BattlefieldPreset.LEGACY:
		failures.append(_failure("RETIRED_GENERATOR", "battlefield_preset", "Generator 2 is quarantined; use the local archived project for its maps and recordings"))
	if generated_map and not BattlefieldCatalogData.has(resolved_battlefield_id()):
		failures.append(_failure("UNKNOWN_BATTLEFIELD", "battlefield_id", "Unknown battlefield identity: %s" % battlefield_id))
	return failures

func resolved_battlefield_id() -> StringName:
	var legacy := BattlefieldCatalogData.resolve_legacy_id(refinery, industrial_warehouse, refinery_2, loading_yard)
	if legacy != BattlefieldCatalogData.GENERATED_COVER:
		return legacy
	return battlefield_id if not battlefield_id.is_empty() else BattlefieldCatalogData.GENERATED_COVER

func select_battlefield(id: StringName) -> void:
	battlefield_id = id
	refinery = id == BattlefieldCatalogData.REFINERY
	industrial_warehouse = id == BattlefieldCatalogData.INDUSTRIAL_WAREHOUSE
	refinery_2 = id == BattlefieldCatalogData.REFINERY_2
	loading_yard = id == BattlefieldCatalogData.LOADING_YARD

static func _failure(code: String, field: String, message: String) -> Dictionary:
	return {"code": code, "field": field, "reference": "", "message": message}

func normalize_rosters() -> void:
	player_archetypes = TacticalArchetypeCatalog.normalize_ids(player_archetypes, player_count)
	enemy_archetypes = TacticalArchetypeCatalog.normalize_ids(enemy_archetypes, enemy_count)
	ally_archetypes = TacticalArchetypeCatalog.normalize_ids(ally_archetypes, ally_count)

func get_archetype_id(faction: TacticalUnit.Faction, slot: int) -> StringName:
	normalize_rosters()
	var roster := player_archetypes
	if faction == TacticalUnit.Faction.ENEMY: roster = enemy_archetypes
	elif faction == TacticalUnit.Faction.ALLY: roster = ally_archetypes
	return roster[slot] if slot >= 0 and slot < roster.size() else TacticalArchetypeCatalog.GENERIC_ID

static func _ids_from_data(values: Variant) -> Array[StringName]:
	var result: Array[StringName] = []
	if values is Array:
		for value in values: result.append(StringName(value))
	return result
