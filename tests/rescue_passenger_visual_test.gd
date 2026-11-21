extends SceneTree
## The carried rescue passenger is a second, separately rigged humanoid draped over the carrier's shoulders in a fireman's
## carry (animation improvements 06 and 06A). It is presentation only: no tactical actor, no weapon, no animation
## controller, no IK. Production UnitVisualAdapter path. Assertions are geometric relations, not pose coordinates.

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _bone_position(rig_root: Node3D, skeleton: Skeleton3D, bone_name: String) -> Vector3:
	return rig_root.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin

func _in_root(rig: UnitVisualAdapter, skeleton: Skeleton3D, bone_name: String) -> Vector3:
	return rig.rig.character_root.global_transform.affine_inverse() * skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone_name)).origin

## The carrier is read INSIDE its skeleton pass (skeleton_updated): outside it, bone poses lack what the modifiers (the
## carry lean) did. The passenger follows in the same signal, so its transform is read there too.
var carrier_state := {"pos": {}, "relation": Transform3D.IDENTITY, "weapon_relation": Transform3D.IDENTITY}
var _rig: UnitVisualAdapter
var _passenger_node: Node3D
var _diagnostics: HandContactDiagnostics

func _on_carrier_updated() -> void:
	var sk := _rig.rig.skeleton
	for bone_name in ["Neck", "Hips", "Head", "HeadTop_End", "LeftArm", "RightArm", "LeftForeArm", "RightForeArm", "LeftHand", "RightHand"]:
		carrier_state.pos["mixamorig_" + bone_name] = _rig.rig.character_root.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_" + bone_name)).origin
	if is_instance_valid(_passenger_node):
		var chest := sk.get_bone_global_pose(sk.find_bone(_rig.rig.torso_bone_name))
		var chest_world := Transform3D(sk.global_basis.orthonormalized() * chest.basis.orthonormalized(), sk.global_transform * chest.origin)
		carrier_state["relation"] = chest_world.affine_inverse() * _passenger_node.global_transform
		carrier_state["weapon_relation"] = chest_world.affine_inverse() * _rig.rig.weapon.global_transform
		carrier_state["chest"] = chest_world
		carrier_state["targets"] = [_rig.rig.right_hand_target.global_position, _rig.rig.support_ik_target.global_position]
		carrier_state["target_in_chest"] = [chest_world.affine_inverse() * _rig.rig.right_hand_target.global_position, chest_world.affine_inverse() * _rig.rig.support_ik_target.global_position]
		carrier_state["axis"] = [_world_to_root(_rig, _rig.rig.stock_marker.global_position), _world_to_root(_rig, _rig.rig.muzzle_socket.global_position)]
		if _diagnostics != null and not _diagnostics.latest.is_empty():
			carrier_state["diag"] = _diagnostics.latest.duplicate(true)
		var lengths := []
		for side in ["Right", "Left"]:
			var upper := sk.get_bone_global_pose(sk.find_bone("mixamorig_%sArm" % side)).origin
			var fore := sk.get_bone_global_pose(sk.find_bone("mixamorig_%sForeArm" % side)).origin
			var hand := sk.get_bone_global_pose(sk.find_bone("mixamorig_%sHand" % side)).origin
			lengths.append([upper.distance_to(fore), fore.distance_to(hand)])
		carrier_state["lengths"] = lengths

func _carrier(bone_name: String) -> Vector3:
	return carrier_state.pos[bone_name]

## Forward lean of the carrier's trunk (hips to neck, in the carrier's own frame): positive leans toward the way it faces.
func _lean_degrees(_unused: UnitVisualAdapter) -> float:
	var trunk := _carrier("mixamorig_Neck") - _carrier("mixamorig_Hips")
	return rad_to_deg(atan2(trunk.z, trunk.y))

func _world_to_root(rig: UnitVisualAdapter, world: Vector3) -> Vector3:
	return rig.rig.character_root.global_transform.affine_inverse() * world

func _angle_at(a: Vector3, b: Vector3, c: Vector3) -> float:
	return rad_to_deg((a - b).angle_to(c - b))

func _pose_signature(skeleton: Skeleton3D) -> Array:
	var out := []
	for i in skeleton.get_bone_count():
		out.append(skeleton.get_bone_pose_rotation(i))
	return out

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	for i in 20: await process_frame
	_rig = rig
	rig.rig.skeleton.skeleton_updated.connect(_on_carrier_updated)
	await process_frame
	var units_before := root.find_children("*", "TacticalUnit", true, false).size()
	var skeletons_before := root.find_children("*", "Skeleton3D", true, false).size()
	check(not rig.rig.character_root.has_node("RescuePassenger"), "No passenger before pickup")
	var lean_before := _lean_degrees(rig)

	rig.preview_carrying = true   # the carrier is carrying (the movement ghost uses the same flag)
	rig.present_pickup()
	rig.present_pickup()
	await create_timer(0.9).timeout
	var passenger := rig.rig.character_root.get_node_or_null("RescuePassenger")
	check(passenger != null, "Pickup shows a RescuePassenger")
	check(rig.rig.character_root.find_children("RescuePassenger", "", true, false).size() == 1, "Picking up twice still shows one passenger")
	_passenger_node = passenger
	rig.rig.skeleton.skeleton_updated.disconnect(_on_carrier_updated)
	rig.rig.skeleton.skeleton_updated.connect(_on_carrier_updated)   # after the passenger's own follow, so its transform is this pass's
	await process_frame
	var passenger_skeleton: Skeleton3D = passenger.skeleton
	check(passenger_skeleton != null and passenger_skeleton != rig.rig.skeleton, "The passenger has its own skeleton")
	check(root.find_children("*", "Skeleton3D", true, false).size() == skeletons_before + 1, "Exactly one extra skeleton was created")
	check(passenger.posed, "The passive pose was applied")
	check(root.find_children("*", "TacticalUnit", true, false).size() == units_before, "No tactical unit or gameplay actor was created for the passenger")
	check(passenger.find_children("*", "AnimationPlayer", true, false).is_empty() and passenger.find_children("*", "AnimationTree", true, false).is_empty() and passenger.find_children("*", "SkeletonModifier3D", true, false).is_empty(), "The passenger has no animation player, tree or skeleton modifier (no IK, no grip)")
	var passenger_scripts := 0
	for node in passenger.find_children("*", "", true, false):
		if node.get_script() != null: passenger_scripts += 1
	check(passenger_scripts == 0, "No controller scripts run inside the passenger")
	check(passenger.find_child("AUG", true, false) == null and passenger.find_child("MuzzleSocket", true, false) == null, "The passenger has no weapon")
	check(rig.rig.weapon.get_parent() == rig.rig.character_root, "The carrier's rifle is off the hand socket")
	check(rig.rig.arm_ik.active and rig.rig.carry_contacts_active(), "The arm IK is on and owned by the carry contacts, not the weapon")
	check(passenger.anchor_point().length() < 0.001, "The passenger's abdomen is on the anchor, not its root origin (%.4f m)" % passenger.anchor_point().length())
	var chest_bone := rig.rig.skeleton.find_bone(rig.rig.torso_bone_name)
	var neck_bone := rig.rig.skeleton.find_bone(rig.rig.neck_bone_name)
	check(chest_bone >= 0 and neck_bone >= 0, "The carrier exposes the chest and neck bones the anchor is measured from")

	# Body: the passenger keeps its bones' lengths, hangs limp, and is folded over the shoulders rather than held level.
	var p := passenger_skeleton
	var worst_length := 0.0
	for bone in p.get_bone_count():
		var parent := p.get_bone_parent(bone)
		if parent < 0:
			continue
		var posed_length := (p.get_bone_global_pose(bone).origin - p.get_bone_global_pose(parent).origin).length()
		var rest_length := (p.get_bone_global_rest(bone).origin - p.get_bone_global_rest(parent).origin).length()
		worst_length = maxf(worst_length, absf(posed_length - rest_length))
	check(worst_length < 0.0001, "Every passenger bone keeps its rest length (largest change %.6f m)" % worst_length)
	var abdomen := _in_root(rig, p, "mixamorig_Spine")
	var head := _in_root(rig, p, "mixamorig_Head")
	var feet := (_in_root(rig, p, "mixamorig_LeftFoot") + _in_root(rig, p, "mixamorig_RightFoot")) * 0.5
	check(head.y < abdomen.y - 0.15 and feet.y < abdomen.y - 0.25, "The head and the feet hang below the abdomen (%.2f and %.2f m; the head joint hangs less than the feet because the neck and skull hang below it)" % [abdomen.y - head.y, abdomen.y - feet.y])
	var fold := rad_to_deg((head - abdomen).angle_to(feet - abdomen))
	check(fold < 140.0, "The body is folded over the shoulder, not a level plank (%.0f deg between head and feet at the abdomen)" % fold)
	var carrier_neck := _carrier("mixamorig_Neck")
	check(signf(head.x - carrier_neck.x) != signf(feet.x - carrier_neck.x), "The head hangs on one side of the carrier and the feet on the other")
	# 06B.1: a fireman's carry crosses the shoulders. The earlier check (feet well forward of the head) described a body hung down the
	# carrier's back; it is replaced by the transverse relation.
	check(absf(feet.x - head.x) > 0.5 and absf(feet.z - head.z) < 0.35, "The body crosses the shoulders: head and feet %.2f m apart sideways and only %.2f m apart front to back" % [absf(feet.x - head.x), absf(feet.z - head.z)])
	check(absf(abdomen.z - carrier_neck.z) < 0.2 and absf(abdomen.x - carrier_neck.x) < 0.25, "The abdomen rests over the shoulders (%.2f m sideways and %.2f m front to back from the neck)" % [abdomen.x - carrier_neck.x, abdomen.z - carrier_neck.z])
	for side in ["Left", "Right"]:
		var elbow := _angle_at(_in_root(rig, p, "mixamorig_%sArm" % side), _in_root(rig, p, "mixamorig_%sForeArm" % side), _in_root(rig, p, "mixamorig_%sHand" % side))
		var knee := _angle_at(_in_root(rig, p, "mixamorig_%sUpLeg" % side), _in_root(rig, p, "mixamorig_%sLeg" % side), _in_root(rig, p, "mixamorig_%sFoot" % side))
		check(elbow < 175.0, "%s arm is loose at the elbow (%.0f deg)" % [side, elbow])
		check(knee < 178.0, "%s knee is not locked (%.0f deg)" % [side, knee])
		check(_in_root(rig, p, "mixamorig_%sHand" % side).y < _in_root(rig, p, "mixamorig_%sArm" % side).y - 0.2, "%s hand hangs below its shoulder" % side)

	# Relation to the carrier: abdomen on the shoulders behind the neck, head of the carrier clear, nothing inside the head.
	var shoulders_y := (_carrier("mixamorig_LeftArm").y + _carrier("mixamorig_RightArm").y) * 0.5
	check(absf(abdomen.y - shoulders_y) < 0.2 and abdomen.z < carrier_neck.z, "The abdomen lies across the shoulders, behind the neck (%.2f m from shoulder height)" % (abdomen.y - shoulders_y))
	var carrier_head := (_carrier("mixamorig_Head") + _carrier("mixamorig_HeadTop_End")) * 0.5   # the middle of the head, not its base joint
	var nearest := INF
	for bone in p.get_bone_count():
		nearest = minf(nearest, (rig.rig.character_root.global_transform.affine_inverse() * p.global_transform * p.get_bone_global_pose(bone).origin).distance_to(carrier_head))
	check(nearest > 0.2, "No passenger joint comes within 0.2 m of the centre of the carrier's head (%.2f m)" % nearest)

	# Carrier posture: leans forward under the load, modestly, and only while carrying.
	var lean_carrying := _lean_degrees(rig)
	check(lean_carrying > lean_before + 8.0 and lean_carrying < lean_before + 25.0, "The carrier leans forward under the load (%.1f deg, was %.1f)" % [lean_carrying, lean_before])
	var carry_clip: Animation = rig.rig.animation_controller.animation_player.get_animation(&"carry_idle")
	var builder := CharacterFallbackAnimationBuilder.new(rig.rig.skeleton, rig.rig.bones)
	for state in [&"rifle_idle", &"aim", &"move", &"pickup", &"boarding"]:
		var clip: Animation = builder._make_rescue_pose(state) if state in [&"pickup", &"boarding"] else rig.rig.animation_controller.animation_player.get_animation(state)
		var track := clip.find_track(NodePath(".:%s" % builder.head), Animation.TYPE_ROTATION_3D)
		var counter := false
		if track >= 0 and clip.track_get_key_count(track) == 1:
			counter = absf(rad_to_deg((clip.track_get_key_value(track, 0) as Quaternion).get_euler().x) - builder.CARRY_HEAD_COUNTER_DEGREES) < 0.01
		check(not counter, "The carry lean is not in the %s clip" % state)
	check(carry_clip != null, "The carry clip exists")

	# Provisional sling stowage: the weapon hangs muzzle-down on the carrier's chest, clear of the passenger.
	check(rig.rig.is_weapon_stowed() and rig.rig.weapon.get_parent() == rig.rig.character_root, "The carrier's weapon is stowed on its chest")
	var butt := _world_to_root(rig, rig.rig.stock_marker.global_position)
	var muzzle := _world_to_root(rig, rig.rig.muzzle_socket.global_position)
	check(muzzle.y < butt.y - 0.3, "The slung weapon hangs muzzle-down (%.2f m below the butt)" % (butt.y - muzzle.y))
	var nearest_passenger := INF
	for bone in p.get_bone_count():
		var parent := p.get_bone_parent(bone)
		if parent < 0:
			continue
		var a := _world_to_root(rig, p.global_transform * p.get_bone_global_pose(parent).origin)
		var b := _world_to_root(rig, p.global_transform * p.get_bone_global_pose(bone).origin)
		var closest := Geometry3D.get_closest_points_between_segments(butt, muzzle, a, b)
		nearest_passenger = minf(nearest_passenger, closest[0].distance_to(closest[1]))
	check(nearest_passenger > 0.12, "The slung weapon's axis keeps clear of every passenger bone (%.2f m)" % nearest_passenger)
	var weapon_before := rig.rig.weapon.global_position
	var axis_before := (muzzle - butt).normalized()
	var profile_before: WeaponHandlingProfile = rig.rig.handling
	var other := profile_before.duplicate() as WeaponHandlingProfile
	other.stowed_offset_from_neck += Vector3(0.0, -0.1, 0.0)
	other.stowed_angles_degrees = Vector3(0, 0, 0)
	rig.rig.handling = other
	rig.rig.stow_weapon()
	await process_frame
	await process_frame
	var moved := _world_to_root(rig, rig.rig.weapon.global_position) - _world_to_root(rig, weapon_before)
	check(absf(moved.y + 0.1) < 0.03, "Another weapon's profile moves where it hangs, without touching the rescue code (%.3f m)" % moved.y)
	var axis_other := (_world_to_root(rig, rig.rig.muzzle_socket.global_position) - _world_to_root(rig, rig.rig.stock_marker.global_position)).normalized()
	check(rad_to_deg(axis_before.angle_to(axis_other)) > 45.0, "...and orients it differently (%.0f deg from the first weapon's hang)" % rad_to_deg(axis_before.angle_to(axis_other)))
	rig.rig.handling = profile_before
	rig.rig.stow_weapon()
	await process_frame
	await process_frame

	# Follows the carrier through moving and turning, with a stable pose. The relation is to the chest bone, because the
	# chest bobs and leans in the carry animation.
	# The rigid-carry invariants below are the contract with the passenger's secondary motion OFF (06B.1). The motion has its own
	# bounds, checked after the contact block.
	rig.rig.passenger_motion_enabled = false
	await process_frame
	await process_frame
	var signature := _pose_signature(p)
	rig.rig.animation_controller.play(&"carry_move")
	await process_frame
	await process_frame
	var relation_to_chest: Transform3D = carrier_state.relation   # sampled once the carry animation is updating the skeleton
	var weapon_relation_to_chest: Transform3D = carrier_state.weapon_relation
	var worst_weapon := 0.0
	var worst_relation := 0.0
	for step in 40:
		await process_frame
		var now_relation: Transform3D = carrier_state.relation
		worst_relation = maxf(worst_relation, relation_to_chest.origin.distance_to(now_relation.origin))
		var now_weapon: Transform3D = carrier_state.weapon_relation
		worst_weapon = maxf(worst_weapon, weapon_relation_to_chest.origin.distance_to(now_weapon.origin) + rad_to_deg((weapon_relation_to_chest.basis.orthonormalized() * now_weapon.basis.orthonormalized().inverse()).get_rotation_quaternion().get_angle()) * 0.001)
		worst_relation = maxf(worst_relation, rad_to_deg((relation_to_chest.basis * now_relation.basis.inverse()).get_rotation_quaternion().get_angle()) * 0.001)
		if step == 20:
			rig.global_position += Vector3(2.0, 0.0, 1.0)
			rig.rotation.y += deg_to_rad(110.0)
	check(worst_relation < 0.0005, "The passenger keeps its place on the chest while the carrier walks, moves and turns 110 deg (%.5f)" % worst_relation)
	check(worst_weapon < 0.0005, "The slung weapon keeps its place on the chest through walking, moving and turning (%.5f)" % worst_weapon)
	var after := _pose_signature(p)
	var drift := 0.0
	for i in signature.size():
		var delta: Quaternion = signature[i]
		var now_q: Quaternion = after[i]
		drift = maxf(drift, maxf(maxf(absf(delta.x - now_q.x), absf(delta.y - now_q.y)), maxf(absf(delta.z - now_q.z), absf(delta.w - now_q.w))))
	check(drift < 0.000001, "The passenger's pose does not change while the carrier moves (largest quaternion component change %s)" % str(drift))

	# Carry contacts (06B): the wrists are on the passenger, through the same arm IK, elbow guidance and hand grip.
	_diagnostics = HandContactDiagnostics.attach(rig.rig)
	_diagnostics.set_readout_visible(false)
	_diagnostics.set_enabled(true)
	var order: Array[String] = []
	for child in rig.rig.skeleton.get_children():
		if child is SkeletonModifier3D: order.append(String(child.name))
	check(order == ["Locomotion", "CoverCrouch", "Traversal", "TraversalLegIK", "WeaponPose", "WeaponArmIK", "HandGrip"], "Modifier order is unchanged: %s" % str(order))
	check(rig.rig.carry_contact_report.size() == 2 and not (rig.rig.carry_contact_report[0] as Dictionary).is_empty() and not (rig.rig.carry_contact_report[1] as Dictionary).is_empty(), "Both anatomical contacts exist")
	check(String(rig.rig.carry_contact_report[0].contact) == "wrist" and String(rig.rig.carry_contact_report[1].contact) == "thigh", "The right hand holds the wrist and the left the thigh")
	check(rig.rig.grip_modifier.orient_weight == 0.0 and rig.rig.grip_modifier.contact_weight == [1.0, 1.0], "The hands follow the contacts, not the weapon")
	check(rig.rig.aim_blend == 0.0 and rig.rig.weapon_pose_modifier.report.get("available", true) == false, "No weapon pose is applied while carrying (aim blend, support reach)")
	rig.rig.animation_controller.play(&"carry_move")
	await create_timer(0.6).timeout
	rig.rig.skeleton.skeleton_updated.disconnect(_on_carrier_updated)
	rig.rig.skeleton.skeleton_updated.connect(_on_carrier_updated)   # after the diagnostics' own sample, so carrier_state.diag is this pass's
	var worst := {"wrist": 0.0, "palm": 0.0, "finger": 0.0, "normal": 0.0, "margin": 9.0, "elbow_low": 999.0, "elbow_high": 0.0, "target_drift": 0.0, "length": 0.0, "contact_point": 0.0}
	await process_frame
	var target_ref: Array = (carrier_state.target_in_chest as Array).duplicate()
	var rest_lengths := []
	for side in ["Right", "Left"]:
		var rest_upper := rig.rig.skeleton.get_bone_global_rest(rig.rig.skeleton.find_bone("mixamorig_%sArm" % side)).origin
		var rest_fore := rig.rig.skeleton.get_bone_global_rest(rig.rig.skeleton.find_bone("mixamorig_%sForeArm" % side)).origin
		var rest_hand := rig.rig.skeleton.get_bone_global_rest(rig.rig.skeleton.find_bone("mixamorig_%sHand" % side)).origin
		rest_lengths.append([rest_upper.distance_to(rest_fore), rest_fore.distance_to(rest_hand)])
	for step in 50:
		await process_frame
		if step == 25:
			rig.global_position += Vector3(1.0, 0.0, -2.0)
			rig.rotation.y += deg_to_rad(110.0)
		var diag: Dictionary = carrier_state.diag
		for hand in 2:
			var h: Dictionary = diag.hands[hand]
			worst.wrist = maxf(worst.wrist, float(h.wrist_to_ik_target))
			worst.palm = maxf(worst.palm, float(h.palm_to_intended))
			worst.finger = maxf(worst.finger, float(h.finger_direction_error_deg))
			worst.normal = maxf(worst.normal, float(h.palm_normal_error_deg))
			worst.margin = minf(worst.margin, float(h.reach_margin))
			worst.elbow_low = minf(worst.elbow_low, float(h.elbow_angle_deg))
			worst.elbow_high = maxf(worst.elbow_high, float(h.elbow_angle_deg))
			worst.target_drift = maxf(worst.target_drift, ((carrier_state.target_in_chest[hand] as Vector3) - (target_ref[hand] as Vector3)).length())
			var arm_lengths: Array = carrier_state.lengths[hand]
			worst.length = maxf(worst.length, maxf(absf(float(arm_lengths[0]) - float(rest_lengths[hand][0])), absf(float(arm_lengths[1]) - float(rest_lengths[hand][1]))))
	print("  carry contacts over a walk and a 110 deg turn: wrist %.2f mm, palm %.1f mm, finger %.0f deg, palm normal %.0f deg, reach margin >= %.1f mm, elbow %.0f-%.0f deg, target drift %.3f mm, arm length change %.4f mm" % [worst.wrist * 1000.0, worst.palm * 1000.0, worst.finger, worst.normal, worst.margin * 1000.0, worst.elbow_low, worst.elbow_high, worst.target_drift * 1000.0, worst.length * 1000.0])
	check(worst.wrist < 0.001, "Each wrist reaches its target (worst %.3f mm)" % (worst.wrist * 1000.0))
	check(worst.margin > 0.005, "Neither arm is stretched to its limit (smallest reach margin %.1f mm)" % (worst.margin * 1000.0))
	check(worst.elbow_low > 40.0 and worst.elbow_high < 175.0, "The elbows stay bent between 40 and 175 deg (%.0f to %.0f)" % [worst.elbow_low, worst.elbow_high])
	check(worst.palm < 0.015, "Each palm centre is within 15 mm of its intended place on the limb (worst %.1f mm)" % (worst.palm * 1000.0))
	check(worst.finger < 5.0 and worst.normal < 20.0, "The hands face the contacts (fingers within %.1f deg, palm normal within %.1f deg)" % [worst.finger, worst.normal])
	check(worst.target_drift < 0.001, "The wrist targets keep their place on the chest through walking and turning (%.4f mm)" % (worst.target_drift * 1000.0))
	check(worst.length < 0.0001, "The carrier's arm bones keep their lengths (largest change %.5f mm)" % (worst.length * 1000.0))
	# The contact points are the passenger's own anatomy: measured from its bones in the same pass.
	var pskel: Skeleton3D = _passenger_node.skeleton
	var report_wrist: Vector3 = rig.rig.carry_contact_report[0].point
	var fore: Vector3 = _passenger_node.global_transform * _passenger_node._skeleton_in_node * pskel.get_bone_global_pose(pskel.find_bone("mixamorig_LeftForeArm")).origin
	var hand_bone: Vector3 = _passenger_node.global_transform * _passenger_node._skeleton_in_node * pskel.get_bone_global_pose(pskel.find_bone("mixamorig_LeftHand")).origin
	var on_segment := Geometry3D.get_closest_point_to_segment(report_wrist, fore, hand_bone)
	check(on_segment.distance_to(report_wrist) < 0.002 and report_wrist.distance_to(fore) > 0.05, "The wrist contact lies on the passenger's own forearm (%.1f mm off its bones)" % (on_segment.distance_to(report_wrist) * 1000.0))
	# Clearance of the slung weapon from the carrier's own arms and hands, in bone terms (not mesh).
	var nearest_arm := INF
	for side in ["Right", "Left"]:
		var chain := [_carrier("mixamorig_%sArm" % side), _carrier("mixamorig_%sForeArm" % side), _carrier("mixamorig_%sHand" % side)]
		for index in 2:
			var closest := Geometry3D.get_closest_points_between_segments(carrier_state.axis[0], carrier_state.axis[1], chain[index], chain[index + 1])
			nearest_arm = minf(nearest_arm, closest[0].distance_to(closest[1]))
	check(nearest_arm > 0.05, "The slung weapon's axis clears the carrier's arm bones (%.2f m)" % nearest_arm)
	print("  slung weapon axis clearance (bone segments, not mesh): carrier arm bones %.3f m, passenger bones %.3f m" % [nearest_arm, nearest_passenger])

	# Secondary motion (06C): restrained, bounded, zero at rest, and the hands stay on the contacts while it plays.
	rig.rig.passenger_motion_enabled = true
	rig.rig.animation_controller.play(&"carry_move")
	await create_timer(0.5).timeout
	var largest_offset := 0.0
	var largest_swing := 0.0
	var motion_wrist := 0.0
	var motion_seen := false
	for step in 90:
		await process_frame
		largest_offset = maxf(largest_offset, _passenger_node.motion_offset.length())
		largest_swing = maxf(largest_swing, absf(_passenger_node.motion_swing))
		motion_seen = motion_seen or _passenger_node.motion_offset.length() > 0.0001
		var live: Dictionary = carrier_state.diag
		for hand in 2:
			motion_wrist = maxf(motion_wrist, float(live.hands[hand].wrist_to_ik_target))
	print("  secondary motion over a walk: offset <= %.1f mm (limit %.1f), swing <= %.2f, wrist error <= %.2f mm" % [largest_offset * 1000.0, rig.rig.passenger_motion_amplitude * 1000.0, largest_swing, motion_wrist * 1000.0])
	check(largest_offset <= rig.rig.passenger_motion_amplitude + 0.0001, "The body's lag stays within its amplitude (%.2f mm)" % (largest_offset * 1000.0))
	check(largest_swing <= 1.0, "The limb swing stays within its range (%.2f)" % largest_swing)
	check(motion_wrist < 0.001, "The wrists stay on their targets while the body lags (%.3f mm)" % (motion_wrist * 1000.0))
	rig.rig.animation_controller.play(&"carry_idle")
	await create_timer(1.6).timeout
	check(_passenger_node.motion_offset.length() < 0.0001 and absf(_passenger_node.motion_swing) < 0.01, "At rest the body is exactly where the chest puts it (%.4f mm)" % (_passenger_node.motion_offset.length() * 1000.0))
	rig.rig.passenger_motion_enabled = false
	await process_frame
	await process_frame
	check(_passenger_node.motion_offset == Vector3.ZERO, "Switching the motion off removes it at once")
	rig.rig.passenger_motion_enabled = true

	# Leaving the carry: ownership returns to the weapon, and nothing of the carry is left behind.
	rig.rig.end_carry()
	check(not rig.rig.carry_contacts_active() and rig.rig.carry_contact_report.is_empty() and rig.rig.grip_modifier.contact_weight == [0.0, 0.0] and rig.rig.grip_modifier.curl == [0.0, 0.0], "Ending the carry releases the contacts and the grip")
	check(rig.rig.weapon.get_parent() == rig.rig.weapon_attachment and not rig.rig.is_weapon_stowed() and rig.rig.arm_ik.active, "The weapon is back in the hand and the arm IK belongs to it again")
	rig.preview_carrying = false
	var reference := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	root.add_child(reference)
	reference.position = Vector3(3.0, 0.0, 0.0)
	for r in [rig, reference]:
		r.presenter.aim.held = true
		r.presenter.aim.release_left = 1000000.0
		r.rig.animation_controller.play(&"aim")
	await create_timer(1.8).timeout
	var local_of := func(r: UnitVisualAdapter, node: Node3D) -> Vector3: return r.rig.character_root.global_transform.affine_inverse() * node.global_position
	var worst_residual := 0.0
	for pair in [[rig.rig.right_hand_target, reference.rig.right_hand_target], [rig.rig.support_ik_target, reference.rig.support_ik_target], [rig.rig.right_elbow_pole, reference.rig.right_elbow_pole], [rig.rig.left_elbow_pole, reference.rig.left_elbow_pole]]:
		worst_residual = maxf(worst_residual, (local_of.call(rig, pair[0]) as Vector3).distance_to(local_of.call(reference, pair[1])))
	# The hand targets match to a micrometre. The elbow poles (0.35 m from the arm's midpoint, direction only) differ by about 2 mm,
	# 0.3 degrees of swivel: the aim latches its swivel once while the carry lean is still easing out, so the chest is a hair off.
	check(worst_residual < 0.005, "After the carry, aiming matches a character that never carried (hand targets and elbow poles within %.2f mm)" % (worst_residual * 1000.0))
	check(rig.rig.aim_blend > 0.99 and absf(rig.rig.crouch_modifier.aim_lean_degrees - reference.rig.crouch_modifier.aim_lean_degrees) < 0.01 and rig.rig.crouch_modifier.support_reach_degrees > 0.0, "Aim blend, aim lean and support reach are back to the weapon's values")
	reference.queue_free()
	await process_frame

	# Boarding shrinks the passenger with the existing tween, and the passenger is freed with the carrier's presentation.
	var carrier := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	root.add_child(carrier)
	carrier.position = Vector3(-3.0, 0.0, 0.0)
	for r in 20: await process_frame
	carrier.preview_carrying = true
	carrier.present_pickup()
	await create_timer(0.9).timeout
	var boarding_passenger: Node3D = carrier.rig.carry_passenger
	check(is_instance_valid(boarding_passenger), "A second carrier shows its own passenger")
	carrier.present_boarding()
	await create_timer(0.7).timeout
	check(boarding_passenger.presence < 0.05 and boarding_passenger.scale.x < 0.05, "Boarding shrinks the passenger (%.3f)" % boarding_passenger.scale.x)
	carrier.queue_free()
	await process_frame
	await process_frame
	check(not is_instance_valid(boarding_passenger), "The passenger is freed with the carrier's presentation")
	print("Rescue passenger visual: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
