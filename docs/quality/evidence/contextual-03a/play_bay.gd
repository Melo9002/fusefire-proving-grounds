extends SceneTree
## Normal game HUD and turn controller, with a deliberately small certification map.
## User arguments: enemy (exchange factions) and rotated (rotate the layout).

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.CONTEXTUAL_BAY)
	config.player_count = 1
	config.enemy_count = 1
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, 1)
	var args := OS.get_cmdline_user_args()
	config.battle_seed = 2 if args.has("enemy") else 1
	if args.has("rotated"): config.battle_seed += 2
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	current_scene = level
	if not level.battle_initialization_succeeded:
		quit(1)
