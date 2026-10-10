class_name BattleConfiguration
extends RefCounted

## Named inputs used to start a battle. Keep match setup, simulations, and
## replay restoration readable by assigning these fields before configuration.

var player_count: int = 2
var enemy_count: int = 2
var ally_count: int = 0
var player_archetypes: Array[StringName] = []
var enemy_archetypes: Array[StringName] = []
var ally_archetypes: Array[StringName] = []
## Old replay configurations omit this and retain pre-SP attack semantics.
var supply_points_enabled := true
var generated_map := false
var battle_seed: int = 1
var map_size := Vector2i(32, 24)
var include_vip := false
var vip_behavior: MissionActor.VIPBehavior = MissionActor.VIPBehavior.PLAYER_CONTROLLED
var mission: MissionDefinition
var difficulty: AIDifficultyPolicy.Tier = AIDifficultyPolicy.Tier.NORMAL
var refinery := false


func apply_replay(data: Dictionary) -> void:
	player_count = data.get("player_count", 2)
	enemy_count = data.get("enemy_count", 2)
	ally_count = data.get("ally_count", 0)
	player_archetypes = _ids_from_data(data.get("player_archetypes", []))
	enemy_archetypes = _ids_from_data(data.get("enemy_archetypes", []))
	ally_archetypes = _ids_from_data(data.get("ally_archetypes", []))
	supply_points_enabled = bool(data.get("supply_points_enabled", false))
	normalize_rosters()
	generated_map = data.get("generated_map", false)
	battle_seed = data.get("seed", 1)
	map_size = data.get("map_size", Vector2i(32, 24))
	include_vip = data.get("include_vip", false)
	vip_behavior = data.get("vip_behavior", MissionActor.VIPBehavior.PLAYER_CONTROLLED)
	var saved_mission: MissionDefinition = data.get("mission")
	mission = saved_mission.duplicate(true) if saved_mission else null
	difficulty = data.get("difficulty", AIDifficultyPolicy.Tier.NORMAL)
	refinery = data.get("refinery", false)


func to_replay() -> Dictionary:
	normalize_rosters()
	return {
		"player_count": player_count,
		"enemy_count": enemy_count,
		"generated_map": generated_map,
		"seed": battle_seed,
		"ally_count": ally_count,
		"player_archetypes": player_archetypes.duplicate(),
		"enemy_archetypes": enemy_archetypes.duplicate(),
		"ally_archetypes": ally_archetypes.duplicate(),
		"supply_points_enabled": supply_points_enabled,
		"map_size": map_size,
		"include_vip": include_vip,
		"vip_behavior": vip_behavior,
		"mission": mission.duplicate(true) if mission else null,
		"difficulty": difficulty,
		"refinery": refinery,
	}

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
