extends CharacterBody3D
class_name TacticalUnit

enum Faction { PLAYER, ENEMY, ALLY, NEUTRAL }

signal movement_finished
signal defeated(unit: TacticalUnit)
signal attack_presented(target_world_position: Vector3)

@export var movement_speed: float = 5.0
@export var standing_height: float = 1.0
@export var attack_range: int = 3
@export var faction: Faction = Faction.PLAYER
@export var stats: UnitStats
@export var mission_actor: MissionActor
@export var unit_hud_scene: PackedScene = preload("res://ui/unit_world_bar.tscn")
@export var visual_adapter: UnitVisualAdapter

var current_path: PackedVector3Array = PackedVector3Array()
var grid_position: Vector3i = Vector3i.ZERO
var current_waypoint_idx: int = 0
var is_moving: bool = false
var carried_unit: TacticalUnit
var _movement_speed_before_carry := -1

func carry_unit(unit: TacticalUnit) -> void:
	if not is_instance_valid(unit) or carried_unit != null:
		return
	carried_unit = unit
	_movement_speed_before_carry = stats.speed
	stats.speed = maxi(2, stats.speed - 2)
	unit.visible = false
	unit.process_mode = Node.PROCESS_MODE_DISABLED

func is_carrying_unit() -> bool:
	return is_instance_valid(carried_unit)

func get_mission_id() -> StringName:
	return mission_actor.mission_id if mission_actor else StringName(name)

func get_mission_actor_kind() -> MissionActor.Kind:
	return mission_actor.kind if mission_actor else MissionActor.Kind.COMBATANT

func can_extract_others() -> bool:
	return mission_actor != null and mission_actor.can_extract_others()

func _ready() -> void:
	if stats:
		stats.defeated.connect(_on_stats_defeated)
		stats.hp_changed.connect(_on_hp_changed)
	if visual_adapter:
		visual_adapter.setup(self)
	_spawn_world_hud()

func _on_stats_defeated() -> void:
	if visual_adapter:
		visual_adapter.present_defeat()
	defeated.emit(self)

func _on_hp_changed(_current: int, _maximum: int) -> void:
	if visual_adapter and stats and not stats.is_defeated:
		visual_adapter.present_hit()

func _process(delta: float) -> void:
	if not is_moving:
		return

	if current_waypoint_idx >= current_path.size():
		is_moving = false
		if visual_adapter:
			visual_adapter.present_idle()
		movement_finished.emit()
		return

	var target_waypoint = current_path[current_waypoint_idx]

	global_position = global_position.move_toward(target_waypoint, movement_speed * delta)

	if global_position.distance_to(target_waypoint) < 0.01:
		global_position = target_waypoint
		current_waypoint_idx += 1

func move_along_path(path: PackedVector3Array) -> void:
	if path.size() == 0:
		return
	current_path = path
	current_waypoint_idx = 0
	is_moving = true
	if visual_adapter:
		visual_adapter.present_move()

func present_attack(target_world_position: Vector3) -> void:
	if visual_adapter:
		visual_adapter.present_attack(target_world_position)
	attack_presented.emit(target_world_position)

func face_world_position(target_world_position: Vector3) -> void:
	if visual_adapter:
		visual_adapter.face_world_position(target_world_position)

func finish_defeat_presentation() -> void:
	# Tactical removal has already happened. Leave only the harmless visual body
	# long enough for its one-shot defeat pose to be readable.
	collision_layer = 0
	collision_mask = 0
	await get_tree().create_timer(1.25).timeout
	if is_instance_valid(self):
		queue_free()

func _spawn_world_hud() -> void:
	if not unit_hud_scene:
		push_warning("[TacticalUnit] %s: unit_hud_scene is missing!" % name)
		return
	if not stats:
		push_warning("[TacticalUnit] %s: stats component reference is missing!" % name)
		return

	var ui_layer: Node = get_tree().get_first_node_in_group("UI_LAYER")
	if not ui_layer:
		push_error("[TacticalUnit] %s: No CanvasLayer found in 'UI_LAYER' group!" % name)
		return

	var hud_instance: UnitWorldBar = unit_hud_scene.instantiate() as UnitWorldBar
	if hud_instance:
		ui_layer.add_child(hud_instance)
		hud_instance.setup(self, stats, faction)
