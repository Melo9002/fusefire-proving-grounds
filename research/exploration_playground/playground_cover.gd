class_name PlaygroundCover
extends Node
## Cover, Mass Effect 2 style (sandbox package). Space near a wall snaps the character to it, crouched with the wall at its side; A and D slide along it (she turns toward the way she slides); holding the right mouse
## button pops the rifle up over a low wall or leans around the edge of a high one; Space again or S steps back out. The body pose is the shared cover posture (CoverPostureProfile) requested through the character host;
## which wall, where she stands and how she slides is this controller's. Walls are StaticBody3D boxes in the group `exploration_cover`; their height is the box height ("full" cover from 1.5 m).

const SNAP_DISTANCE := 1.6
const STANDOFF := 0.45
const SLIDE_SPEED := 1.5
const FULL_COVER_HEIGHT := 1.5
const END_MARGIN := 0.4

var ctx: Node
var active := false
var wall: StaticBody3D
var _normal := Vector3.BACK     # from the wall toward the side she is on
var _half := Vector3.ONE        # half extents of the wall box


func setup(controller: Node) -> void:
	ctx = controller


## The nearest wall she could take cover behind: {"wall", "normal"} or empty.
func nearest_wall() -> Dictionary:
	var best := {}
	var best_distance := SNAP_DISTANCE
	for node in ctx.get_tree().get_nodes_in_group(PlaygroundProps.COVER_GROUP):
		var candidate := node as StaticBody3D
		var half := _half_extents(candidate)
		if candidate == null or half == Vector3.ZERO:
			continue
		var local: Vector3 = candidate.to_local(ctx.body.global_position)
		if absf(local.x) > half.x + 0.3:
			continue
		var distance := absf(local.z) - half.z
		if distance < best_distance:
			best_distance = distance
			best = {"wall": candidate, "normal": candidate.global_basis.z * signf(local.z if local.z != 0.0 else 1.0)}
	return best


func _half_extents(candidate: StaticBody3D) -> Vector3:
	for child in candidate.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is BoxMesh:
			return ((child as MeshInstance3D).mesh as BoxMesh).size * 0.5
	return Vector3.ZERO


func can_enter() -> bool:
	return not active and not nearest_wall().is_empty() and not ctx.dead and not ctx.visual.is_carrying() and not ctx.visual.is_climbing() and not ctx.visual.is_on_stairs()


## Snaps to the nearest wall and takes cover. Returns false when there is none in reach.
func enter() -> bool:
	if not can_enter():
		return false
	var found := nearest_wall()
	wall = found["wall"]
	_normal = found["normal"]
	_half = _half_extents(wall)
	var local: Vector3 = wall.to_local(ctx.body.global_position)
	local.x = clampf(local.x, -_half.x + END_MARGIN, _half.x - END_MARGIN)
	local.z = signf(local.z if local.z != 0.0 else 1.0) * (_half.z + STANDOFF)
	var snapped_position: Vector3 = wall.to_global(local)
	snapped_position.y = ctx.body.global_position.y
	ctx.body.global_position = snapped_position
	ctx.body.velocity = Vector3.ZERO
	var facing := -_normal
	var height := _half.y * 2.0
	ctx.visual.presenter.hold_facing()
	ctx.visual.enter_cover(atan2(facing.x, facing.z), height >= FULL_COVER_HEIGHT, height, 0)
	active = true
	return true


func leave() -> void:
	if not active:
		return
	active = false
	ctx.visual.leave_cover()
	if not ctx.combat.aiming:
		ctx.visual.presenter.release_facing_hold()


## Per frame while in cover: slide along the wall with A and D (S steps out), staying at the wall.
func move(delta: float) -> void:
	if Input.is_action_just_pressed(&"playground_back"):
		leave()
		return
	var facing := -_normal
	var right := facing.cross(Vector3.UP).normalized()
	var axis := Input.get_axis(&"playground_left", &"playground_right")
	var local: Vector3 = wall.to_local(ctx.body.global_position)
	var along := wall.global_basis.x
	var step := right * axis * SLIDE_SPEED
	# Keep to the wall's length (a little past its ends for a corner peek) and its face.
	var next_x: float = local.x + along.dot(step) * delta
	if absf(next_x) > _half.x - END_MARGIN + 0.1:
		step = Vector3.ZERO
	ctx.body.velocity = Vector3(step.x, 0.0, step.z)
	ctx.body.move_and_slide()
	var fixed: Vector3 = wall.to_local(ctx.body.global_position)
	fixed.z = signf(fixed.z if fixed.z != 0.0 else 1.0) * (_half.z + STANDOFF)
	var back: Vector3 = wall.to_global(fixed)
	back.y = ctx.body.global_position.y
	ctx.body.global_position = back
	var real: Vector3 = ctx.body.get_real_velocity()
	ctx.moving = Vector3(real.x, 0.0, real.z).length() > 0.05
	ctx.visual.set_cover_side(int(signf(axis)) if absf(axis) > 0.1 else (ctx.visual.get_meta(&"last_side", 0)))
	if absf(axis) > 0.1:
		ctx.visual.set_meta(&"last_side", int(signf(axis)))
	if ctx.moving:
		ctx.visual.report_velocity(Vector3(real.x, 0.0, real.z), delta)
