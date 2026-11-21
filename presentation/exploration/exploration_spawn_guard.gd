class_name ExplorationSpawnGuard
extends Node
## A basic safety net of exploration mode: when the controlled body falls out of the world (off a platform edge, through a gap), let it fall for a moment so the fall reads, then put it back at a spawn point
## with its motion cleared (the point's yaw is the facing the controller gives the character), so nobody is ever stuck below the level. Spawn points are any Node3D in the group `exploration_spawn` (a marker the level author places; its yaw is the facing on return); the
## nearest one to where the body last stood on the floor is used, and with none the body returns to where the guard first saw it. It knows nothing about tactical state and nothing about animation: the
## context's controller listens to `respawned` and tells its character host to forget its motion (see ExplorationCharacterHost.reset_motion).

## The body was returned: the spawn point used (null when the fallback position was used) and the position it was placed at.
signal respawned(point: Node3D, position: Vector3)

const SPAWN_GROUP := &"exploration_spawn"

@export var body: CharacterBody3D
## How far below where the body last stood on the floor it may fall before it is returned (metres): long enough to see the fall, short enough not to wait.
@export_range(1.0, 50.0, 0.5, "suffix:m") var fall_depth := 5.0

var _last_grounded := Vector3.ZERO
var _start := Vector3.ZERO
var _known := false


func _process(_delta: float) -> void:
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	if not _known:
		_known = true
		_start = body.global_position
		_last_grounded = _start
	if body.is_on_floor():
		_last_grounded = body.global_position
	elif body.global_position.y < _last_grounded.y - fall_depth:
		respawn()


## The spawn point nearest to `from`, or null when the level has none.
func nearest_spawn(from: Vector3) -> Node3D:
	var best: Node3D = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(SPAWN_GROUP):
		var point := node as Node3D
		if point == null:
			continue
		var distance := point.global_position.distance_squared_to(from)
		if distance < best_distance:
			best_distance = distance
			best = point
	return best


## Returns the body to a spawn point now (also usable by a controller for a "stuck" button). Its velocity is cleared and its facing set to the point's.
func respawn() -> void:
	var point := nearest_spawn(_last_grounded)
	var target := point.global_position if point != null else _start
	body.global_position = target
	body.velocity = Vector3.ZERO
	_last_grounded = target
	respawned.emit(point, target)
