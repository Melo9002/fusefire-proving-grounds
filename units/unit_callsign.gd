class_name UnitCallsign
extends RefCounted
## Short, distinct names for the units in a battle, so two soldiers are told apart at a glance on
## cards, above the selected unit and in combat messages. Presentation only: actions, replay and
## the AI keep using the stable tactical_id, which never changes.

const PLAYER: Array[String] = ["Alpha", "Bravo", "Charlie", "Delta", "Echo"]
const ALLY: Array[String] = ["Foxtrot", "Golf", "Hotel", "India", "Juliet"]

## The callsign for a squad slot (0-based) of a faction.
static func for_slot(faction: TacticalUnit.Faction, slot: int) -> String:
	match faction:
		TacticalUnit.Faction.PLAYER:
			return PLAYER[slot] if slot >= 0 and slot < PLAYER.size() else "Soldier %d" % (slot + 1)
		TacticalUnit.Faction.ALLY:
			return ALLY[slot] if slot >= 0 and slot < ALLY.size() else "Ally %d" % (slot + 1)
		TacticalUnit.Faction.ENEMY:
			return "Hostile %d" % (slot + 1)
	return ""
