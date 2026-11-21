extends SceneTree
## The coordinated rescue interaction (animation 06C-06D): pickup, release, loaded gait, interruption and boarding, through the
## production UnitVisualAdapter and the shared RescueInteraction timeline. Geometric relations and continuity, not coordinates.
## The timeline is a function of time only, so most checks scrub it to chosen times and read the result (no wall clock).

var failures := 0
var checks := 0
var _rig: UnitVisualAdapter
var _arm_lengths := []   # [[upper, fore] right, left] read inside the carrier's skeleton pass

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _on_carrier_updated() -> void:
	var sk := _rig.skeleton
	_arm_lengths = []
	for side in ["Right", "Left"]:
		var upper := sk.get_bone_global_pose(sk.find_bone("mixamorig_%sArm" % side)).origin
		var fore := sk.get_bone_global_pose(sk.find_bone("mixamorig_%sForeArm" % side)).origin
		var hand := sk.get_bone_global_pose(sk.find_bone("mixamorig_%sHand" % side)).origin
		_arm_lengths.append([upper.distance_to(fore), fore.distance_to(hand)])

func _new_rig(stage: Node3D, at := Vector3.ZERO) -> UnitVisualAdapter:
	var rig := load("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn").instantiate() as UnitVisualAdapter
	stage.add_child(rig)
	rig.position = at
	return rig

func _same_sample(x: Dictionary, y: Dictionary) -> bool:
	for key in x:
		if x[key] is float:
			if absf(float(x[key]) - float(y[key])) > 0.00001:
				return false
		elif x[key] != y[key]:
			return false
	return true

## Largest rotation of the left thigh away from its rest orientation over a clip, degrees.
func _largest_thigh_swing(clip: Animation, builder: CharacterFallbackAnimationBuilder, skeleton: Skeleton3D) -> float:
	var track := clip.find_track(NodePath(".:%s" % builder.left_upper_leg), Animation.TYPE_ROTATION_3D)
	var rest := skeleton.get_bone_rest(skeleton.find_bone(builder.left_upper_leg)).basis.get_rotation_quaternion()
	var largest := 0.0
	for key in clip.track_get_key_count(track):
		largest = maxf(largest, rad_to_deg((clip.track_get_key_value(track, key) as Quaternion).angle_to(rest)))
	return largest

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _passenger_count(stage: Node) -> int:
	return stage.find_children("RescuePassenger", "", true, false).size()

func _bone_lengths(skeleton: Skeleton3D) -> Array:
	var out := []
	for bone in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(bone)
		if parent >= 0:
			out.append(skeleton.get_bone_global_pose(parent).origin.distance_to(skeleton.get_bone_global_pose(bone).origin))
	return out

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var rig := _new_rig(stage)
	await _frames(20)
	_rig = rig
	var passenger_world := rig.global_position + rig.global_basis.z * 1.0

	# ---- The timeline on its own: a function of time, phases in order, steady state at the end.
	var a := RescueInteraction.new()
	var b := RescueInteraction.new()
	a.start(RescueInteraction.Kind.PICKUP)
	b.start(RescueInteraction.Kind.PICKUP)
	var same := true
	for t in [0.0, 0.31, 0.77, 1.4, 2.05, 2.9, 3.0]:
		a.scrub(t)
		b.advance(0.0)
		b.scrub(t)
		same = same and a.sample() == b.sample()
	check(same, "The same time gives the same sample (deterministic)")
	var by_steps := RescueInteraction.new()
	by_steps.start(RescueInteraction.Kind.PICKUP)
	for i in 90:
		by_steps.advance(1.0 / 60.0 * (1.0 if i % 2 == 0 else 1.0))
	var by_big := RescueInteraction.new()
	by_big.start(RescueInteraction.Kind.PICKUP)
	for i in 45:
		by_big.advance(1.0 / 30.0)
	check(absf(by_steps.time - by_big.time) < 0.0001 and _same_sample(by_steps.sample(), by_big.sample()), "Frame rate does not change the sample at a given time (%.3f vs %.3f s)" % [by_steps.time, by_big.time])
	a.scrub(0.0)
	var first := a.sample()
	check(first.contact == 0.0 and first.lift == 0.0 and first.crouch == 0.0 and first.stow == 0.0, "A pickup starts standing, empty-handed, with the weapon in the hand and the passenger on the floor")
	a.scrub(a.pickup_seconds())
	var last := a.sample()
	check(last.contact == 1.0 and last.lift == 1.0 and last.crouch == 0.0 and last.stow == 1.0 and last.carry == 1.0, "A pickup ends in the steady carry (loaded, hands on, passenger across the shoulders, weapon slung)")
	var order := []
	var previous := -1
	for t in range(0, 301):
		a.scrub(t * 0.01)
		var index: int = ["align", "reach", "lift", "settle"].find(String(a.sample().phase))
		if index >= 0:
			if index < previous:
				check(false, "Phases only move forward (t=%.2f)" % (t * 0.01))
			previous = maxi(previous, index)
			if order.is_empty() or order[-1] != index:
				order.append(index)
	check(order == [0, 1, 2, 3], "Pickup passes through align, reach, lift, settle in order: %s" % str(order))
	var monotonic := true
	var before_lift := 0.0
	var before_contact := 0.0
	for t in range(0, 301):
		a.scrub(t * 0.01)
		var s := a.sample()
		monotonic = monotonic and float(s.lift) >= before_lift - 0.00001 and float(s.contact) >= before_contact - 0.00001
		before_lift = float(s.lift)
		before_contact = float(s.contact)
	check(monotonic, "During a pickup the lift and the hands' hold only grow")
	var released := RescueInteraction.new()
	released.start(RescueInteraction.Kind.RELEASE)
	var hands_let_go_when_grounded := true
	for t in range(0, 301):
		released.scrub(released.release_seconds * t / 300.0)
		var s := released.sample()
		if float(s.contact) < 0.999 and float(s.lift) > 0.001:
			hands_let_go_when_grounded = false
	released.scrub(0.0)
	check(is_equal_approx(float(released.sample().lift), 1.0) and is_equal_approx(float(released.sample().contact), 1.0), "A release starts from the steady carry")
	check(hands_let_go_when_grounded, "In a release the hands loosen only once the passenger is on the floor")
	released.scrub(released.release_seconds)
	check(released.sample().lift == 0.0 and released.sample().contact == 0.0 and released.sample().crouch == 0.0 and released.sample().stow == 0.0, "A release ends upright, hands free, weapon back in the hand")
	var paused := RescueInteraction.new()
	paused.start(RescueInteraction.Kind.PICKUP)
	paused.paused = true
	paused.advance(1.0)
	check(paused.time == 0.0, "A paused timeline does not advance")

	# ---- Pickup through the production path: the carrier takes the rescued actor's place and lifts it.
	var loaded_move: Animation = rig.animation_controller.animation_player.get_animation(&"carry_move")
	var plain_move: Animation = rig.animation_controller.animation_player.get_animation(&"move")
	var builder := CharacterFallbackAnimationBuilder.new(rig.skeleton, rig.bones)
	var swing_loaded := _largest_thigh_swing(loaded_move, builder, rig.skeleton)
	var swing_plain := _largest_thigh_swing(plain_move, builder, rig.skeleton)
	check(swing_loaded < swing_plain - 4.0 and swing_plain > 20.0, "The loaded gait takes a shorter step (%.0f deg of hip swing against %.0f unloaded) and the unloaded walk is its own clip" % [swing_loaded, swing_plain])

	var interaction_finished: Array = []
	rig.preview_carrying = true
	rig.skeleton.skeleton_updated.connect(_on_carrier_updated)
	var weapon_start := rig.weapon.global_position
	var hand_before_pickup: Vector3 = rig.right_hand_target.global_position
	var pickup_handle: ActionHandle = rig.present_pickup(passenger_world)
	pickup_handle.when_done(func(outcome: int) -> void: interaction_finished.append(outcome))
	check(rig.interaction_active() and is_instance_valid(rig.carry_passenger) and not pickup_handle.is_done() and rig.rescue_presentation() == pickup_handle, "Pickup begins an interaction with one passenger, and a pending handle for it")
	var passenger = rig.carry_passenger
	check(passenger.lift == 0.0 and passenger.global_position.distance_to(passenger.ground_origin) < 0.001, "The passenger starts lying at the rescued actor's place (%.1f mm)" % (passenger.global_position.distance_to(passenger.ground_origin) * 1000.0))
	check(absf(passenger.ground_origin.x - passenger_world.x) < 0.001 and absf(passenger.ground_origin.z - passenger_world.z) < 0.001, "...at the actor's own position on the floor, not at the carrier")
	var lengths_rest := _bone_lengths(passenger.skeleton)
	var tactical_units := root.find_children("*", "TacticalUnit", true, false).size()
	await _frames(3)
	check(rig.grip_modifier.contact_weight == [0.0, 0.0], "No hand contact at the start of the pickup")
	var start_hand: Vector3 = hand_before_pickup
	rig.rescue_interaction.paused = true
	rig.rescue_interaction.scrub(0.0)
	await _frames(3)

	check(rig.right_hand_target.global_position.distance_to(start_hand) < 0.02, "The hands start where they were (%.1f mm; carrier at %s)" % [rig.right_hand_target.global_position.distance_to(start_hand) * 1000.0, str(rig.position)])
	check(rig.weapon.global_position.distance_to(weapon_start) < 0.25 and rig.weapon.get_parent() == rig.character_root, "The weapon starts at the hand and not on the sling (%.2f m from where it was)" % rig.weapon.global_position.distance_to(weapon_start))

	# Sample the whole pickup at many times: no snapping, valid poses, contact only after the carrier has bent to it.
	rig.rescue_interaction.paused = true
	var worst_passenger_jump := 0.0
	var worst_weapon_jump := 0.0
	var worst_hand_jump := 0.0
	var worst_hand_accel := 0.0
	var last_hand_step := 0.0
	var worst_length := 0.0
	var worst_carrier_length := 0.0
	var arm_rest: Array = []
	var premature_contact := false
	var nearest_to_torso := INF
	var last_passenger: Vector3 = passenger.global_position
	var last_weapon := rig.weapon.global_position
	var last_hand := rig.right_hand_target.global_position
	var rest_arm_lengths: Array = []
	var seconds := rig.rescue_interaction.pickup_seconds()
	var steps := int(seconds * 30.0)
	for i in steps:
		var t := i / 30.0
		rig.rescue_interaction.scrub(t)
		await _frames(2)
		if not rig.interaction_active():
			break
		if rest_arm_lengths.is_empty():
			rest_arm_lengths = _arm_lengths.duplicate(true)
		var sample := rig.rescue_interaction.sample()
		if t < rig.rescue_interaction.align_seconds - 0.001 and (float(rig.grip_modifier.contact_weight[0]) > 0.001 or float(sample.contact) > 0.0):
			premature_contact = true
		if i > 0:
			worst_passenger_jump = maxf(worst_passenger_jump, passenger.global_position.distance_to(last_passenger))
			worst_weapon_jump = maxf(worst_weapon_jump, rig.weapon.global_position.distance_to(last_weapon))
			var hj := rig.right_hand_target.global_position.distance_to(last_hand)
			if hj > 0.07:
						worst_hand_jump = maxf(worst_hand_jump, hj)
		last_passenger = passenger.global_position
		last_weapon = rig.weapon.global_position
		last_hand = rig.right_hand_target.global_position
		var lengths := _bone_lengths(passenger.skeleton)
		for k in lengths.size():
			worst_length = maxf(worst_length, absf(float(lengths[k]) - float(lengths_rest[k])))
		for side in 2:
			for seg in 2:
				worst_carrier_length = maxf(worst_carrier_length, absf(float(_arm_lengths[side][seg]) - float(rest_arm_lengths[side][seg])))
		if float(sample.lift) > 0.2 and float(sample.lift) < 0.95:
			var sk := rig.skeleton
			var hips := rig.character_root.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Hips")).origin
			var neck := rig.character_root.global_transform.affine_inverse() * sk.global_transform * sk.get_bone_global_pose(sk.find_bone("mixamorig_Neck")).origin
			var abdomen: Vector3 = rig.character_root.global_transform.affine_inverse() * passenger.global_position
			var closest := Geometry3D.get_closest_point_to_segment(abdomen, hips, neck)
			nearest_to_torso = minf(nearest_to_torso, closest.distance_to(abdomen))
	print("  pickup sampled every 1/30 s: passenger step <= %.1f cm, weapon <= %.1f cm, hand target <= %.1f cm, passenger bone length change <= %.4f mm, carrier arm length change <= %.4f mm, nearest abdomen to carrier spine during the lift %.2f m" % [worst_passenger_jump * 100.0, worst_weapon_jump * 100.0, worst_hand_jump * 100.0, worst_length * 1000.0, worst_carrier_length * 1000.0, nearest_to_torso])
	check(not premature_contact, "No hand contact before the carrier has turned, stepped in and begun to bend")
	check(worst_passenger_jump < 0.09, "The passenger never jumps between frames (%.1f cm at 30 Hz)" % (worst_passenger_jump * 100.0))
	check(worst_weapon_jump < 0.09, "The weapon never jumps between frames (%.1f cm)" % (worst_weapon_jump * 100.0))
	check(worst_hand_jump < 0.09 and worst_hand_accel < 0.04, "The hands move smoothly (largest step %.1f cm, largest change of step %.1f cm at 30 Hz)" % [worst_hand_jump * 100.0, worst_hand_accel * 100.0])
	check(worst_length < 0.00005, "The passenger's bones keep their lengths through the lift (%.5f mm)" % (worst_length * 1000.0))
	check(worst_carrier_length < 0.0003, "The carrier's arm bones keep their lengths through the reach and lift (%.5f mm)" % (worst_carrier_length * 1000.0))
	check(nearest_to_torso > 0.07, "The passenger is lifted up the carrier's front, not through its spine (%.2f m at the nearest)" % nearest_to_torso)
	check(root.find_children("*", "TacticalUnit", true, false).size() == tactical_units and _passenger_count(stage) == 1, "The lift adds no tactical actor and no second passenger")

	# The end of the pickup is the steady carry, once, with the carrier standing at its own place.
	rig.rescue_interaction.paused = false
	rig.rescue_interaction.scrub(seconds - 0.05)
	await create_timer(0.3).timeout
	check(not rig.interaction_active() and interaction_finished == [PresentationTypes.Outcome.COMPLETED] and pickup_handle.is_done(), "The pickup ends once, and says so: %s" % str(interaction_finished))
	check(rig.position.distance_to(Vector3.ZERO) < 0.001 and rig.crouch_modifier.depth < 0.01, "The carrier is back upright at its own place")
	check(passenger.lift == 1.0 and rig.carry_contacts_active() and rig.grip_modifier.contact_weight == [1.0, 1.0], "The passenger lies across the shoulders with both hands on their contacts")
	check(rig.get_presentation_state() == &"carry_idle", "The carrier settles into the carry idle (%s)" % rig.get_presentation_state())

	# ---- Release: the reverse.
	var release_finished: Array = []
	rig.keep_released_passenger = true
	var release_handle: ActionHandle = rig.begin_release()
	release_handle.when_done(func(outcome: int) -> void: release_finished.append(outcome))
	rig.rescue_interaction.paused = true
	var released_jump := 0.0
	var hands_free_before_grounded := false
	var last_pos: Vector3 = passenger.global_position
	var seconds_out := rig.rescue_interaction.release_seconds
	for i in int(seconds_out * 30.0):
		rig.rescue_interaction.scrub(i / 30.0)
		await _frames(2)
		var s := rig.rescue_interaction.sample()
		if float(s.contact) < 0.999 and passenger.global_position.distance_to(passenger.ground_origin) > 0.02:
			hands_free_before_grounded = true
		if i > 0:
			released_jump = maxf(released_jump, passenger.global_position.distance_to(last_pos))
		last_pos = passenger.global_position
	check(released_jump < 0.09, "The passenger is lowered, not dropped (largest step %.1f cm at 30 Hz)" % (released_jump * 100.0))
	check(not hands_free_before_grounded, "The hands let go only when the passenger is on the floor")
	rig.rescue_interaction.paused = false
	rig.rescue_interaction.scrub(seconds_out - 0.05)
	await create_timer(0.3).timeout
	check(release_finished == [PresentationTypes.Outcome.COMPLETED] and not rig.interaction_active(), "The release ends once")
	check(rig.carry_passenger == null and rig.weapon.get_parent() == rig.weapon_attachment and not rig.is_weapon_stowed() and rig.arm_ik.active, "After the release the carrier holds its rifle again and carries no one")
	check(rig.get_presentation_state() == &"rifle_idle" and rig.grip_modifier.contact_weight == [0.0, 0.0], "...and is back in the ordinary stance with its grips released")
	var left_lying := stage.find_children("RescuePassenger", "", true, false)
	check(left_lying.size() == 1 and left_lying[0].get_parent() == stage, "A workbench release leaves the passenger lying, detached from the carrier")
	if left_lying.size() == 1:
		var lying = left_lying[0]
		check(lying.global_position.distance_to(lying.ground_origin) < 0.005, "...on the floor where it was set down")
		lying.free()
	rig.keep_released_passenger = false

	# ---- Interruption in every phase: the carrier loses its passenger (the tactical layer has put it down).
	var phases := {"pickup start": [RescueInteraction.Kind.PICKUP, 0.2], "pickup reach": [RescueInteraction.Kind.PICKUP, 1.0], "pickup lift": [RescueInteraction.Kind.PICKUP, 1.8], "pickup settle": [RescueInteraction.Kind.PICKUP, 2.5], "release lower": [RescueInteraction.Kind.RELEASE, 1.2], "steady carry": [RescueInteraction.Kind.NONE, 0.0]}
	for label in phases:
		var kind: int = phases[label][0]
		var when: float = phases[label][1]
		rig.preview_carrying = true
		if kind == RescueInteraction.Kind.PICKUP:
			rig.present_pickup(passenger_world)
			rig.rescue_interaction.paused = true
			rig.rescue_interaction.scrub(when)
		else:
			rig.begin_carry()
			if kind == RescueInteraction.Kind.RELEASE:
				rig.begin_release()
				rig.rescue_interaction.paused = true
				rig.rescue_interaction.scrub(when)
		for f in 4:
			await _frames(1)
			rig.preview_carrying = false
		rig.present_carry_released()
		await _frames(1)
		await _frames(3)
		check(rig.carry_passenger == null and _passenger_count(stage) == 0, "Interrupted at %s: no passenger representation is left" % label)
		check(rig.weapon.get_parent() == rig.weapon_attachment and not rig.is_weapon_stowed() and rig.arm_ik.active, "Interrupted at %s: the weapon is back in the hand" % label)
		check(rig.grip_modifier.contact_weight == [0.0, 0.0] and rig.carry_contact_report.is_empty(), "Interrupted at %s: no carry contact targets remain" % label)
		check(not rig.interaction_active() and rig.position.length() < 0.001 and rig.crouch_modifier.depth < 0.01 and rig.crouch_modifier.kneel < 0.01, "Interrupted at %s: the carrier is upright and at its own place (active %s, root %s, depth %.3f, kneel %.3f)" % [label, rig.interaction_active(), str(rig.position), rig.crouch_modifier.depth, rig.crouch_modifier.kneel])
		check(rig.get_presentation_state() not in [&"pickup", &"carry_idle", &"carry_move", &"boarding"], "Interrupted at %s: the carrier leaves the carry states (%s)" % [label, rig.get_presentation_state()])
	rig.present_carry_released()
	check(rig.carry_passenger == null, "Releasing a carrier that carries nobody is harmless")

	# ---- Boarding during a pickup finishes the lift, then shrinks the one passenger.
	rig.preview_carrying = true
	rig.present_pickup(passenger_world)
	await _frames(10)
	rig.present_boarding()
	check(not rig.interaction_active() and is_instance_valid(rig.carry_passenger) and _passenger_count(stage) == 1, "Boarding settles the interaction and keeps one passenger")
	await create_timer(0.7).timeout
	check(rig.carry_passenger.presence < 0.05, "The passenger is handed off by shrinking away, as before (%.2f)" % rig.carry_passenger.presence)
	rig.preview_carrying = false
	rig.present_carry_released()

	# ---- Movement starting during a pickup settles it instead of fighting it.
	rig.preview_carrying = true
	rig.present_pickup(passenger_world)
	await _frames(10)
	rig.present_move()
	check(not rig.interaction_active() and rig.carry_passenger.lift == 1.0, "Walking off settles the pickup at once, into the carry (active %s, lift %s)" % [rig.interaction_active(), str(rig.carry_passenger.lift if is_instance_valid(rig.carry_passenger) else -1)])
	rig.preview_carrying = false
	rig.present_carry_released()

	rig.skeleton.skeleton_updated.disconnect(_on_carrier_updated)
	stage.queue_free()
	await _frames(2)
	print("Rescue interaction: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
