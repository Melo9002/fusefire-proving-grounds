class_name BattleLevel
extends Node3D

const ReplayRecorderData := preload("res://systems/replay/battle_replay_recorder.gd")
const ReplayPlayerData := preload("res://systems/replay/battle_replay_player.gd")
const ReplaySessionData := preload("res://systems/replay/battle_replay_session.gd")
const ActionCameraDirectorData := preload("res://presentation/camera/action_camera_director.gd")
const BattleConfigurationData := preload("res://systems/battle_configuration.gd")
const MATCH_SETUP_PATH := "res://ui/match_setup.tscn"
const BATTLE_SCENE_PATH := "res://levels/prototype_map/prototype_map.tscn"

@export var unit_scene: PackedScene
@export var player_spawn_zone: SpawnZone
@export var enemy_spawn_zone: SpawnZone
@export var ally_spawn_zone: SpawnZone
@export var player_units_parent: Node3D
@export var allied_units_parent: Node3D
@export var enemy_units_parent: Node3D
@export var objective_units_parent: Node3D
@export var turn_manager: TurnManager
@export var battle_controller: BattleController
@export var objective_manager: ObjectiveManager
@export var objective_zone_visualizer: ObjectiveZoneVisualizer
@export_range(1, 20, 1) var test_battle_attack_range: int = 10

var player_unit_count: int = 2
var enemy_unit_count: int = 2
var allied_unit_count: int = 0
var use_generated_map: bool = false
var battle_seed: int = 1
var generation_seed: int = 1
var generated_size := Vector2i(32, 24)
var use_refinery_map := false
var include_vip := false
var vip_behavior := MissionActor.VIPBehavior.PLAYER_CONTROLLED
var mission_definition: MissionDefinition
var ai_difficulty: AIDifficultyPolicy.Tier = AIDifficultyPolicy.Tier.NORMAL
var pending_replay
var _replay_configuration: Dictionary = {}
var _replay_recorder
var action_camera_director: Node

func configure(player_count: int, enemy_count: int, generate_map: bool = false, match_seed: int = 1, ally_count: int = 0, map_size := Vector2i(32, 24), add_vip: bool = false, behavior: MissionActor.VIPBehavior = MissionActor.VIPBehavior.PLAYER_CONTROLLED, selected_mission: MissionDefinition = null, selected_difficulty: AIDifficultyPolicy.Tier = AIDifficultyPolicy.Tier.NORMAL, refinery: bool = false) -> void:
	var config := BattleConfigurationData.new()
	config.player_count = player_count
	config.enemy_count = enemy_count
	config.generated_map = generate_map
	config.battle_seed = match_seed
	config.ally_count = ally_count
	config.map_size = map_size
	config.include_vip = add_vip
	config.vip_behavior = behavior
	config.mission = selected_mission
	config.difficulty = selected_difficulty
	config.refinery = refinery
	configure_battle(config)


## Preferred human-readable entry point. The positional configure() wrapper is
## retained for existing Prototype 1 scripts and external callers.
func configure_battle(config: BattleConfigurationData) -> void:
	generated_size = config.map_size if FlatMapGenerator.MAP_SIZES.has(config.map_size) else Vector2i(32, 24)
	player_unit_count = clampi(config.player_count, 1, 5)
	enemy_unit_count = clampi(config.enemy_count, 1, 5)
	allied_unit_count = clampi(config.ally_count, 0, 5)
	use_generated_map = config.generated_map
	use_refinery_map = config.refinery
	battle_seed = config.battle_seed
	generation_seed = config.battle_seed
	include_vip = config.include_vip
	vip_behavior = config.vip_behavior
	mission_definition = config.mission
	ai_difficulty = config.difficulty
	battle_controller.ai_difficulty = config.difficulty
	battle_controller.battle_seed = config.battle_seed
	battle_controller.ai_decision_seed = config.battle_seed
	var normalized := BattleConfigurationData.new()
	normalized.player_count = player_unit_count
	normalized.enemy_count = enemy_unit_count
	normalized.ally_count = allied_unit_count
	normalized.generated_map = use_generated_map
	normalized.battle_seed = battle_seed
	normalized.map_size = generated_size
	normalized.include_vip = include_vip
	normalized.vip_behavior = vip_behavior
	normalized.mission = mission_definition
	normalized.difficulty = ai_difficulty
	normalized.refinery = use_refinery_map
	_replay_configuration = normalized.to_replay()

func configure_replay(recording) -> void:
	pending_replay = recording
	var config := BattleConfigurationData.new()
	config.apply_replay(recording.configuration)
	configure_battle(config)
	battle_controller.replay_mode = true

func _ready() -> void:
	action_camera_director = ActionCameraDirectorData.new()
	action_camera_director.name = "ActionCameraDirector"
	add_child(action_camera_director)
	action_camera_director.setup(get_node("CameraRig") as TacticalCamera)
	battle_controller.action_camera_director = action_camera_director
	print("[AI Difficulty] %s" % AIDifficultyPolicy.get_label(ai_difficulty))
	print("[BattleSeed] %d — %s map" % [battle_seed, "generated" if use_generated_map else "authored"])
	if mission_definition != null:
		objective_manager.load_mission(mission_definition)
	if use_generated_map:
		_set_authored_geometry_enabled(false)
		var grid := battle_controller.grid_manager
		grid.map_floor.size.x = generated_size.x * grid.cell_size
		grid.map_floor.size.z = generated_size.y * grid.cell_size
		(get_node("Visualizers/GridVisualizer") as GridVisualizer).generate_grid_lines()
		var rig := get_node("CameraRig") as TacticalCamera
		var scale_factor := maxf(float(generated_size.x) / 32.0, float(generated_size.y) / 24.0)
		rig.max_zoom = 56.0 * maxf(1.0, scale_factor)
		rig._set_zoom(42.0 * scale_factor)
		var width := int(grid.map_floor.size.x / grid.cell_size)
		var depth := int(grid.map_floor.size.z / grid.cell_size)
		var generated_map := FlatMapGenerator.generate_with_cover(width, depth, grid.cell_size, generation_seed, 5, use_refinery_map)
		var generated_geometry := Node3D.new()
		generated_geometry.name = "GeneratedTerrain"
		add_child(generated_geometry)
		GeneratedTerrainPresenter.build(generated_map, generated_geometry, grid.cell_size)
		_spawn_generated_team(player_unit_count, TacticalUnit.Faction.PLAYER, player_units_parent, generated_map)
		_spawn_generated_team(allied_unit_count, TacticalUnit.Faction.ALLY, allied_units_parent, generated_map)
		_spawn_generated_vip(generated_map)
		_spawn_generated_team(enemy_unit_count, TacticalUnit.Faction.ENEMY, enemy_units_parent, generated_map)
		var cover_counts := _count_cover(generated_map)
		print_rich("[color=cyan][MapGenerator][/color] COVER — seed %d, %dx%d, %d low, %d full, %d building(s), %d platform(s), %d hill(s)" % [generation_seed, width, depth, cover_counts.x, cover_counts.y, generated_map.buildings.size(), generated_map.platforms.size(), generated_map.hills.size()])
		if await battle_controller.initialize_battle(generated_map, mission_definition):
			_initialize_objectives()
			_initialize_replay_support()
	else:
		_spawn_team(player_unit_count, player_spawn_zone, player_units_parent, false)
		_spawn_team(allied_unit_count, ally_spawn_zone, allied_units_parent, true)
		_spawn_vip()
		_spawn_team(enemy_unit_count, enemy_spawn_zone, enemy_units_parent, true)
		if await battle_controller.initialize_battle(null, mission_definition):
			_initialize_objectives()
			_initialize_replay_support()

func _initialize_replay_support() -> void:
	if pending_replay:
		_configure_replay_presentation()
		var player = ReplayPlayerData.new()
		player.name = "BattleReplayPlayer"
		add_child(player)
		player.begin(self, pending_replay)
		return
	_replay_recorder = ReplayRecorderData.new()
	_replay_recorder.begin(_replay_configuration, battle_controller, turn_manager, objective_manager)

func _configure_replay_presentation() -> void:
	var hidden_paths := [
		"Visualizers/BattleUI/TurnHUDController/VBoxContainer/APHUDController",
		"Visualizers/BattleUI/TurnHUDController/VBoxContainer/APDisplayLabel",
		"Visualizers/BattleUI/TurnHUDController/VBoxContainer/EndTurnButton",
		"Visualizers/BattleUI/ActionHUDController",
		"Visualizers/BattleUI/ObjectiveHUD",
		"Visualizers/BattleUI/UnitPortraitBar",
		"Visualizers/BattleUI/DebugTools",
	]
	for path in hidden_paths:
		var control := get_node_or_null(path) as Control
		if control:
			control.hide()

func replay_last_battle() -> void:
	if not ReplaySessionData.has_recording():
		return
	get_tree().paused = false
	var replay_level := load(BATTLE_SCENE_PATH).instantiate() as BattleLevel
	replay_level.configure_replay(ReplaySessionData.last_recording)
	get_tree().root.add_child(replay_level)
	get_tree().current_scene = replay_level
	queue_free()

func return_to_match_setup() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MATCH_SETUP_PATH)

func _initialize_objectives() -> void:
	if mission_definition == null:
		return
	objective_manager.begin_tracking(turn_manager, battle_controller, battle_controller.grid_manager)
	battle_controller.bind_objective_manager(objective_manager)
	if objective_manager.get_objective(&"rescue"):
		_spawn_rescue_target()
	objective_zone_visualizer.show_mission(mission_definition)

func _spawn_rescue_target() -> void:
	var grid := battle_controller.grid_manager
	var spawn_cell := MissionZonePlanner.find_rescue_cell(grid.map_data)
	if spawn_cell.x < 0 or grid.is_cell_occupied(spawn_cell):
		push_error("BattleLevel: no valid RescueTarget cell")
		return
	var unit := unit_scene.instantiate() as TacticalUnit
	unit.name = "RescueTarget"
	unit.tactical_id = &"RescueTarget"
	unit.faction = TacticalUnit.Faction.NEUTRAL
	unit.mission_actor.mission_id = &"RescueTarget"
	unit.mission_actor.kind = MissionActor.Kind.RESCUABLE
	objective_units_parent.add_child(unit)
	unit.global_position = grid.grid_to_world(spawn_cell) + Vector3.UP * unit.standing_height
	battle_controller.register_mission_unit(unit, spawn_cell)

func _spawn_team(count: int, zone: SpawnZone, parent: Node3D, _add_ai: bool) -> void:
	if not unit_scene or not zone or not parent or not turn_manager:
		push_error("BattleLevel: missing unit-spawning dependencies")
		return

	var spawn_transforms = zone.get_spawn_transforms(count)
	if spawn_transforms.size() != count:
		return

	for index in count:
		var unit := _create_unit("%sUnit%d" % [_faction_name(zone.faction), index + 1], zone.faction, parent)
		unit.global_transform = spawn_transforms[index]
		_register_team_unit(unit)

func _spawn_generated_team(count: int, faction: TacticalUnit.Faction, parent: Node3D, map_data: MapData) -> void:
	var spawn_cells := map_data.get_spawn_cells(faction)
	if spawn_cells.size() < count:
		push_error("Generated map has insufficient faction %s spawns" % faction)
		return
	for index in count:
		var unit := _create_unit("%sUnit%d" % [_faction_name(faction), index + 1], faction, parent)
		unit.global_position = map_data.get_cell(spawn_cells[index]).world_position + Vector3.UP * unit.standing_height
		_register_team_unit(unit)

func _create_unit(unit_name: String, faction: TacticalUnit.Faction, parent: Node3D) -> TacticalUnit:
	var unit = unit_scene.instantiate() as TacticalUnit
	unit.name = unit_name
	unit.tactical_id = StringName(unit_name)
	unit.faction = faction
	unit.attack_range = test_battle_attack_range
	if unit.mission_actor:
		unit.mission_actor.mission_id = StringName(unit_name)
	parent.add_child(unit)
	var ai := AIController.new()
	ai.objective_manager = objective_manager
	ai.name = "%sAI" % unit_name
	ai.unit = unit
	ai.turn_manager = turn_manager
	ai.battle_controller = battle_controller
	parent.add_child(ai)
	return unit

func _register_team_unit(unit: TacticalUnit) -> void:
	if unit.mission_actor and unit.mission_actor.is_vip():
		if unit.mission_actor.vip_behavior == MissionActor.VIPBehavior.PLAYER_CONTROLLED:
			turn_manager.player_units.append(unit)
		else:
			turn_manager.allied_units.append(unit)
		return
	if unit.faction == TacticalUnit.Faction.ENEMY:
		turn_manager.enemy_units.append(unit)
	elif unit.faction == TacticalUnit.Faction.ALLY:
		turn_manager.allied_units.append(unit)
	else:
		turn_manager.player_units.append(unit)

func _configure_vip(unit: TacticalUnit) -> void:
	unit.mission_actor.kind = MissionActor.Kind.VIP
	unit.mission_actor.vip_behavior = vip_behavior

func _spawn_vip() -> void:
	if not include_vip:
		return
	var transforms := ally_spawn_zone.get_spawn_transforms(allied_unit_count + 1)
	var unit := _create_unit("FriendlyVIP", TacticalUnit.Faction.ALLY, allied_units_parent)
	_configure_vip(unit)
	unit.global_transform = transforms[allied_unit_count]
	_register_team_unit(unit)

func _spawn_generated_vip(map_data: MapData) -> void:
	if not include_vip:
		return
	var spawn := map_data.get_spawn_cells(TacticalUnit.Faction.ALLY)[allied_unit_count]
	var unit := _create_unit("FriendlyVIP", TacticalUnit.Faction.ALLY, allied_units_parent)
	_configure_vip(unit)
	unit.global_position = map_data.get_cell(spawn).world_position + Vector3.UP * unit.standing_height
	_register_team_unit(unit)

func _faction_name(faction: TacticalUnit.Faction) -> String:
	match faction:
		TacticalUnit.Faction.ENEMY:
			return "Enemy"
		TacticalUnit.Faction.ALLY:
			return "Ally"
		_:
			return "Player"

func _set_authored_geometry_enabled(enabled: bool) -> void:
	for group_name in ["terrain_features", "elevated_surfaces", "elevation_paths", "traversal_links"]:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is Node3D:
				(node as Node3D).visible = enabled
			_set_collision_enabled(node, enabled)

func _set_collision_enabled(node: Node, enabled: bool) -> void:
	if node is CSGShape3D:
		(node as CSGShape3D).use_collision = enabled
	for child in node.get_children():
		_set_collision_enabled(child, enabled)

func _count_cover(map_data: MapData) -> Vector2i:
	var counts := Vector2i.ZERO
	for cell: MapCellData in map_data.cells.values():
		if cell.cover_type == MapCellData.CoverType.LOW:
			counts.x += 1
		elif cell.cover_type == MapCellData.CoverType.FULL:
			counts.y += 1
	return counts
