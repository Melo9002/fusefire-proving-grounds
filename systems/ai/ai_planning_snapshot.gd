class_name AIPlanningSnapshot
extends RefCounted
## The board an AI plan was made against. Planning yields between frames; a plan whose
## snapshot has gone stale is discarded rather than committed. The action service still
## rejects stale revisions at commit, so this is the early, cheap half of the same rule.

var revision := 0
var occupancy: Dictionary = {}

static func capture(battle: BattleController) -> AIPlanningSnapshot:
	var snapshot := AIPlanningSnapshot.new()
	snapshot.revision = battle.action_service.state_revision
	snapshot.occupancy = battle.grid_manager.occupancy_map.duplicate()
	return snapshot

## True when committed state or unit positions have moved since the snapshot was taken.
func is_stale(battle: BattleController) -> bool:
	return battle.action_service.state_revision != revision or battle.grid_manager.occupancy_map != occupancy
