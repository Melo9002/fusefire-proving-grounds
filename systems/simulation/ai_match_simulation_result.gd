class_name AIMatchSimulationResult
extends RefCounted

enum Status { COMPLETED, STALLED, ROUND_LIMIT, TIMEOUT, SETUP_FAILED }

var seed := 0
var mission_id: StringName
var mission_title := ""
var difficulty := AIDifficultyPolicy.Tier.NORMAL
var map_source := ""
var map_size := Vector2i.ZERO
var elevated_cell_count := 0
var traversal_link_count := 0
var status := Status.SETUP_FAILED
var battle_result := TurnManager.BattleResult.ONGOING
var rounds := 0
var decision_count := 0
var elapsed_seconds := 0.0
var reason := ""
var quality: MapQualityReport
var configuration: Dictionary = {}
var decision_records: Array[Dictionary] = []
var final_state := ""
var validation_errors: Array[String] = []
var failure_report_path := ""

func status_label() -> String:
	return Status.keys()[status].capitalize()

func battle_result_label() -> String:
	return TurnManager.BattleResult.keys()[battle_result].capitalize()

func completed() -> bool:
	return status == Status.COMPLETED

func summary() -> String:
	var map_label := map_source
	if map_size != Vector2i.ZERO:
		map_label += " %dx%d" % [map_size.x, map_size.y]
	return "seed %d | %s | %s | %s/%s | rounds %d | decisions %d | %.2fs%s" % [
		seed, map_label, mission_title, status_label(), battle_result_label(), rounds, decision_count,
		elapsed_seconds, " | %s" % reason if not reason.is_empty() else "",
	]

func reproduction_data() -> Dictionary:
	return {
		"seed": seed,
		"mission_id": String(mission_id),
		"mission_title": mission_title,
		"difficulty": AIDifficultyPolicy.Tier.keys()[difficulty],
		"map_source": map_source,
		"map_size": [map_size.x, map_size.y],
		"elevated_cell_count": elevated_cell_count,
		"traversal_link_count": traversal_link_count,
		"status": status_label(),
		"battle_result": battle_result_label(),
		"rounds": rounds,
		"decision_count": decision_count,
		"reason": reason,
		"final_state": final_state,
		"validation_errors": validation_errors,
		"configuration": configuration,
		"decisions": decision_records,
	}
