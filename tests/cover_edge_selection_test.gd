extends SceneTree
## Cover side selection and cover posture integrity (stabilization 03), through the production fixture: edge geometry, right-side tie, unreachable and
## obstructed edges, hysteresis, independence from facing and from enemies, the body never turned away from the wall, a stable rifle through
## aim, shot, recovery, a hit and leaving cover.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0
var _rig_yaw_samples: Array[float] = []

## The engine's own delta for the frame just processed (what the animation advanced by). A wall-clock difference between two `await process_frame` resumptions is not that: on a fast
## headless frame it can read 1 ms for a frame that moved 3 degrees, which printed as thousands of deg/s although the motion was smooth.
## The rate is also only meaningful at a realistic frame rate: an uncapped headless run produces 1-5 ms frames with unstable deltas, where the same smooth motion (about 8 degrees per frame at 60 fps)
## reads 1500-2000 deg/s on some runs. The test therefore pins the frame rate to 60 fps while it measures (the limit is still 900 deg/s, i.e. 15 degrees per frame).
var _clock := Node.new()

func _frame_dt() -> float:
	return maxf(_clock.get_process_delta_time(), 0.001)

func _initialize() -> void:
	root.add_child(_clock)
	Engine.max_fps = 60
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _contact(direction: Vector3) -> Dictionary:
	return {"direction": direction}

func _wall(f, z: int, x_from: int, x_to: int) -> void:
	for x in range(x_from, x_to + 1):
		f.set_cover(Vector3i(x, 0, z), MapCellData.CoverType.FULL, 2.2)

func _clear_wall(f, z: int, x_from: int, x_to: int) -> void:
	for x in range(x_from, x_to + 1):
		f.set_cover(Vector3i(x, 0, z), MapCellData.CoverType.NONE, 0.0)
		f.grid.get_cell_data(Vector3i(x, 0, z)).walkable = true

func _side(f, profile: CoverPostureProfile, x: int, z: int, previous := 0) -> int:
	var stand: Vector3 = f.grid.grid_to_world(Vector3i(x, 0, z))
	var found := CoverEdgeSelector.edges(f.grid, stand, _contact(Vector3(0, 0, 1)), profile)
	return CoverEdgeSelector.choose(found, previous, profile)

func _run() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	f.battle.set_debug_enemy_control(true)
	var profile := CoverPostureProfile.new()
	check(profile.tie_side == 1 and profile.hysteresis > 0.0, "Default profile prefers the right on a tie and has hysteresis")

	# ---- Pure geometry. The unit stands at z=11 facing +z toward a FULL wall at z=12; its right is -x.
	_wall(f, 12, 5, 7)
	check(_side(f, profile, 6, 11) == CoverEdgeSelector.Side.RIGHT, "Centred behind a wall: equal distances prefer the RIGHT edge")
	check(_side(f, profile, 5, 11) == CoverEdgeSelector.Side.RIGHT, "Near the right end of the wall (the -x end): the nearer RIGHT edge")
	check(_side(f, profile, 7, 11) == CoverEdgeSelector.Side.LEFT, "Near the left end of the wall (the +x end): the nearer LEFT edge")
	var tie_found := CoverEdgeSelector.edges(f.grid, f.grid.grid_to_world(Vector3i(6, 0, 11)), _contact(Vector3(0, 0, 1)), profile)
	check(absf(float(tie_found.right.distance) - float(tie_found.left.distance)) < 0.01 and tie_found.right.usable and tie_found.left.usable, "The tie case really has two usable edges at equal distance")
	var four := CoverPostureProfile.new()
	four.edge_reach = 3.5
	_wall(f, 12, 5, 8)
	check(_side(f, four, 7, 11) == CoverEdgeSelector.Side.LEFT, "Wall of four, one cell from the left end: the nearer (left) edge wins over a farther right one")
	check(_side(f, four, 6, 11) == CoverEdgeSelector.Side.RIGHT, "...and from the right end side the right edge wins")
	# Hysteresis: nearly-equal choices do not flip with a small difference.
	var sticky := CoverPostureProfile.new()
	sticky.edge_reach = 3.5
	sticky.hysteresis = 1.5
	check(_side(f, sticky, 6, 11, CoverEdgeSelector.Side.LEFT) == CoverEdgeSelector.Side.LEFT, "A chosen side is kept when the other edge is only slightly nearer (hysteresis)")
	check(_side(f, four, 6, 11, CoverEdgeSelector.Side.LEFT) == CoverEdgeSelector.Side.RIGHT, "...but a clearly nearer edge wins once the difference exceeds the hysteresis")
	var tie_sticky := _side(f, profile, 6, 11, CoverEdgeSelector.Side.NONE)
	_clear_wall(f, 12, 5, 8)
	_wall(f, 12, 5, 7)
	check(_side(f, profile, 6, 11, CoverEdgeSelector.Side.LEFT) == CoverEdgeSelector.Side.LEFT and tie_sticky == CoverEdgeSelector.Side.RIGHT, "On an exact tie a unit that was peeking left stays left; a fresh choice is right")
	# Unreachable: a wall longer than the reach on both sides.
	_clear_wall(f, 12, 5, 7)
	_wall(f, 12, 2, 10)
	check(_side(f, profile, 6, 11) == CoverEdgeSelector.Side.NONE, "A long wall with neither end within reach gives no peek side (a protected posture)")
	# Obstructed: the nearest edge is blocked by another unit, so the farther one is used.
	_clear_wall(f, 12, 2, 10)
	_wall(f, 12, 5, 7)
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	var blocker_cell := Vector3i(4, 0, 11)
	f.place(enemy, blocker_cell)
	var reach := CoverPostureProfile.new()
	reach.edge_reach = 3.5
	check(_side(f, reach, 5, 11) == CoverEdgeSelector.Side.LEFT, "The nearest edge is skipped when the ground to it is occupied (the farther usable edge is chosen)")
	check(_side(f, profile, 5, 11) == CoverEdgeSelector.Side.NONE, "...and no side at all when the only other edge is out of reach")
	f.place(enemy, Vector3i(12, 0, 10))
	_clear_wall(f, 12, 5, 7)

	# ---- The pose in a real mission: a three-cell LOW wall east of the unit; its right is +z.
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(5, 0, 10))
	f.ready_actor(actor, 3, 4)
	f.act_as(actor)
	var adapter := actor.visual_adapter
	for i in 20: await process_frame
	for z in [9, 10, 11]:
		f.set_cover(Vector3i(6, 0, z), MapCellData.CoverType.LOW, 0.9)
	adapter.present_idle()
	await create_timer(1.0).timeout
	check(adapter.get_presentation_state() == &"cover_low" and adapter.cover_side == CoverEdgeSelector.Side.RIGHT, "Centred behind a low wall the unit peeks right (side %d)" % adapter.cover_side)
	check(absf(rad_to_deg(adapter._cover_yaw) + adapter.cover_profile.protected_yaw_degrees) < 2.0, "Protected, the body turns toward the right edge by the protected angle, not away from the wall (%.0f)" % rad_to_deg(adapter._cover_yaw))
	check(not adapter.cover_edges.has("enemy") and not adapter.cover_edges.has("target") and adapter.cover_edges.keys().size() == 4, "The edge analysis holds geometry only: no enemy or target information")
	# Facing independence and no target leakage: facing the enemy from the other side changes neither the side nor the world orientation of the body.
	var world_yaw_before: float = adapter.rotation.y + adapter.character_root.rotation.y
	var side_before: int = adapter.cover_side
	adapter.face_world_position(adapter.global_position + Vector3(-5, 0, 0))
	await process_frame
	var world_yaw_after: float = adapter.rotation.y + adapter.character_root.rotation.y
	check(adapter.cover_side == side_before and absf(angle_difference(world_yaw_before, world_yaw_after)) < deg_to_rad(3.0), "A facing change does not change the peek side and does not snap the body (%.1f deg)" % rad_to_deg(angle_difference(world_yaw_before, world_yaw_after)))
	adapter.present_idle()
	await create_timer(1.0).timeout
	# Leave the wall and place it so the left is nearer: z 10..11.
	f.set_cover(Vector3i(6, 0, 9), MapCellData.CoverType.NONE, 0.0)
	await create_timer(0.8).timeout
	check(adapter.cover_side == CoverEdgeSelector.Side.LEFT and rad_to_deg(adapter._cover_yaw) > adapter.cover_profile.protected_yaw_degrees - 2.0, "Wall extending to the right only: the nearer edge is the left and the body turns that way (side %d, %.0f deg)" % [adapter.cover_side, rad_to_deg(adapter._cover_yaw)])
	f.set_cover(Vector3i(6, 0, 9), MapCellData.CoverType.LOW, 0.9)
	await create_timer(0.8).timeout
	check(adapter.cover_side == CoverEdgeSelector.Side.LEFT, "Restoring the tie does not flip the side back (hysteresis)")

	# ---- Rifle stability through aim, shot, recovery and a hit, and the end of cover. Measured per frame.
	f.set_cover(Vector3i(6, 0, 9), MapCellData.CoverType.NONE, 0.0)
	f.set_cover(Vector3i(6, 0, 11), MapCellData.CoverType.NONE, 0.0)
	f.set_cover(Vector3i(6, 0, 9), MapCellData.CoverType.LOW, 0.9)
	f.set_cover(Vector3i(6, 0, 11), MapCellData.CoverType.LOW, 0.9)
	adapter.present_idle()
	await create_timer(1.0).timeout
	var done: Array = []
	var attack := func() -> void:
		await f.battle.try_attack(actor, enemy)
		done.append(true)
	attack.call()
	var previous := Vector3.ZERO
	var worst_step := 0.0
	var depth_low := 99.0
	var depth_high := -99.0
	var worst_rate := 0.0
	var t_end := Time.get_ticks_msec() + 3500
	var hit_sent := false
	while Time.get_ticks_msec() < t_end:
		await process_frame
		var dt := _frame_dt()
		var direction := adapter.muzzle_socket.global_basis.z.normalized()
		if previous != Vector3.ZERO:
			worst_rate = maxf(worst_rate, rad_to_deg(direction.angle_to(previous)) / dt)
		previous = direction
		depth_low = minf(depth_low, adapter.crouch_modifier.depth)
		depth_high = maxf(depth_high, adapter.crouch_modifier.depth)
		if not hit_sent and adapter.attack_phase == UnitVisualAdapter.AttackPhase.NONE and not done.is_empty() and Time.get_ticks_msec() > t_end - 2200:
			hit_sent = true
			adapter.present_hit()
	print("  cover firing: worst muzzle angular rate %.0f deg/s, crouch depth range %.2f to %.2f" % [worst_rate, depth_low, depth_high])
	check(worst_rate < 900.0, "The rifle's direction never jumps through aim, shot, recovery and a hit (worst %.0f deg/s)" % worst_rate)
	check(depth_low > 0.2, "The cover crouch is held through the whole sequence, hit included (lowest depth %.2f)" % depth_low)
	check(adapter.get_presentation_state() in [&"cover_low", &"hit"] and adapter._held_cover_kind == MapCellData.CoverType.LOW, "After the hit the unit is still in its cover pose (%s)" % adapter.get_presentation_state())
	await create_timer(1.2).timeout
	check(adapter.get_presentation_state() == &"cover_low" and adapter.aim_blend < 0.05, "...and recovers to the protected posture with the weapon down")

	# ---- Leaving cover: nothing of the cover pose is left, and ordinary locomotion takes over.
	var moved := []
	var go := func() -> void:
		moved.append(await f.battle.try_move(actor, Vector3i(2, 0, 10)))
	go.call()
	await create_timer(0.4).timeout
	check(actor.is_moving and adapter.get_presentation_state() == &"move", "A real move order out of cover starts the locomotion clip (%s)" % adapter.get_presentation_state())
	while moved.is_empty():
		await process_frame
	await create_timer(1.0).timeout
	check(absf(adapter._cover_yaw) < deg_to_rad(1.0) and adapter.crouch_modifier.depth < 0.01 and adapter.crouch_modifier.kneel < 0.01 and adapter.cover_side == CoverEdgeSelector.Side.NONE, "After leaving cover the yaw offset, crouch and side are all cleared")
	var owners := 0
	for child in adapter.skeleton.get_children():
		if child is LocomotionPoseModifier or child is CoverCrouchModifier:
			owners += 1
	check(owners == 2, "Each of the two body modifiers exists exactly once (no duplicate ownership)")

	# ---- The lean clips lean the way their names say (character's left is +x), by a believable amount, head following the hips.
	var sk := adapter.skeleton
	adapter.animation_controller.animation_tree.active = false
	var to_root := adapter.character_root.global_transform.affine_inverse() * sk.global_transform
	sk.reset_bone_poses()
	var rest_hips: Vector3 = to_root * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).origin
	var lean_dx := {}
	for clip in [&"shoot_left", &"shoot_right"]:
		var a: Animation = adapter.animation_controller.animation_player.get_animation(clip)
		sk.reset_bone_poses()
		for track in a.get_track_count():
			var bone := sk.find_bone(a.track_get_path(track).get_subname(0))
			if a.track_get_type(track) == Animation.TYPE_ROTATION_3D:
				sk.set_bone_pose_rotation(bone, a.rotation_track_interpolate(track, 0.07))
			elif a.track_get_type(track) == Animation.TYPE_POSITION_3D:
				sk.set_bone_pose_position(bone, a.position_track_interpolate(track, 0.07))
		lean_dx[clip] = (to_root * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).origin).x - rest_hips.x
	check(lean_dx[&"shoot_left"] > 0.05 and lean_dx[&"shoot_left"] < 0.2, "shoot_left leans toward the character's LEFT (%.3f m)" % lean_dx[&"shoot_left"])
	check(lean_dx[&"shoot_right"] < -0.05 and lean_dx[&"shoot_right"] > -0.2, "shoot_right leans toward the character's RIGHT (%.3f m)" % lean_dx[&"shoot_right"])
	adapter.animation_controller.animation_tree.active = true

	await f.dispose(self)
	print("Cover edge selection: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
