extends SceneTree

const COMBINATIONS := [Vector2i(1, 1), Vector2i(1, 5), Vector2i(5, 1), Vector2i(5, 5)]
const BattleConfigurationData := preload("res://systems/battle_configuration.gd")

var failures: int = 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	for combination_index in COMBINATIONS.size():
		var counts = COMBINATIONS[combination_index]
		await _check_combination(counts.x, counts.y, combination_index % 2 == 0, combination_index % 2 == 1)
	print("Match setup smoke: %d failure(s)" % failures)
	quit(1 if failures else 0)

func _check_combination(player_count: int, enemy_count: int, expect_victory: bool, use_named_configuration: bool) -> void:
	var level = load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	if use_named_configuration:
		var config := BattleConfigurationData.new()
		config.player_count = player_count
		config.enemy_count = enemy_count
		level.configure_battle(config)
	else:
		level.configure(player_count, enemy_count)
	root.add_child(level)
	await create_timer(0.15).timeout

	var turns = level.turn_manager
	var grid = level.get_node("Systems/GridManager") as GridManager
	var label = "%d vs %d" % [player_count, enemy_count]
	check(turns.player_units.size() == player_count, "%s spawns the requested players" % label)
	check(turns.enemy_units.size() == enemy_count, "%s spawns the requested enemies" % label)
	check(grid.occupancy_map.size() == player_count + enemy_count, "%s registers every unit once" % label)
	check(level.enemy_units_parent.get_child_count() == enemy_count * 2, "%s creates one AI per enemy" % label)

	var stat_ids: Dictionary = {}
	for unit in turns.player_units + turns.enemy_units:
		check(unit.stats.current_hp == unit.stats.max_hp and unit.stats.current_ap == unit.stats.max_ap,
			"%s gives each unit fresh HP and AP" % label)
		stat_ids[unit.stats.get_instance_id()] = true
	check(stat_ids.size() == player_count + enemy_count, "%s gives every unit independent stats" % label)

	var untouched_unit = turns.player_units.back() if player_count > 1 else null
	turns.player_units[0].stats.take_damage(10)
	if untouched_unit:
		check(untouched_unit.stats.current_hp == untouched_unit.stats.max_hp, "%s keeps unit health independent" % label)

	var defeated_team: Array[TacticalUnit] = (turns.enemy_units if expect_victory else turns.player_units).duplicate()
	for unit in defeated_team:
		unit.stats.take_damage(1000)
	await process_frame
	var expected_result = TurnManager.BattleResult.VICTORY if expect_victory else TurnManager.BattleResult.DEFEAT
	check(turns.battle_result == expected_result, "%s reaches the correct battle result" % label)

	level.queue_free()
	await process_frame
	await process_frame
