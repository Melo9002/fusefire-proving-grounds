class_name TacticalArchetype
extends Resource

## An Inspector-authored starting preset. Runtime HP, AP, and tactical state
## always belong to the spawned TacticalUnit and are never written back here.

@export var archetype_id: StringName = &"generic"
@export var display_name := "Generic"
@export_multiline var description := "Baseline tactical combatant."

@export_group("Starting Overrides")
## Zero keeps the TacticalUnit scene's current value.
@export_range(0, 999, 1) var max_hp := 0
@export_range(0, 20, 1) var max_ap := 0
@export_range(1, 99, 1, "suffix:SP") var max_supply_points := 4
@export_range(0, 30, 1) var movement_range := 0
@export_range(0, 30, 1) var attack_range := 0

@export_group("Capabilities")
## Declares future shield availability. Directional shield gameplay begins in 01.11.4.
@export var shield_capable := false

func validation_message() -> String:
	if archetype_id.is_empty():
		return "Archetype ID cannot be empty"
	if display_name.strip_edges().is_empty():
		return "Archetype '%s' needs a display name" % archetype_id
	return ""

func apply_starting_configuration(unit: TacticalUnit) -> void:
	if not is_instance_valid(unit) or not unit.stats:
		return
	unit.archetype_id = archetype_id
	unit.shield_capable = shield_capable
	if max_hp > 0:
		unit.stats.max_hp = max_hp
		unit.stats.current_hp = max_hp
	if max_ap > 0:
		unit.stats.max_ap = max_ap
		unit.stats.current_ap = max_ap
	unit.stats.max_supply_points = max_supply_points
	unit.stats.current_supply_points = max_supply_points
	if movement_range > 0: unit.stats.speed = movement_range
	if attack_range > 0: unit.attack_range = attack_range
