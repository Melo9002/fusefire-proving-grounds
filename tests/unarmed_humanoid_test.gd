extends SceneTree
## A humanoid with no weapon (Task 07 package 9), on the REAL animation stack: the production MIRA visual and a production TacticalUnit built with `weapon_scene = null`. No resolver mock: every modifier, the
## presenter, the IK, the traversal, the rescue and the cleanup run as in the game. Checks that it initialises with nothing missing, reports its equipment truthfully (NONE, and for an armed MIRA HELD and
## SLUNG), moves, turns, crouches and kneels, hangs its arms like a body rather than a T-pose, climbs and descends with its hands on the rungs, takes a hit and a defeat, carries and sets down a passenger,
## ignores weapon requests safely, and cleans up. Structural headless checks; the rendered capture is the visual evidence.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const UNIT_SCENE := preload("res://units/tactical_unit.tscn")
const COMPLETED := PresentationTypes.Outcome.COMPLETED
const SKIPPED := PresentationTypes.Outcome.SKIPPED
const INTERRUPTED := PresentationTypes.Outcome.INTERRUPTED
var failures := 0
var checks := 0

func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _unarmed() -> Array:
	var stage := Node3D.new()
	root.add_child(stage)
	var v: TacticalCharacterAdapter = VISUAL.instantiate()
	v.rig.weapon_scene = null   # before the tree: the character is built without a weapon
	stage.add_child(v)
	_hook(v)
	await _frames(15)
	return [stage, v]

## Bone positions and rotations are read where the finished pose is valid (the skeleton's update): between updates the solved IK is not what a read returns.
var _pose := {}   # bone name -> {"world": Vector3, "rotation": Quaternion}

func _hook(v: TacticalCharacterAdapter) -> void:
	var names: Array[StringName] = [v.rig.bones.right_arm[0], v.rig.bones.right_arm[2], v.rig.bones.left_arm[0], v.rig.bones.left_arm[2], v.rig.bones.left_leg[0]]
	v.rig.skeleton.skeleton_updated.connect(func() -> void:
		for bone_name in names:
			var index := v.rig.skeleton.find_bone(bone_name)
			_pose[bone_name] = {"world": v.rig.skeleton.global_transform * v.rig.skeleton.get_bone_global_pose(index).origin, "rotation": v.rig.skeleton.get_bone_pose_rotation(index)})

func _world(_v: TacticalCharacterAdapter, bone: StringName) -> Vector3:
	return _pose[bone].world

func _watch(handle: ActionHandle) -> Array:
	var seen: Array = []
	handle.when_done(func(outcome: int) -> void: seen.append(outcome))
	return seen

func _run() -> void:
	var pair := await _unarmed()
	var stage: Node3D = pair[0]
	var v: TacticalCharacterAdapter = pair[1]

	# ---- It initialises with nothing missing, and says what it holds.
	var stages := v.rig.skeleton.get_children().filter(func(c): return c is SkeletonModifier3D).map(func(c): return String(c.name))
	check(not v.rig.has_weapon() and v.rig.weapon == null and v.rig.muzzle_socket == null and v.rig.weapon_attachment == null and v.rig.muzzle_flash == null, "Built with no weapon: no weapon node, no socket, no muzzle")
	check(stages == ["Locomotion", "CoverCrouch", "Traversal", "TraversalLegIK", "WeaponPose", "WeaponArmIK", "HandGrip"] and v.rig.bones.degraded.is_empty(), "...and every stage of the stack still builds (%s)" % [stages])
	check(v.rig.equipment_state() == PresentationTypes.EquipmentState.NONE and v.presenter.intent().equipment == PresentationTypes.EquipmentState.NONE and not v.rig.is_weapon_stowed(), "The equipment state is NONE, in the rig and in the presenter's snapshot")
	check(PoseOwnership.validate().is_empty(), "The pose-ownership declarations are unchanged and consistent")

	# ---- Arms hang from the shoulders like a body's, not out in a T-pose, and the hands rest open.
	await _frames(20)
	var arm_ok := true
	var shoulder_r := _world(v, v.rig.bones.right_arm[0])
	var hand_r := _world(v, v.rig.bones.right_arm[2])
	var shoulder_l := _world(v, v.rig.bones.left_arm[0])
	var hand_l := _world(v, v.rig.bones.left_arm[2])
	var drop_r := shoulder_r.y - hand_r.y
	var drop_l := shoulder_l.y - hand_l.y
	var reach_r := shoulder_r.distance_to(hand_r)
	check(drop_r > 0.5 * v.rig._arm_length(0) and drop_l > 0.5 * v.rig._arm_length(1), "The hands hang well below the shoulders (%.2f and %.2f m of an arm %.2f m long), not out in a T-pose" % [drop_r, drop_l, v.rig._arm_length(0)])
	check(reach_r < v.rig._arm_length(0) * 1.02 and v.rig.grip_modifier.curl[0] == RigBones.FINGERS.size() * 0.0 + CharacterRig.UNARMED_HAND_CURL, "...within the arm's length, with the fingers resting a little closed")
	check(absf(v.rig.right_hand_target.global_position.distance_to(hand_r)) < 0.08, "The hand follows its target (%.3f m)" % v.rig.right_hand_target.global_position.distance_to(hand_r))

	# ---- Locomotion and turning.
	var thigh_before: Quaternion = _pose[v.rig.bones.left_leg[0]].rotation
	var swing := 0.0
	v.rig.animation_controller.play(&"move")   # a walk: the movement clip the gait feeds (the tactical unit plays it when it moves)
	for i in 90:
		v.update_locomotion(Vector3(0, 0, 3.0), 1.0 / 60.0)
		await process_frame
		swing = maxf(swing, rad_to_deg(thigh_before.angle_to(_pose[v.rig.bones.left_leg[0]].rotation)))
	check(v.rig.locomotion_report.speed > 2.0 and v.rig.locomotion_report.gait > 0.5 and swing > 10.0, "Unarmed it walks: the gait follows the speed (%.1f m/s) and the legs swing (%.0f degrees)" % [v.rig.locomotion_report.speed, swing])
	var hands_walking := absf(_world(v, v.rig.bones.right_arm[2]).y - _world(v, v.rig.bones.right_arm[0]).y)
	check(hands_walking > 0.3, "...with the arms still hanging while it walks (%.2f m below the shoulder)" % hands_walking)
	v.face_world_position(v.global_position + Vector3(-4, 0, -2))
	check(absf(v.rig._twist) > 1.0, "A turn shows the hips catching up (twist %.0f degrees)" % v.rig._twist)

	# ---- Posture: crouch and kneel carry the body and the arms down with them.
	await _frames(30)
	var standing_hand := _world(v, v.rig.bones.right_arm[2]).y - v.global_position.y
	v.presenter.postures.set_posture(&"test/posture", PresentationTypes.Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.0, 0.40)
	await _frames(40)
	var crouched_hand := _world(v, v.rig.bones.right_arm[2]).y - v.global_position.y
	check(v.rig.crouch_modifier.depth > 0.3 and crouched_hand < standing_hand - 0.15, "Crouched, the body lowers and the hanging hands go with it (%.2f to %.2f m)" % [standing_hand, crouched_hand])
	v.presenter.postures.set_posture(&"test/posture", PresentationTypes.Posture.KNEEL, PresentationTypes.PRIORITY_CONTEXT, 0.0, v.rig.crouch_modifier.max_depth + CharacterRig.KNEEL_BLEND_RANGE)
	await _frames(60)
	check(v.rig.crouch_modifier.kneel > 0.9, "Kneeling works unarmed (kneel %.2f)" % v.rig.crouch_modifier.kneel)
	v.presenter.postures.release(&"test/posture")
	await _frames(60)

	# ---- Weapon requests are safe and change nothing.
	v.request_readiness(&"test", WeaponReadiness.Level.AIMED)
	v.present_aim()
	await _frames(40)
	check(v.rig.aim_blend == 0.0 and v.readiness_level() == WeaponReadiness.Level.STOWED and not v.presenter.aim.held, "An aim request is ignored safely: nothing is raised (blend %.2f, level %s)" % [v.rig.aim_blend, v.readiness_level()])
	v.release_readiness(&"test")
	var attack := v.present_attack(v.global_position + Vector3(0, 0, 6))
	check(attack.is_done() and attack.outcome == SKIPPED and attack.shot.outcome == SKIPPED and not v.presenter.attack.is_active() and v.get_presentation_state() != &"shoot", "An attack request shows nothing (SKIPPED, no shot clip): its result was gameplay's")
	v.rig.stow_weapon()
	v.rig.unstow_weapon()
	check(v.rig.equipment_state() == PresentationTypes.EquipmentState.NONE, "Stowing and unstowing with no weapon are no-ops")

	# ---- A ladder: the legs and trunk are posed and the hands take the rungs, from the hanging pose.
	v.rig.begin_traversal(&"ladder", 3.0, 1)
	var best_hold := 0.0
	var hand_on_rung := INF
	for i in 120:
		v.rig.set_traversal_progress(clampf(float(i) * 0.022, 0.0, 2.6))
		await process_frame
		if v.rig.ladder.pose != null:
			best_hold = maxf(best_hold, v.rig.ladder.pose.hand_weight[1])
			if v.rig.ladder.pose.hand_weight[1] > 0.95:
				hand_on_rung = minf(hand_on_rung, _world(v, v.rig.bones.right_arm[2]).distance_to(v.rig.character_root.to_global(v.rig.ladder.pose.hands[1])))
	check(v.rig.leg_ik.active and best_hold > 0.95 and hand_on_rung < 0.25, "Climbing unarmed the hands reach the rungs (hold %.2f, wrist %.2f m from the contact)" % [best_hold, hand_on_rung])
	v.rig.end_traversal()
	await _frames(20)
	check(v.rig.ladder == null and not v.rig.leg_ik.active and v.rig.grip_modifier.contact_weight == [CharacterRig.HANGING_HAND_WEIGHT, CharacterRig.HANGING_HAND_WEIGHT] and (v.rig.grip_modifier.contact_forward[0] as Vector3).y < -0.5 and (v.rig.grip_modifier.contact_forward[1] as Vector3).y < -0.5 and v.rig.crouch_modifier.aim_lean_degrees == 0.0,
		"Leaving the ladder leaves nothing of it: the hands are back to hanging (a neutral wrist, fingers down the arm), not held to the rungs")
	var model := StairModel.from_links(Vector3.ZERO, Vector3(0, 0, 1), 1.0, 1.0, 2, 3)
	v.rig.begin_stairs(model, true)
	for i in 60:
		v.update_locomotion(Vector3(0, 0, 1.2), 1.0 / 60.0)
		v.rig.set_stair_progress(clampf(float(i) * 0.015, 0.0, model.end_s()), 1.2)
		await process_frame
	check(v.rig.stairs != null and v.rig.stairs.pose != null and v.rig.leg_ik.active, "Stairs work unarmed")
	v.rig.end_stairs()

	# ---- Hit and defeat.
	var hit := v.present_hit()
	var hit_seen := _watch(hit)
	await _frames(60)
	check(hit_seen == [COMPLETED], "A hit plays and returns to idle (COMPLETED once)")

	# ---- Rescue as a carrier with no rifle, and the carried body.
	v.preview_carrying = true
	var lift := v.rig.begin_pickup(v.rig.character_root.global_position + v.rig.character_root.global_basis.orthonormalized().z)
	var lift_seen := _watch(lift)
	v.rig.rescue_interaction.scrub(v.rig.rescue_interaction.duration() - 0.05)
	await _frames(10)
	check(lift_seen == [COMPLETED] and is_instance_valid(v.rig.carry_passenger) and v.rig.carry_contacts_active() and v.rig.equipment_state() == PresentationTypes.EquipmentState.NONE, "An unarmed carrier lifts a passenger: the lift completes and the hands take the limbs, equipment still NONE")
	var hand_to_contact := _world(v, v.rig.bones.right_arm[2]).distance_to(v.rig.carry_contact_report[0].point) if not v.rig.carry_contact_report.is_empty() and v.rig.carry_contact_report[0].has("point") else 9.9
	check(hand_to_contact < 0.3, "...the right hand is at the passenger's wrist (%.2f m)" % hand_to_contact)
	var release := v.rig.begin_release()
	var release_seen := _watch(release)
	v.rig.rescue_interaction.scrub(v.rig.rescue_interaction.duration() - 0.05)
	await _frames(10)
	check(release_seen == [COMPLETED] and not is_instance_valid(v.rig.carry_passenger) and not v.presenter.postures.has_request(CharacterRig.RESCUE_POSTURE_SOURCE), "...and sets it down: COMPLETED, no passenger, no posture request left")
	v.preview_carrying = false

	# ---- Defeat, then teardown with nothing outstanding.
	var defeat := v.present_defeat()
	var defeat_seen := _watch(defeat)
	var presenter := v.presenter
	stage.queue_free()
	await _frames(3)
	check(defeat_seen == [INTERRUPTED] and presenter.postures.request_count() == 0 and not presenter.attack.is_active(), "Removing the character mid-defeat interrupts its handle and leaves no request behind")

	await _equipped_states()
	await _unarmed_unit()

	print("Unarmed humanoid: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## The equipped MIRA still reports what is true: HELD in the hands, SLUNG when carried or stowed.
func _equipped_states() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var v: TacticalCharacterAdapter = VISUAL.instantiate()
	stage.add_child(v)
	await _frames(15)
	check(v.rig.has_weapon() and v.rig.equipment_state() == PresentationTypes.EquipmentState.HELD and v.presenter.intent().equipment == PresentationTypes.EquipmentState.HELD, "Equipped MIRA: the rifle is HELD")
	v.rig.stow_weapon()
	check(v.rig.equipment_state() == PresentationTypes.EquipmentState.SLUNG and v.presenter.intent().equipment == PresentationTypes.EquipmentState.SLUNG, "...SLUNG once stowed")
	v.rig.unstow_weapon()
	check(v.rig.equipment_state() == PresentationTypes.EquipmentState.HELD, "...and HELD again")
	var attack := v.present_attack(v.global_position + Vector3(0, 0, 6))
	check(not attack.is_done(), "...and an attack from her is shown as before (a raise is pending)")
	v.presenter.attack.cancel()
	stage.queue_free()
	await _frames(2)

## A production tactical unit with no weapon: the tactical calls are safe and its removal lifecycle is unchanged.
func _unarmed_unit() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var unit := UNIT_SCENE.instantiate() as TacticalUnit
	unit.show_world_hud = false
	unit.visual_adapter.rig.weapon_scene = null
	stage.add_child(unit)
	await _frames(10)
	var adapter := unit.visual_adapter
	check(not adapter.rig.has_weapon() and adapter.rig.equipment_state() == PresentationTypes.EquipmentState.NONE, "A production unit built unarmed has no weapon")
	var attack: AttackHandle = unit.present_attack(unit.global_position + Vector3(0, 0, 6))
	unit.present_aim()
	unit.tactical_state.establish_aim()
	await _frames(20)
	check(attack.outcome == SKIPPED and adapter.rig.aim_blend == 0.0, "Its attack and aim presentations are skipped safely")
	unit.visual_adapter.present_hit()
	await _frames(5)
	var defeat := adapter.present_defeat()
	var removal := adapter.presenter.removal_handle(TacticalUnit.DEFEAT_REMOVAL_SECONDS)
	var removal_seen := _watch(removal)
	unit.finish_defeat_presentation()
	var started := Time.get_ticks_msec()
	while is_instance_valid(unit) and Time.get_ticks_msec() - started < 5000:
		await process_frame
	check(not is_instance_valid(unit) and removal_seen == [COMPLETED] and defeat.outcome == COMPLETED, "A defeated unarmed unit is removed after its defeat and the tactical floor")
	stage.queue_free()
	await _frames(2)
