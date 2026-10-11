class_name MissionObjectiveDefinition
extends Resource

enum Kind {
	ELIMINATE,
	PROTECT,
	RESCUE,
	REACH,
	SURVIVE,
	EXTRACT,
	ENEMY_EVACUATION,
	INTERACT_TERMINAL,
}

@export var objective_id: StringName
@export var kind: Kind = Kind.ELIMINATE
@export var title := "Objective"
@export_multiline var description := ""
@export var required := true
@export_range(1, 999, 1) var target_amount := 1
@export var target_ids: Array[StringName] = []
@export var zone_id: StringName
@export_flags("Player", "Enemy", "Ally", "Neutral") var pursuing_factions := (1 << TacticalUnit.Faction.PLAYER) | (1 << TacticalUnit.Faction.ALLY)

func is_pursued_by(faction: TacticalUnit.Faction) -> bool:
	return pursuing_factions & (1 << faction) != 0
