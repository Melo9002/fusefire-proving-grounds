class_name BattleConfiguration
extends RefCounted

## Named inputs used to start a battle. Keep match setup, simulations, and
## replay restoration readable by assigning these fields before configuration.

var player_count: int = 2
var enemy_count: int = 2
var ally_count: int = 0
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
	return {
		"player_count": player_count,
		"enemy_count": enemy_count,
		"generated_map": generated_map,
		"seed": battle_seed,
		"ally_count": ally_count,
		"map_size": map_size,
		"include_vip": include_vip,
		"vip_behavior": vip_behavior,
		"mission": mission.duplicate(true) if mission else null,
		"difficulty": difficulty,
		"refinery": refinery,
	}
