extends CharacterBody3D
class_name TacticalUnit

enum Faction { PLAYER, ENEMY, ALLY, NEUTRAL }

signal movement_finished
signal defeated(unit: TacticalUnit)
signal attack_presented(target_world_position: Vector3)

@export_group("Gameplay")
## Presentation speed in world metres per second. Movement range is UnitStats.speed.
@export_range(0.1, 30.0, 0.1, "suffix:m/s") var movement_speed: float = 5.0
## Feet-to-origin offset used when placing the unit on a grid cell.
@export_range(0.0, 5.0, 0.01, "suffix:m") var standing_height: float = 1.0
## Maximum grid distance for the equipped Prototype 1 weapon.
@export_range(1, 30, 1, "suffix:cells") var attack_range: int = 3
@export_group("Identity")
@export var faction: Faction = Faction.PLAYER
## Stable battle-local identity used by actions and replay. Display/node names may change.
@export var tactical_id: StringName
@export_group("Components")
@export var stats: UnitStats
@export var mission_actor: MissionActor
@export_group("Presentation")
## Disable for isolated presentation tools or fixtures that intentionally have no battle UI layer.
@export var show_world_hud := true
@export var unit_hud_scene: PackedScene = preload("res://ui/unit_world_bar.tscn")
@export var visual_adapter: UnitVisualAdapter
## Show the original Prototype 1 Bean instead of the current character rig.
## Kept as a debug fallback and a tiny piece of FuseFire archaeology.
@export var use_legacy_bean := false
@export_group("")

var current_path: PackedVector3Array = PackedVector3Array()
var grid_position: Vector3i = Vector3i.ZERO
var current_waypoint_idx: int = 0
var is_moving: bool = false
## Suppresses automatic poses while an action service commits authoritative stats.
var defer_stat_presentation := false
var _visual_segments: Array[StringName] = []
var _visual_waypoint := -1
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
	if visual_adapter:
		visual_adapter.present_pickup()

func is_carrying_unit() -> bool:
	return is_instance_valid(carried_unit)

func get_mission_id() -> StringName:
	return mission_actor.mission_id if mission_actor else StringName(name)

func get_mission_actor_kind() -> MissionActor.Kind:
	return mission_actor.kind if mission_actor else MissionActor.Kind.COMBATANT

func can_extract_others() -> bool:
	return mission_actor != null and mission_actor.can_extract_others()

func _ready() -> void:
	_apply_character_presentation()
	if stats:
		stats.defeated.connect(_on_stats_defeated)
		stats.hp_changed.connect(_on_hp_changed)
	if visual_adapter and not use_legacy_bean:
		visual_adapter.setup(self)
	if show_world_hud:
		_spawn_world_hud()

func _apply_character_presentation() -> void:
	var bean := get_node_or_null("MeshInstance3D") as MeshInstance3D
	if bean:
		bean.visible = use_legacy_bean
	if visual_adapter:
		visual_adapter.visible = not use_legacy_bean
		visual_adapter.process_mode = Node.PROCESS_MODE_DISABLED if use_legacy_bean else Node.PROCESS_MODE_INHERIT

func _on_stats_defeated() -> void:
	if visual_adapter and not defer_stat_presentation:
		visual_adapter.present_defeat()
	defeated.emit(self)

func _on_hp_changed(_current: int, _maximum: int) -> void:
	if visual_adapter and stats and not stats.is_defeated and not defer_stat_presentation:
		visual_adapter.present_hit()

func present_attack_impact(defeated_by_attack: bool) -> void:
	if not visual_adapter:
		return
	if defeated_by_attack:
		visual_adapter.present_defeat()
	else:
		visual_adapter.present_hit()

func _process(delta: float) -> void:
	if not is_moving:
		return

	if current_waypoint_idx >= current_path.size():
		is_moving = false
		if visual_adapter:
			visual_adapter.present_movement_end()
		movement_finished.emit()
		return

	var target_waypoint = current_path[current_waypoint_idx]
	if visual_adapter:
		if _visual_waypoint != current_waypoint_idx:
			_visual_waypoint = current_waypoint_idx
			visual_adapter.present_path_segment(_visual_segments[current_waypoint_idx] if current_waypoint_idx < _visual_segments.size() else &"move")
		visual_adapter.update_locomotion(global_position.direction_to(target_waypoint) * movement_speed, delta)

	global_position = global_position.move_toward(target_waypoint, movement_speed * delta)

	if global_position.distance_to(target_waypoint) < 0.01:
		global_position = target_waypoint
		current_waypoint_idx += 1

func move_along_path(path: PackedVector3Array, visual_segments: Array[StringName] = []) -> void:
	if path.size() == 0:
		return
	current_path = path
	_visual_segments = visual_segments
	_visual_waypoint = -1
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
	await get_tree().create_timer(1.25, false).timeout
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
