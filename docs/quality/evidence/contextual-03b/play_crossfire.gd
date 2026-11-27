extends SceneTree
## Normal tactical game on a compact Depot deployment. Pass "duel" for 1v1.

func _initialize() -> void:
	_start.call_deferred()

func _start() -> void:
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.CONTEXTUAL_SHOWCASE)
	var size := 1 if OS.get_cmdline_user_args().has("duel") else 2
	config.player_count = size
	config.enemy_count = size
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ELIMINATE, size)
	config.battle_seed = 16
	config.difficulty = AIDifficultyPolicy.Tier.HARD
	config.enemy_commander = AICommanderPolicy.Profile.CAUTIOUS
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	current_scene = level
	if not level.battle_initialization_succeeded:
		quit(1)
