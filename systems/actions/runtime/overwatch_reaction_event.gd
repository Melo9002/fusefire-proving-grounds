class_name OverwatchReactionEvent
extends RefCounted

var watcher_id: StringName
var checkpoint_cell: Vector3i
var checkpoint_index := 0
var hit_chance := 0
var roll := 0.0
var did_hit := false
var damage := 0
var target_hp_before := 0
var target_hp_after := 0
var target_defeated := false
var supply_points_before := 0
var supply_points_after := 0
var environmental_cover := MapCellData.CoverType.NONE
var shield_applied := false
var shield_accuracy_modifier := 0
var shield_damage_multiplier := 1.0

func to_dictionary() -> Dictionary:
	return {
		"watcher_id": String(watcher_id),
		"checkpoint": [checkpoint_cell.x, checkpoint_cell.y, checkpoint_cell.z],
		"checkpoint_index": checkpoint_index,
		"hit_chance": hit_chance, "roll_milli": roundi(roll * 1000.0),
		"did_hit": did_hit, "damage": damage,
		"target_hp_before": target_hp_before, "target_hp_after": target_hp_after,
		"target_defeated": target_defeated,
		"supply_points_before": supply_points_before, "supply_points_after": supply_points_after,
		"environmental_cover": int(environmental_cover),
		"shield_applied": shield_applied,
		"shield_accuracy_modifier": shield_accuracy_modifier,
		"shield_damage_multiplier_milli": roundi(shield_damage_multiplier * 1000.0),
	}
