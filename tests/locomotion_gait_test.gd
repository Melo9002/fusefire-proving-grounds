extends SceneTree
## Humanoid locomotion foundation (stabilization 01). Invariants of the procedural walk on the imported MIRA skeleton, sampled over a
## whole stride (16 phases) for every directional clip and the loaded carry walk: the movement coordinate contract, knees that hinge
## forward and not sideways, preserved bone lengths, no hyperextension, alternating legs, a stride that matches the cadence, and
## that ordinary movement leaves the weapon modifiers, the loaded carry and the turn behaviour intact. No visual-tuning angles are asserted.

var failures := 0
var checks := 0
var _rig: UnitVisualAdapter
var _live_lengths: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

## The leg's joints in the character's frame (x its left, y up, z forward) at cycle position `t` of a clip, with the clip's tracks applied
## to a rest-posed skeleton.
func _pose_at(clip: Animation, t: float) -> Dictionary:
	var sk := _rig.skeleton
	sk.reset_bone_poses()
	for track in clip.get_track_count():
		var bone := sk.find_bone(clip.track_get_path(track).get_subname(0))
		if bone < 0:
			continue
		if clip.track_get_type(track) == Animation.TYPE_ROTATION_3D:
			sk.set_bone_pose_rotation(bone, clip.rotation_track_interpolate(track, t))
		elif clip.track_get_type(track) == Animation.TYPE_POSITION_3D:
			sk.set_bone_pose_position(bone, clip.position_track_interpolate(track, t))
	var to_root := _rig.character_root.global_transform.affine_inverse() * sk.global_transform
	var out := {}
	for side in ["Left", "Right"]:
		for joint in ["UpLeg", "Leg", "Foot"]:
			out[side + joint] = to_root * sk.get_bone_global_pose(sk.find_bone("mixamorig_%s%s" % [side, joint])).origin
	return out

func _knee_flexion(pose: Dictionary, side: String) -> float:
	return 180.0 - rad_to_deg((pose[side + "UpLeg"] - pose[side + "Leg"]).angle_to(pose[side + "Foot"] - pose[side + "Leg"]))

func _on_updated() -> void:
	var sk := _rig.skeleton
	_live_lengths = []
	for side in ["Left", "Right"]:
		var hip := sk.get_bone_global_pose(sk.find_bone("mixamorig_%sUpLeg" % side)).origin
		var knee := sk.get_bone_global_pose(sk.find_bone("mixamorig_%sLeg" % side)).origin
		var foot := sk.get_bone_global_pose(sk.find_bone("mixamorig_%sFoot" % side)).origin
		_live_lengths.append([hip.distance_to(knee), knee.distance_to(foot)])

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	await _frames(20)
	_rig = rig
	var sk := rig.skeleton
	var player: AnimationPlayer = rig.animation_controller.animation_player
	var builder := CharacterFallbackAnimationBuilder.new(sk)

	# ---- Coordinate contract: the measured anatomical axes against the rig's visual root.
	var to_root_basis := rig.character_root.global_basis.orthonormalized().inverse() * sk.global_basis.orthonormalized()
	var forward := to_root_basis * builder.anatomical_forward()
	var up := to_root_basis * builder.anatomical_up()
	check(forward.dot(Vector3.BACK) > 0.95, "The anatomical forward (toes) is the visual root's +Z (%s)" % str(forward))
	check(up.dot(Vector3.UP) > 0.95, "Up (hips to head) is the root's +Y")
	var hinge := to_root_basis * builder.hip_hinge()
	check(absf(hinge.dot(Vector3.RIGHT)) > 0.95, "The hip hinge axis is the lateral axis (%s)" % str(hinge))
	var rest_pose := _pose_at(Animation.new(), 0.0)
	check(rest_pose.LeftUpLeg.x > 0.0 and rest_pose.RightUpLeg.x < 0.0, "The character's left is +X")

	# ---- Every clip, every phase.
	var clips := {&"move": Vector2(0, 1), &"move_jog": Vector2(0, 1), &"move_run": Vector2(0, 1), &"carry_move": Vector2(0, 1), &"carry_move_fast": Vector2(0, 1), &"move_back": Vector2(0, -1), &"move_left": Vector2(1, 0), &"move_right": Vector2(-1, 0)}
	var travel := {}
	var lateral_travel := {}
	for name in clips:
		var clip: Animation = player.get_animation(name)
		var rest := _pose_at(Animation.new(), 0.0)
		var upper_rest: float = (rest.LeftUpLeg - rest.LeftLeg).length()
		var lower_rest: float = (rest.LeftLeg - rest.LeftFoot).length()
		var worst_length := 0.0
		var min_flex := 999.0
		var max_flex := -999.0
		var worst_plane := 1.0
		var worst_foot_over_hip := -999.0
		var left_z: Array[float] = []
		var right_z: Array[float] = []
		var left_x: Array[float] = []
		for k in 16:
			var pose := _pose_at(clip, k / 16.0)
			for side in ["Left", "Right"]:
				worst_length = maxf(worst_length, maxf(absf((pose[side + "UpLeg"] - pose[side + "Leg"]).length() - upper_rest), absf((pose[side + "Leg"] - pose[side + "Foot"]).length() - lower_rest)))
				var flex := _knee_flexion(pose, side)
				min_flex = minf(min_flex, flex)
				max_flex = maxf(max_flex, flex)
				var normal: Vector3 = (pose[side + "UpLeg"] - pose[side + "Leg"]).cross(pose[side + "Foot"] - pose[side + "Leg"])
				if flex > 20.0 and normal.length() > 0.001:
					worst_plane = minf(worst_plane, absf(normal.normalized().x))
				worst_foot_over_hip = maxf(worst_foot_over_hip, (pose[side + "Foot"] as Vector3).y - (pose[side + "UpLeg"] as Vector3).y)
			left_z.append(pose.LeftFoot.z - pose.LeftUpLeg.z)
			right_z.append(pose.RightFoot.z - pose.RightUpLeg.z)
			left_x.append(pose.LeftFoot.x - pose.LeftUpLeg.x)
		var fore_aft: float = left_z.max() - left_z.min()
		var sideways: float = left_x.max() - left_x.min()
		travel[name] = fore_aft
		lateral_travel[name] = sideways
		print("  %s: knee flexion %.0f to %.0f deg, knee-plane sagittality >= %.2f, foot fore-aft %.2f m, sideways %.2f m, bone length change %.4f mm" % [name, min_flex, max_flex, worst_plane, fore_aft, sideways, worst_length * 1000.0])
		check(worst_length < 0.0005, "%s keeps the leg bone lengths through the stride (%.4f mm)" % [name, worst_length * 1000.0])
		check(min_flex > -1.0 and max_flex < 115.0, "%s never hyperextends a knee and never over-flexes it (%.0f to %.0f deg)" % [name, min_flex, max_flex])
		check(worst_foot_over_hip < -0.15, "%s keeps the feet below the hips even at the highest heel recovery (%.2f m)" % [name, worst_foot_over_hip])
		if name in [&"move", &"move_jog", &"move_run", &"carry_move", &"carry_move_fast", &"move_back"]:
			check(worst_plane > 0.75, "%s: the knees hinge in the sagittal plane, not sideways (sagittality %.2f)" % [name, worst_plane])
			check(fore_aft > 2.0 * sideways, "%s: the feet travel fore-aft, not sideways (%.2f against %.2f m)" % [name, fore_aft, sideways])
			# Alternating legs: when the left foot is furthest forward the right is not.
			var peak := left_z.find(left_z.max())
			check(right_z[peak] < left_z[peak] - 0.2, "%s: the legs alternate" % name)
		else:
			check(sideways > 2.0 * fore_aft or sideways > 0.1, "%s: a side step moves the feet sideways" % name)
	check(travel[&"carry_move"] < travel[&"move"] - 0.05, "The loaded gait steps shorter than the ordinary walk (%.2f against %.2f m)" % [travel[&"carry_move"], travel[&"move"]])
	# (Stance foot travel against stride length for every gait, including jog and run, is tests/locomotion_speed_test.gd.)

	# ---- Live, through the production update and every modifier: bone lengths, modifier order, hands.
	sk.skeleton_updated.connect(_on_updated)
	rig.present_move()
	await _frames(2)
	var rest_lengths: Array = _live_lengths.duplicate(true)
	var worst_live := 0.0
	for i in 70:
		rig.update_locomotion(Vector3(0, 0, 1.3), 1.0 / 60.0)
		await process_frame
		for side in 2:
			for seg in 2:
				worst_live = maxf(worst_live, absf(float(_live_lengths[side][seg]) - float(rest_lengths[side][seg])))
	check(worst_live < 0.0005, "Leg bone lengths hold through the whole modifier pass while walking (%.4f mm)" % (worst_live * 1000.0))
	var order: Array[String] = []
	for child in sk.get_children():
		if child is SkeletonModifier3D:
			order.append(String(child.name))
	check(order == ["Locomotion", "CoverCrouch", "Traversal", "TraversalLegIK", "WeaponPose", "WeaponArmIK", "HandGrip"], "Modifier order is unchanged: %s" % str(order))
	check(rig.get_presentation_state() == &"move" and not rig.carry_contacts_active() and rig.arm_ik.active, "Walking with the rifle keeps the weapon pose and arm IK in charge of the arms")
	var hand_to_weapon := rig.right_hand_target.global_position.distance_to(rig.weapon.to_global(rig.handling.firing_grip))
	check(hand_to_weapon < 0.15, "While walking the right hand stays on the rifle's grip (%.0f mm)" % (hand_to_weapon * 1000.0))

	# ---- A 110 degree turn while walking: gradual, monotonic, and the forward clip throughout.
	rig.rotation.y = 0.0
	var yaw_before := 0.0
	var monotonic := true
	var forward_throughout := true
	var direction := Vector3(sin(deg_to_rad(110.0)), 0, cos(deg_to_rad(110.0)))
	for i in 60:
		rig.update_locomotion(direction * 1.3, 1.0 / 60.0)
		await process_frame
		monotonic = monotonic and rig.rotation.y >= yaw_before - 0.0001
		yaw_before = rig.rotation.y
		var blend: Vector2 = rig.animation_controller.animation_tree.get("parameters/move/Direction/blend_position")
		forward_throughout = forward_throughout and blend.y > 0.9 and absf(blend.x) < 0.01
	check(monotonic and absf(rig.rotation.y - deg_to_rad(110.0)) < 0.01, "The unit turns steadily to its travel direction (%.0f deg)" % rad_to_deg(rig.rotation.y))
	check(forward_throughout and rig.get_presentation_state() == &"move", "The forward walk stays selected through the turn")

	# ---- Start and stop: idle to move to idle through the controller, without leaving a locomotion state behind.
	rig.present_movement_end()
	await create_timer(0.5).timeout
	check(rig.get_presentation_state() == &"rifle_idle", "Movement ends in the idle stance (%s)" % rig.get_presentation_state())

	# ---- Directions are reachable and distinct through the blend space.
	var tree: AnimationTree = rig.animation_controller.animation_tree
	for entry in [[Vector2(0, 1), &"move"], [Vector2(0, -1), &"move_back"], [Vector2(1, 0), &"move_left"], [Vector2(-1, 0), &"move_right"]]:
		var space := (tree.tree_root as AnimationNodeStateMachine).get_node(&"move") as AnimationNodeBlendTree
		var blend_space := space.get_node(&"Direction") as AnimationNodeBlendSpace2D
		var found := false
		for point in blend_space.get_blend_point_count():
			if not blend_space.get_blend_point_position(point).is_equal_approx(entry[0] as Vector2):
				continue
			var node := blend_space.get_blend_point_node(point)
			if node is AnimationNodeBlendSpace1D:
				# Forward travel is the speed blend of walk, jog and run; its first gait is the walk clip.
				found = (node.get_blend_point_node(0) as AnimationNodeAnimation).animation == entry[1]
			else:
				found = (node as AnimationNodeAnimation).animation == entry[1]
		check(found, "Travel %s selects %s" % [str(entry[0]), str(entry[1])])

	sk.skeleton_updated.disconnect(_on_updated)
	stage.queue_free()
	await _frames(2)
	print("Locomotion gait: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
