extends SceneTree
## Independent passenger identity (animation assignment), at the rig level for every carrier/passenger pairing: a passenger is described apart from the carrier, built from its OWN scene, scale and rig profile, keeps that
## identity through the lift, the carry, the release and the next lift, and is never resized, replaced or duplicated; a body of another size is fitted to its carrier (floor clearance and reach); and callers that name no
## passenger get the carrier's own kind, exactly as before. Negative controls show the checks can fail (a passenger derived from its carrier; the fit switched off).
const SCENE := "res://tools/animation_workbench/pose_workbench.tscn"
const IDS: Array[StringName] = [&"mira_0", &"small_mira_0"]
const GROUND_CLEARANCE_M := 0.10
const REACH_LIMIT := 0.97

var failures := 0
var checks := 0


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


func _bench(carrier: StringName) -> Node3D:
	WorkbenchSession.character = carrier
	WorkbenchSession.passenger = &""
	WorkbenchSession.armed = false
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var bench: Node3D = (load(SCENE) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(10)
	return bench


## The body's standing height as its own model has it (rest pose, head top to floor, scale included), measured from a fresh instance of the definition's scene: what the carried body must still be.
func _own_height(definition: PassengerDefinition) -> float:
	var model := definition.scene.instantiate() as Node3D
	model.scale = Vector3.ONE * definition.scale
	root.add_child(model)
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	var bones := RigBones.from_profile(definition.rig_profile, skeleton)
	var height := (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(bones.head_top)).origin).y - (skeleton.global_transform * skeleton.get_bone_global_rest(skeleton.find_bone(bones.hips)).origin).y
	model.free()
	return height


func _carried_height(passenger: Node3D) -> float:
	var skeleton: Skeleton3D = passenger.skeleton
	var rest := skeleton.get_bone_global_rest(skeleton.find_bone(passenger.bones.head_top)).origin.y - skeleton.get_bone_global_rest(skeleton.find_bone(passenger.bones.hips)).origin.y
	return rest * skeleton.global_basis.get_scale().y


func _passengers_under(rig: CharacterRig) -> int:
	return rig.character_root.get_children().filter(func(node: Node) -> bool: return node.get_script() != null and str(node.get_script().resource_path).ends_with("rescue_passenger.gd")).size()


func _run() -> void:
	_definitions()
	for carrier in IDS:
		for passenger in IDS:
			await _pairing(carrier, passenger)
	await _default_is_the_carriers_own_kind()
	await _lifecycle()
	await _controls()
	print("passenger_identity_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)


func _definitions() -> void:
	var found := PassengerDefinition.known_characters()
	check(found.has(&"mira_0") and found.has(&"small_mira_0"), "Every character with a runtime rig scene is known (%s)" % [found])
	check(PassengerDefinition.for_character(&"no_such_character") == null, "An unknown character is not made up")
	var regular := PassengerDefinition.for_character(&"mira_0")
	var small := PassengerDefinition.for_character(&"small_mira_0")
	check(regular != null and small != null and regular != small, "Each character has its own definition")
	check(PassengerDefinition.for_character(&"mira_0") == regular, "and it is resolved once and remembered (no rebuilding per call)")
	check(regular.scene != null and regular.rig_profile != null and small.scene != null and small.rig_profile != null, "Each carries its own model scene and rig profile")
	check(regular.scale > small.scale and regular.scene != small.scene and regular.rig_profile != small.rig_profile, "The two bodies differ in scale (%.2f, %.2f), model and profile" % [regular.scale, small.scale])
	check(regular.character_id == &"mira_0" and small.character_id == &"small_mira_0", "and in identity")
	check(PassengerDefinition.id_from_path("res://art/characters/small_mira_0/runtime/small_mira_0_rig.tscn") == &"small_mira_0", "A character id comes from the project's own folder layout")


func _pairing(carrier: StringName, passenger: StringName) -> void:
	var label := "%s carries %s" % [carrier, passenger]
	var bench := await _bench(carrier)
	var rig: CharacterRig = bench.rig
	var definition := PassengerDefinition.for_character(passenger)
	rig.passenger_definition = definition
	rig.begin_carry()
	rig.animation_controller.play(&"carry_idle")
	await _frames(50)
	var body: Node3D = rig.carry_passenger
	check(is_instance_valid(body) and body.definition == definition, "%s: the carried body is the chosen definition" % label)
	var model: Node3D = body.find_child("PassengerModel", true, false)
	check(is_equal_approx(model.scale.x, definition.scale), "%s: at its own scale (%.2f), not resized to the carrier's (%.2f)" % [label, model.scale.x, rig.character_scale])
	check(absf(_carried_height(body) - _own_height(definition)) < 0.01, "%s: with its own proportions (%.3f m against %.3f m)" % [label, _carried_height(body), _own_height(definition)])
	check(body.bones != null and body.bones.hips != &"" and body.bones.has_role(&"LeftUpperArm") and body.bones.has_role(&"LeftUpperLeg"), "%s: its bone roles are resolved from its own profile" % label)
	check(_passengers_under(rig) == 1, "%s: exactly one passenger under the carrier" % label)
	var same := carrier == passenger
	check(bool(rig.carry_fit.get("fitted", false)) != same, "%s: %s" % [label, "a body of the carrier's own kind keeps the authored carry" if same else "a body of another size is fitted to its carrier"])
	# The final carry: off the floor, with both hands on it.
	var lowest := INF
	var skeleton: Skeleton3D = body.skeleton
	for bone in skeleton.get_bone_count():
		lowest = minf(lowest, (skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin).y - rig.character_root.global_position.y)
	check(lowest >= GROUND_CLEARANCE_M, "%s: the whole body is clear of the floor (%.2f m)" % [label, lowest])
	for side in 2:
		var entry: Dictionary = rig.carry_contact_report[side]
		var chain: Array = rig.right_arm_bones if side == 0 else rig.left_arm_bones
		var shoulder: Vector3 = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(chain[0])).origin
		var wrist: Vector3 = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(chain[2])).origin
		var arm := rig.ladder_body().arm_length()
		check(not entry.is_empty() and wrist.distance_to(shoulder) / arm < REACH_LIMIT, "%s: the %s hand holds without a fully straight arm (%.0f%% of its reach)" % [label, "right" if side == 0 else "left", 100.0 * wrist.distance_to(shoulder) / arm])
	bench.queue_free()
	await _frames(2)


func _default_is_the_carriers_own_kind() -> void:
	for carrier in IDS:
		var bench := await _bench(carrier)
		var rig: CharacterRig = bench.rig
		check(rig.passenger_definition == null, "%s: with no passenger named, none is stored" % carrier)
		rig.begin_carry()
		await _frames(5)
		check(rig.carry_passenger.definition.is_same_body_as(rig) and rig.carry_passenger.definition.character_id == carrier, "%s: a rig that names no passenger carries its own kind, as before" % carrier)
		check(rig.carry_fit.get("fitted", true) == false, "%s: and its carry is the authored one" % carrier)
		bench.queue_free()
		await _frames(2)


## The body's identity through pickup, carry, release and the next pickup, with the node count checked at each stage.
func _lifecycle() -> void:
	var bench := await _bench(&"small_mira_0")
	var rig: CharacterRig = bench.rig
	var regular := PassengerDefinition.for_character(&"mira_0")
	var small := PassengerDefinition.for_character(&"small_mira_0")
	var lift := Vector3(0.0, 0.0, 1.0)
	var handle := rig.begin_pickup(rig.character_root.global_position + lift, null, regular)
	await _frames(5)
	check(is_instance_valid(rig.carry_passenger) and rig.carry_passenger.definition == regular, "A pickup builds the body the host named, lying where it was")
	rig.finish_interaction_now()
	check(handle.is_done() and rig.carry_passenger.definition == regular and _passengers_under(rig) == 1, "and the lift completes with that body and no second one")
	rig.keep_released_passenger = true
	rig.begin_release()
	await _frames(5)
	rig.finish_interaction_now()
	var lying: Node3D = null
	for sibling in rig.get_parent().get_parent().get_children() + rig.get_parent().get_children():
		if sibling.get_script() != null and str(sibling.get_script().resource_path).ends_with("rescue_passenger.gd"):
			lying = sibling
	check(lying != null and lying.definition == regular and not is_instance_valid(rig.carry_passenger) and _passengers_under(rig) == 0, "Put down, the body is left lying with its identity and the carrier holds none")
	rig.begin_pickup(lying.global_position, null, lying.definition)
	lying.queue_free()
	await _frames(5)
	rig.finish_interaction_now()
	check(rig.carry_passenger.definition == regular and rig.passenger_definition == regular, "Lifted again from what lay there, it is the same casualty")
	# A different casualty next time: the choice replaces, never mixes.
	rig.end_carry()
	check(not is_instance_valid(rig.carry_passenger) and _passengers_under(rig) == 0 and rig.loaded_ladder == null, "Ending the carry frees the body and leaves nothing of it")
	rig.begin_pickup(rig.character_root.global_position + lift, null, small)
	await _frames(5)
	rig.finish_interaction_now()
	check(rig.carry_passenger.definition == small and is_equal_approx(rig.carry_passenger.find_child("PassengerModel", true, false).scale.x, small.scale) and _passengers_under(rig) == 1, "The next casualty is the new one, at its own scale, alone")
	# A pickup that is cut short leaves nothing.
	rig.end_carry()
	rig.begin_pickup(rig.character_root.global_position + lift, null, regular)
	await _frames(10)
	rig.end_carry()
	check(not is_instance_valid(rig.carry_passenger) and _passengers_under(rig) == 0 and not rig.interaction_active(), "A lift cut short leaves no body and no interaction behind")
	bench.queue_free()
	await _frames(2)


func _controls() -> void:
	# A passenger derived from its carrier is the carrier's size: the check that the carried body keeps its own scale can fail.
	var bench := await _bench(&"small_mira_0")
	var rig: CharacterRig = bench.rig
	rig.passenger_definition = PassengerDefinition.from_rig(rig)
	rig.begin_carry()
	await _frames(5)
	var coupled: float = rig.carry_passenger.find_child("PassengerModel", true, false).scale.x
	check(coupled < PassengerDefinition.for_character(&"mira_0").scale - 0.1, "Negative control: a passenger described by its carrier is the carrier's size (%.2f), not the regular MIRA's" % coupled)
	bench.queue_free()
	await _frames(2)
	# The fit is what keeps a larger body off the floor: with the fit switched off the same carry drags (and the clearance check above would fail).
	bench = await _bench(&"small_mira_0")
	rig = bench.rig
	PassengerFit._cache["small_mira_0|mira_0"] = {"fitted": false, "pose": {}, "slide": Vector3.ZERO, "tuck": 1.0, "fractions": {}}
	rig.passenger_definition = PassengerDefinition.for_character(&"mira_0")
	rig.begin_carry()
	rig.animation_controller.play(&"carry_idle")
	await _frames(50)
	var lowest := INF
	var skeleton: Skeleton3D = rig.carry_passenger.skeleton
	for bone in skeleton.get_bone_count():
		lowest = minf(lowest, (skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin).y - rig.character_root.global_position.y)
	check(lowest < GROUND_CLEARANCE_M, "Negative control: without the fit a regular MIRA on Small MIRA's shoulders reaches the floor (%.2f m)" % lowest)
	PassengerFit.clear_cache()
	bench.queue_free()
	await _frames(2)
