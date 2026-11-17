extends SceneTree
## A wounded combatant may be cautious, but must not disable wait recovery forever.
var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.FLEET_STATION)
	config.battle_seed = 16
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Fleet recovery fixture starts")
	if level.battle_initialization_succeeded:
		var actor := level.turn_manager.player_units[0]
		var ai := level.player_units_parent.get_node("PlayerUnit1AI") as AIController
		actor.stats.current_hp = 25
		ai._consecutive_low_value_actions = AIController.URGENCY_START_ACTIONS - 1
		check(ai._get_movement_urgency_bonus() == 0, "Wounded actor retains ordinary early caution")
		ai._consecutive_low_value_actions = AIController.URGENCY_START_ACTIONS + 3
		check(ai._get_movement_urgency_bonus() > 0, "Repeated wounded waits enable the bounded recovery ramp")
		ai._consecutive_low_value_actions = 100
		check(ai._get_movement_urgency_bonus() == AIController.URGENCY_MAX_SCORE, "Recovery remains capped rather than growing without limit")
		actor.mission_actor.kind = MissionActor.Kind.VIP
		check(ai._get_movement_urgency_bonus() == 0, "VIP movement protection remains intact")
		actor.mission_actor.kind = MissionActor.Kind.COMBATANT
		actor.carried_unit = level.turn_manager.player_units[1]
		check(ai._get_movement_urgency_bonus() == 0, "Carrier protection remains intact")
		actor.carried_unit = null
	level.queue_free()
	await process_frame
	await process_frame
	print("Wounded AI recovery: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
