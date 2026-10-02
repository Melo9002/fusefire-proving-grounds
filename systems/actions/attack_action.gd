class_name AttackAction
extends UnitAction

var attacker: TacticalUnit
var target: TacticalUnit
var ap_cost: int
var hit_chance: int
var roll_override: float
var did_hit: bool = false

func _init(p_attacker: TacticalUnit, p_target: TacticalUnit, p_ap_cost: int = 1, p_hit_chance: int = 100, p_roll_override: float = -1.0) -> void:
	attacker = p_attacker
	target = p_target
	ap_cost = p_ap_cost
	hit_chance = clampi(p_hit_chance, 0, 100)
	roll_override = p_roll_override

func is_valid() -> bool:
	if is_instance_valid(attacker) and attacker.is_carrying_unit():
		return false
	if not is_instance_valid(attacker) or not attacker.stats:
		return false
	if not is_instance_valid(target) or not target.stats:
		return false
	if attacker.stats.is_defeated or target.stats.is_defeated:
		return false
	if not FactionRules.are_hostile(attacker.faction, target.faction):
		return false

	if not attacker.stats.has_enough_ap(ap_cost):
		return false

	return true

func execute() -> bool:
	if not is_valid():
		return false
	attacker.stats.consume_ap(ap_cost)
	var roll = roll_override if roll_override >= 0.0 else randf() * 100.0
	did_hit = roll < hit_chance
	if did_hit:
		target.stats.take_damage(25)
		print_rich("[color=red][AttackAction][/color] %s hit %s! (%d%%)" % [attacker.name, target.name, hit_chance])
	else:
		print_rich("[color=gray][AttackAction][/color] %s missed %s. (%d%%)" % [attacker.name, target.name, hit_chance])
	return true
