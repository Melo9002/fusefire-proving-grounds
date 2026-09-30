class_name MissionActor
extends Node

enum Kind {
	COMBATANT,
	VIP,
	RESCUABLE,
}
enum VIPBehavior { PLAYER_CONTROLLED, FOLLOW_ESCORT, HOLD_POSITION }

@export var mission_id: StringName
@export var kind: Kind = Kind.COMBATANT
@export var extraction_capable: bool = false
@export var vip_behavior: VIPBehavior = VIPBehavior.PLAYER_CONTROLLED

func is_combatant() -> bool:
	return kind == Kind.COMBATANT

func is_vip() -> bool:
	return kind == Kind.VIP

func is_rescuable() -> bool:
	return kind == Kind.RESCUABLE

func can_extract_others() -> bool:
	return extraction_capable
