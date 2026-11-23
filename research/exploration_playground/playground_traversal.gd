class_name PlaygroundTraversal
extends Node
## Ladder and stairs (sandbox package). E at the foot of the ladder mounts it, W and S climb, E gets off (at the top she steps onto the tower). The staircase is walked normally: where she stands on it, her body rides the
## treads (kinematically: the treads have no colliders) and the shared stair pose plants her feet on them. The poses come from the character host, which uses the rig's shared ladder and stair presentation; this controller
## owns where the fixtures are, where she is on them and when she gets on and off. The ramp needs nothing: it is a collider she simply walks up.

const CLIMB_SPEED := 0.9
const MOUNT_RANGE := 1.1

var ctx: Node
var ladder := {}
var stairs: StairModel
var on_ladder := false
var climbed := 0.0
var on_stairs := false
var _ascending := true


func setup(controller: Node, info: Dictionary) -> void:
	ctx = controller
	ladder = info["ladder"]
	stairs = info["stairs"]


func ladder_foot() -> Vector3:
	return Vector3(float(ladder.x), 0.0, float(ladder.z) - 0.9)


func can_mount() -> bool:
	if on_ladder or ctx.dead or ctx.visual.is_carrying() or ctx.cover.active:
		return false
	var p: Vector3 = ctx.body.global_position
	return absf(p.x - float(ladder.x)) < MOUNT_RANGE and p.y < 0.3 and absf(p.z - float(ladder.z) + 0.9) < MOUNT_RANGE


func mount() -> void:
	var plane: float = LadderGeometry.PLANE_AHEAD
	ctx.visual.presenter.hold_facing()
	ctx.body.global_position = Vector3(float(ladder.x), 0.0, float(ladder.z) - plane)
	ctx.body.velocity = Vector3.ZERO
	ctx.visual.face_yaw(0.0)   # facing +Z, toward the ladder
	ctx.combat.set_aim(false)
	ctx.visual.set_crouched(false)
	ctx.visual.begin_climb(float(ladder.length))
	on_ladder = true
	climbed = 0.0
	ctx.visual.set_climb_height(0.0)


func dismount_bottom() -> void:
	_end_ladder()
	ctx.body.global_position = ladder_foot()


func _end_ladder() -> void:
	on_ladder = false
	ctx.visual.end_climb()
	if not ctx.combat.aiming:
		ctx.visual.presenter.release_facing_hold()


## Per frame on the ladder: W and S climb, the body rides the height, and the ends step her off.
func move_ladder(delta: float) -> void:
	var axis := Input.get_axis(&"playground_back", &"playground_forward")
	climbed = clampf(climbed + axis * CLIMB_SPEED * delta, 0.0, float(ladder.length))
	ctx.body.global_position.y = climbed
	ctx.body.velocity = Vector3.ZERO
	ctx.visual.set_climb_height(climbed)
	ctx.moving = false
	if climbed >= float(ladder.length) - 0.001 and axis > 0.0:
		_end_ladder()
		ctx.body.global_position = Vector3(float(ladder.x), float(ladder.length), float(ladder.top_z))
	elif climbed <= 0.001 and axis < 0.0:
		dismount_bottom()


## Per frame while walking: gets her on and off the staircase and rides the treads. Returns true while she is on it (the controller then does not apply gravity).
func update_stairs(_delta: float) -> bool:
	var ramp: float = ctx.visual.rig.stair_profile.riser_ramp
	var p: Vector3 = ctx.body.global_position
	var s := stairs.progress_of(p)
	var right := stairs.direction.cross(Vector3.UP)
	var lateral := absf((p - stairs.low).dot(right))
	var end := stairs.end_s()
	if not on_stairs:
		if lateral < stairs.width * 0.5 and s > -0.5 and s < end + 0.2 and not ctx.dead and not ctx.visual.is_carrying():
			var h := stairs.ride_path_height_at(clampf(s, 0.0, end), ramp)
			if absf(p.y - h) < 0.3 and ctx.body.is_on_floor():
				_ascending = ctx.body.get_real_velocity().dot(stairs.direction) >= 0.0
				ctx.visual.begin_stairs(stairs, _ascending)
				on_stairs = true
				_pass_through_deck(true)
		return on_stairs
	if lateral > stairs.width * 0.5 + 0.1 or s < -0.7 or s > end + 0.35 or ctx.dead:
		on_stairs = false
		ctx.visual.end_stairs()
		_pass_through_deck(false)
		return false
	var along: float = ctx.body.get_real_velocity().dot(stairs.direction)
	if absf(along) > 0.3 and (along > 0.0) != _ascending:
		_ascending = along > 0.0   # she turned round on the stairs
		ctx.visual.begin_stairs(stairs, _ascending)
	p.y = stairs.ride_path_height_at(clampf(s, 0.0, end), ramp)
	ctx.body.global_position = p
	ctx.visual.set_stairs_progress(s, absf(along))
	return true


## While she rides the treads her capsule would catch on the deck's front face and on the treads themselves (the treads carry her, kinematically): they are ignored until she is off the stairs.
func _pass_through_deck(on: bool) -> void:
	var solids: Array[PhysicsBody3D] = []
	var deck := ctx.get_node_or_null("StairDeck") as PhysicsBody3D
	if deck != null:
		solids.append(deck)
	var treads := ctx.get_node_or_null("StairTreads")
	if treads != null:
		for child in treads.get_children():
			if child is PhysicsBody3D:
				solids.append(child)
	for solid in solids:
		if on:
			ctx.body.add_collision_exception_with(solid)
		else:
			ctx.body.remove_collision_exception_with(solid)
