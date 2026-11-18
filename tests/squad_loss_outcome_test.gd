extends SceneTree
## Mission outcome when the squad is lost around an extraction (issues #39 and #40).
## Rules under test:
##  - Extract: if every unit dies and nobody got out, the mission is lost, never won.
##  - Extract: units lost after someone extracted do not undo the extraction (still a win).
const MissionKind := MissionObjectiveDefinition.Kind

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func _create_level(kind: MissionKind, include_vip := false, player_count := 2) -> BattleLevel:
	var level := load("res://levels/prototype_map/prototype_map.tscn").instantiate() as BattleLevel
	level.configure(player_count, 2, false, 1, 0, Vector2i(32, 24), include_vip, MissionActor.VIPBehavior.PLAYER_CONTROLLED, MissionCatalog.create_mission(kind, 2, include_vip))
	root.add_child(level)
	await create_timer(0.15).timeout
	level.action_camera_director.frequency = level.action_camera_director.Frequency.OFF
	return level

func _finish(level: BattleLevel) -> void:
	level.queue_free()
	await process_frame
	await process_frame

func _kill(unit: TacticalUnit) -> void:
	unit.stats.take_damage(1000)

func _settle() -> void:
	# Outcome evaluation is deferred and may wait for presentation to finish.
	await create_timer(0.6).timeout

func _run() -> void:
	await _extract_wipe_is_defeat()
	await _extract_after_one_left_then_loss_is_victory()
	print("Squad loss outcomes: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## #39: nobody extracted and the whole squad is dead must be a Defeat.
func _extract_wipe_is_defeat() -> void:
	var level := await _create_level(MissionKind.EXTRACT, false, 2)
	var turns := level.turn_manager
	check(level.objective_manager.extracted_units == 0, "Setup: nobody has extracted")
	for unit in turns.player_units.duplicate():
		_kill(unit)
	await _settle()
	check(turns.player_units.is_empty(), "Setup: the whole squad is dead")
	check(turns.battle_result == TurnManager.BattleResult.DEFEAT, "Extract: a wiped squad with nobody extracted is a Defeat (result %s)" % str(turns.battle_result))
	await _finish(level)

## One unit got out, then the remaining unit dies: the extraction stands and the mission is won.
func _extract_after_one_left_then_loss_is_victory() -> void:
	var level := await _create_level(MissionKind.EXTRACT, false, 2)
	var turns := level.turn_manager
	var exit: Vector3i = level.battle_controller.grid_manager.map_data.get_objective_zone(&"extract")[0]
	var first: TacticalUnit = turns.player_units[0]
	var second: TacticalUnit = turns.player_units[1]
	level.battle_controller.grid_manager.update_unit_position(first, first.grid_position, exit)
	first.stats.set_available_ap_for_setup(0)
	check(await level.objective_manager.try_extract(first), "Setup: the first unit extracts")
	await create_timer(0.75).timeout
	check(level.objective_manager.extracted_units == 1, "Setup: one unit is extracted")
	if is_instance_valid(second):
		_kill(second)
	await _settle()
	check(turns.battle_result == TurnManager.BattleResult.VICTORY, "Extract: units lost after an extraction do not turn it into a Defeat (result %s)" % str(turns.battle_result))
	await _finish(level)
