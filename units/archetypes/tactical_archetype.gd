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
## Normal AP before future Tactical Tempo modifiers. Zero inherits the
## TacticalUnit scene fallback.
@export_range(0, 20, 1, "suffix:AP") var base_ap := 0
## Legacy serialized archetype property. Kept as storage-only so existing
## Resources load without exposing a second AP field in the Inspector.
@export_storage var max_ap := 0
@export_range(1, 99, 1, "suffix:SP") var max_supply_points := 4
@export_range(0, 30, 1) var movement_range := 0
@export_range(0, 30, 1) var attack_range := 0

@export_group("Capabilities")
## Missing capability means this archetype cannot enter Shield Stance.
@export var shield_capability: ShieldCapability
@export_group("Conditions")
@export_flags("Biological", "Mechanical Fluid", "Electronic") var condition_susceptibilities := ConditionDefinition.Susceptibility.MECHANICAL_FLUID | ConditionDefinition.Susceptibility.ELECTRONIC
@export var condition_immunities: Array[StringName] = []
@export_range(0, 9, 1) var emergency_seal_charges := 1

func validation_message() -> String:
	if archetype_id.is_empty():
		return "Archetype ID cannot be empty"
	if display_name.strip_edges().is_empty():
		return "Archetype '%s' needs a display name" % archetype_id
	if shield_capability:
		var capability_error := shield_capability.validation_message()
		if not capability_error.is_empty():
			return "Archetype '%s' has an invalid shield capability: %s" % [archetype_id, capability_error]
	return ""

func configured_base_ap() -> int:
	return base_ap if base_ap > 0 else max_ap

func apply_starting_configuration(unit: TacticalUnit) -> void:
	if not is_instance_valid(unit) or not unit.stats:
		return
	unit.archetype_id = archetype_id
	unit.shield_capability = shield_capability
	unit.condition_susceptibilities = condition_susceptibilities
	unit.condition_immunities = condition_immunities.duplicate()
	unit.emergency_seal_charges = emergency_seal_charges
	if max_hp > 0:
		unit.stats.max_hp = max_hp
		unit.stats.current_hp = max_hp
	var starting_ap := configured_base_ap()
	if starting_ap > 0:
		unit.stats.configure_base_ap(starting_ap, true)
	unit.stats.max_supply_points = max_supply_points
	unit.stats.current_supply_points = max_supply_points
	if movement_range > 0: unit.stats.speed = movement_range
	if attack_range > 0: unit.attack_range = attack_range
