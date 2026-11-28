class_name PlaygroundTraversal
extends Node
## Ladder and stairs (sandbox package). E at the foot of the ladder mounts it, W and S climb, E gets off (at the top she steps onto the tower). The staircase is walked normally: where she stands on it, her body rides the
## treads (kinematically: the treads have no colliders) and the shared stair pose plants her feet on them. The poses come from the character host, which uses the rig's shared ladder and stair presentation; this controller
## owns where the fixtures are, where she is on them and when she gets on and off. The ramp needs nothing: it is a collider she simply walks up.

const CLIMB_SPEED := 0.9
const MOUNT_RANGE := 1.1
const MOUNT_CLEARANCE := 0.40
const TOP_OUT_SECONDS := 0.60
## The mounting zone and how deliberate the approach has to be: the rails' width either side, from a little behind the foot to just short of the rungs; walking within ~37 degrees of straight at the ladder for a quarter of a second (the body turns to where it is walking, so a separate facing test would only make a turn at the platform's edge dangerous).
const APPROACH_HALF_WIDTH := 0.45
const APPROACH_BEHIND := 0.7
const APPROACH_AHEAD := 0.3
const APPROACH_ALIGNMENT := 0.8
const APPROACH_SECONDS := 0.25
## The zone at the head of the ladder runs from just inside the platform's edge to this far beyond the spot the climb starts from (she is stopped by the zone, not by the edge).
const TOP_ZONE_DEPTH := 0.45
const REMOUNT_PAUSE := 0.8
## How far before either end of the staircase she is already slowed to the pace the stair pose is planned for (a run would otherwise reach the stairs at four metres a second and the pose would have to take over from it in one step).
const STAIR_APPROACH := 2.0

var ctx: Node
var ladder := {}
var stairs: StairModel
var on_ladder := false
var climbed := 0.0
var on_stairs := false
## A/B capture can run the earlier height-only pose and landing walk.
var use_landing_contacts := true
var _ascending := true
var _top_out_time := -1.0
var _entering_from_top := false
## Whether the walk up to the stairs is held to the stair pace. Off only to compare with the behaviour before it existed.
var limit_approach := true
var _approach_time := 0.0
var _mount_blocked_for := 0.0
var _rearm_needed := false


func setup(controller: Node, info: Dictionary) -> void:
	ctx = controller
	ladder = info["ladder"]
	stairs = info["stairs"]


func ladder_foot() -> Vector3:
	return Vector3(float(ladder.x), 0.0, float(ladder.z) - 0.9)


## Which end of the ladder she stands at, as a mounting zone: 1 at the foot, -1 at the head (on the tower), 0 anywhere else, or when she may not mount now (on it already, defeated, in cover, in the middle of a lift,
## or carrying a body the presentation cannot climb with). A zone is narrow (the width of the rails, not the metre either side the old E prompt allowed) and short.
func approach_side() -> int:
	if on_ladder or ctx.dead or ctx.cover.active or ctx.carry.busy:
		return 0
	if ctx.visual.is_carrying() and not ctx.visual.supports_loaded_ladder():
		return 0
	var p: Vector3 = ctx.body.global_position
	if absf(p.x - float(ladder.x)) >= APPROACH_HALF_WIDTH:
		return 0
	if absf(p.y - float(ladder.length)) < 0.12:
		return -1 if p.z >= float(ladder.deck_edge) + 0.05 and p.z < float(ladder.top_z) + TOP_ZONE_DEPTH else 0
	if p.y < 0.3 and p.z > ladder_foot().z - APPROACH_BEHIND and p.z < ladder_foot().z + APPROACH_AHEAD:
		return 1
	return 0


## Whether a mount is possible from here (either end).
func can_mount() -> bool:
	return approach_side() != 0


## The approach-based mount, once per frame from the controller with the direction she is being moved: walking deliberately at the ladder (toward the rungs from the foot, toward the edge from the head, for a moment) puts her on it. Walking past it, standing beside it or stepping onto the zone does not; neither does the walk away from the ladder she has just left (the ladder re-arms once she has been out of the zone).
func update_approach(delta: float, wanted: Vector3) -> bool:
	_mount_blocked_for = maxf(_mount_blocked_for - delta, 0.0)
	var side := approach_side()
	if side == 0:
		_rearm_needed = false
		_approach_time = 0.0
		return false
	if wanted.length() < 0.5:
		_rearm_needed = false   # letting go of the stick re-arms the ladder: the next deliberate walk at it mounts
	var toward := Vector3(0.0, 0.0, float(side))   # the foot is on the -Z side of the rungs, the head on the +Z side of the edge
	if _rearm_needed or _mount_blocked_for > 0.0 or wanted.length() < 0.5 or wanted.normalized().dot(toward) < APPROACH_ALIGNMENT:
		_approach_time = 0.0
		return false
	_approach_time += delta
	if _approach_time < APPROACH_SECONDS:
		return false
	_approach_time = 0.0
	mount()
	return true


func mount() -> void:
	ctx.visual.presenter.hold_facing()
	_entering_from_top = absf(float(ctx.body.global_position.y) - float(ladder.length)) < 0.12
	climbed = float(ladder.length) if _entering_from_top else 0.0
	var z := float(ladder.top_z) if _entering_from_top else float(ladder.z) - MOUNT_CLEARANCE
	ctx.body.global_position = Vector3(float(ladder.x), climbed, z)
	ctx.body.velocity = Vector3.ZERO
	ctx.visual.reset_motion(0.0)   # face the rungs without an idle turn pose
	ctx.combat.set_aim(false)
	ctx.visual.set_crouched(false)
	var landing: LadderLanding = ladder.landing if use_landing_contacts else null
	ctx.visual.begin_climb(float(ladder.length), landing, -1 if _entering_from_top else 1)
	on_ladder = true
	_top_out_time = TOP_OUT_SECONDS if _entering_from_top else -1.0
	ctx.visual.set_climb_height(climbed, float(ladder.z) - z, 1.0 if _entering_from_top else 0.0)


## Stands the character at the foot of the ladder, or on the tower at the head of it, facing the rungs: the two approaches a loaded climb is tried from. Not while on the ladder or in the middle of an interaction.
func place_at_approach(top: bool) -> bool:
	if on_ladder or ctx.dead or ctx.carry.busy:
		return false
	ctx.body.velocity = Vector3.ZERO
	_approach_time = 0.0
	_rearm_needed = false
	if top:
		ctx.body.global_position = Vector3(float(ladder.x), float(ladder.length), float(ladder.top_z))
		ctx.visual.reset_motion(PI)   # facing the way the descent starts: back toward the rungs
	else:
		ctx.body.global_position = ladder_foot()
		ctx.visual.reset_motion(0.0)
	return true


## Keeps the pose where the body is while the loaded transfer runs: nothing translates, and W and S wait.
func _hold_for_transfer() -> void:
	ctx.body.velocity = Vector3.ZERO
	ctx.moving = false
	if _top_out_time >= 0.0:
		var progress := smoothstep(0.0, TOP_OUT_SECONDS, _top_out_time)
		ctx.visual.set_climb_height(climbed, float(ladder.z) - float(ctx.body.global_position.z), progress)
	else:
		var mount_progress := smoothstep(0.0, float(ctx.visual.rig.traversal_profile.mount_length), climbed)
		ctx.visual.set_climb_height(climbed, lerpf(MOUNT_CLEARANCE, LadderGeometry.PLANE_AHEAD, mount_progress))


func dismount_bottom() -> void:
	_end_ladder()
	ctx.body.global_position = ladder_foot()


func _end_ladder() -> void:
	on_ladder = false
	_rearm_needed = true   # the walk away from the ladder must not put her straight back on it
	_mount_blocked_for = REMOUNT_PAUSE
	_top_out_time = -1.0
	_entering_from_top = false
	ctx.visual.end_climb()
	if not ctx.combat.aiming:
		ctx.visual.presenter.release_facing_hold()


## Per frame on the ladder: W and S climb, the body rides the height, and the ends step her off.
func move_ladder(delta: float) -> void:
	# Carrying someone: the passenger is moved into the climbing carry before the body moves (on the ladder's foot and at its head); the pose is kept current meanwhile and the controls are ignored.
	if not ctx.visual.loaded_ladder_ready():
		_hold_for_transfer()
		return
	if _top_out_time >= 0.0:
		var from_z := float(ladder.z) - LadderGeometry.PLANE_AHEAD
		var previous_z: float = ctx.body.global_position.z
		_top_out_time = clampf(_top_out_time + (-delta if _entering_from_top else delta), 0.0, TOP_OUT_SECONDS)
		var progress := smoothstep(0.0, TOP_OUT_SECONDS, _top_out_time)
		ctx.body.global_position.z = lerpf(from_z, float(ladder.top_z), progress)
		ctx.visual.set_climb_height(climbed, float(ladder.z) - float(ctx.body.global_position.z), progress)
		var speed := (float(ctx.body.global_position.z) - previous_z) / maxf(delta, 0.0001)
		ctx.moving = not use_landing_contacts and speed > 0.05
		if ctx.moving:
			ctx.visual.report_velocity(Vector3.BACK * speed, delta)
		if _entering_from_top and _top_out_time <= 0.0:
			_top_out_time = -1.0
		elif not _entering_from_top and _top_out_time >= TOP_OUT_SECONDS:
			_end_ladder()
		return
	var axis := Input.get_axis(&"playground_back", &"playground_forward")
	climbed = clampf(climbed + axis * CLIMB_SPEED * delta, 0.0, float(ladder.length))
	ctx.body.global_position.y = climbed
	ctx.body.velocity = Vector3.ZERO
	var mount_progress := smoothstep(0.0, float(ctx.visual.rig.traversal_profile.mount_length), climbed)
	var rung_plane := lerpf(MOUNT_CLEARANCE, LadderGeometry.PLANE_AHEAD, mount_progress)
	ctx.body.global_position.z = float(ladder.z) - rung_plane
	ctx.visual.set_climb_height(climbed, rung_plane)
	ctx.moving = false
	if climbed >= float(ladder.length) - 0.001 and axis > 0.0:
		if not use_landing_contacts:
			ctx.visual.end_climb()
		_entering_from_top = false
		_top_out_time = 0.0
	elif climbed <= 0.001 and axis < 0.0:
		dismount_bottom()


## Whether she is walking up to either end of the staircase (not yet on it): the controller holds her to the stair pace here, so the hand-over to the stair pose happens at the pace it is planned for.
func approaching_stairs() -> bool:
	if on_stairs or ctx.dead or not limit_approach:
		return false
	var p: Vector3 = ctx.body.global_position
	var s := stairs.progress_of(p)
	var right := stairs.direction.cross(Vector3.UP)
	if absf((p - stairs.low).dot(right)) > stairs.width * 0.5 + 0.25:
		return false
	var end := stairs.end_s()
	if s < 0.0 and s > -STAIR_APPROACH:
		return absf(p.y) < 0.3
	if s > end and s < end + STAIR_APPROACH:
		return absf(p.y - stairs.height_at(end)) < 0.3
	return false


## Per frame while walking: gets her on and off the staircase and rides the treads. Returns true while she is on it (the controller then does not apply gravity).
func jump_from_stairs() -> void:
	if not on_stairs:
		return
	# Launch from the physical tread, which can be above its smoothed ride path.
	var tread_y := stairs.height_at(stairs.progress_of(ctx.body.global_position))
	ctx.body.global_position.y = maxf(ctx.body.global_position.y, tread_y + 0.01)
	_leave_stairs()


func _leave_stairs() -> void:
	on_stairs = false
	ctx.visual.end_stairs()
	_pass_through_deck(false)


func update_stairs() -> bool:
	var ramp: float = ctx.visual.rig.stair_profile.riser_ramp
	var p: Vector3 = ctx.body.global_position
	var s := stairs.progress_of(p)
	var right := stairs.direction.cross(Vector3.UP)
	var lateral := absf((p - stairs.low).dot(right))
	var end := stairs.end_s()
	if not on_stairs:
		if lateral < stairs.width * 0.5 and s > -stairs.tread_depth * 1.5 and s < end + stairs.tread_depth * 1.5 and not ctx.dead and not ctx.visual.is_carrying():
			var h := stairs.ride_path_height_at(clampf(s, 0.0, end), ramp)
			if absf(p.y - h) < 0.3 and ctx.body.is_on_floor():
				_ascending = ctx.body.get_real_velocity().dot(stairs.direction) >= 0.0
				ctx.visual.begin_stairs(stairs, _ascending)
				on_stairs = true
				_pass_through_deck(true)
		if not on_stairs:
			return false
	if lateral > stairs.width * 0.5 + 0.1 or s < -stairs.tread_depth * 1.5 or s > end + stairs.tread_depth * 1.5 or ctx.dead:
		_leave_stairs()
		return false
	var along: float = ctx.body.get_real_velocity().dot(stairs.direction)
	if absf(along) > 0.3 and (along > 0.0) != _ascending:
		_ascending = along > 0.0   # she turned round on the stairs
		ctx.visual.begin_stairs(stairs, _ascending)
	p.y = stairs.ride_path_height_at(clampf(s, 0.0, end), ramp)
	ctx.body.global_position = p
	var across: float = ctx.body.get_real_velocity().dot(-right)
	ctx.visual.set_stairs_progress(s, absf(along), across)
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
