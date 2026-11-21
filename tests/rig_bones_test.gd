extends SceneTree
## Profile-driven skeleton configuration (Task 07 package 9). RigBones turns a rig profile into the typed bone configuration the whole animation stack runs on. Checks that MIRA's profile yields EXACTLY the
## bones the code used to name itself (so her behaviour cannot have moved), that a skeleton with entirely different names and fewer bones configures the same modifiers and the passenger pose from its
## profile alone, and that a role the skeleton lacks produces a stated restriction instead of a silent failure. The production visual's numerical equivalence is the pose trace.
const Fixtures := preload("res://tests/fixtures/rigs/rig_fixtures.gd")
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _run() -> void:
	# ---- MIRA: the profile gives exactly the bones the stack used to name in code.
	var skeleton := Fixtures.mira_skeleton()
	var bones := RigBones.from_profile(Fixtures.mira_profile(), skeleton)
	var expected := {
		"hips": &"mixamorig_Hips", "spine": &"mixamorig_Spine", "chest": &"mixamorig_Spine1", "upper_chest": &"mixamorig_Spine2", "neck": &"mixamorig_Neck", "head": &"mixamorig_Head",
		"head_top": &"mixamorig_HeadTop_End", "torso": &"mixamorig_Spine2", "left_shoulder": &"mixamorig_LeftShoulder", "right_shoulder": &"mixamorig_RightShoulder",
		"left_toes": &"mixamorig_LeftToeBase", "right_toes": &"mixamorig_RightToeBase",
	}
	var wrong: Array[String] = []
	for key in expected:
		if bones.get(key) != expected[key]:
			wrong.append("%s=%s" % [key, bones.get(key)])
	check(wrong.is_empty(), "MIRA's profile yields the bones the code used to name (wrong: %s)" % [wrong])
	check(bones.left_arm == [&"mixamorig_LeftArm", &"mixamorig_LeftForeArm", &"mixamorig_LeftHand"] and bones.right_arm == [&"mixamorig_RightArm", &"mixamorig_RightForeArm", &"mixamorig_RightHand"]
			and bones.left_leg == [&"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg", &"mixamorig_LeftFoot"] and bones.right_leg == [&"mixamorig_RightUpLeg", &"mixamorig_RightLeg", &"mixamorig_RightFoot"],
		"...the arms and legs are the same chains")
	check(bones.spine_chain() == [&"mixamorig_Spine", &"mixamorig_Spine1", &"mixamorig_Spine2"] and bones.lower_spine() == [&"mixamorig_Spine", &"mixamorig_Spine1"], "...and the spine chains")
	var fingers_ok := true
	for side in ["Left", "Right"]:
		for finger in RigBones.FINGERS:
			var chain := bones.finger_chain(skeleton, side, finger)
			var mixamo_name: String = "Pinky" if finger == "Little" else finger
			for joint in 4:
				fingers_ok = fingers_ok and chain.size() == 4 and skeleton.get_bone_name(chain[joint]) == "mixamorig_%sHand%s%d" % [side, mixamo_name, joint + 1]
	check(fingers_ok and bones.absent.is_empty(), "...every finger chain is the four mixamo joints, and nothing the profile maps is missing")
	check(bones.role_of_bone(&"mixamorig_RightFoot") == &"RightFoot" and bones.role_of_bone(&"mixamorig_HeadTop_End") == &"HeadTop" and bones.role_of_bone(&"nonsense") == &"", "A bone maps back to its role")
	skeleton.free()

	# ---- A skeleton with other names, no upper chest, no toes, no fingers and no head-top bone: configured from its profile alone.
	var alt_skeleton := Fixtures.alternate_skeleton()
	root.add_child(alt_skeleton)   # the modifiers and the passenger pose read global transforms
	var alt := RigBones.from_profile(Fixtures.alternate_profile(), alt_skeleton)
	check(alt.hips == &"pelvis" and alt.torso == &"spine_02" and alt.head_top == &"head" and alt.left_toes == &"" and alt.spine_chain() == [&"spine_01", &"spine_02"] and alt.left_arm[0] == &"upperarm_l",
		"A skeleton with other names configures from its profile: the torso falls back to the chest, the head top to the head, toes are absent")
	check(alt.finger_chain(alt_skeleton, "Left", "Index").is_empty() and alt.missing_of([&"LeftToes", &"LeftIndexProximal", &"Hips"]) == [&"LeftToes", &"LeftIndexProximal"], "Roles it lacks are reported as missing, not invented")
	var grip := HandGripModifier.new()
	check(not grip.setup(alt_skeleton, alt), "The hand grip declines a skeleton with no fingers (no crash)")
	grip.free()
	var locomotion := LocomotionPoseModifier.new()
	check(locomotion.setup(alt_skeleton, alt, RigAxes.new()), "The locomotion modifier configures on that skeleton from the profile alone")
	locomotion.free()
	var crouch := CoverCrouchModifier.new()
	var crouch_ready := crouch.setup(alt_skeleton, alt, Vector3.FORWARD)
	check(crouch_ready or not crouch_ready, "The cover crouch either configures or declines on it without a crash (%s)" % crouch_ready)
	crouch.free()
	check(PassivePassengerPose.supports(alt) and PassivePassengerPose.apply(alt_skeleton, alt), "The passenger pose, written in roles, poses a skeleton with other names")
	check(PoseOwnership.role_of(alt, "upperarm_l") == &"upper_arm" and PoseOwnership.role_of(alt, "clavicle_l") == &"support_clavicle" and PoseOwnership.role_of(alt, "calf_r") == &"shin" and PoseOwnership.role_of(alt, "pelvis") == &"hips" and PoseOwnership.role_of(alt, "root") == &"",
		"Pose ownership reads a bone's role from the rig, whatever its name")
	alt_skeleton.free()

	# ---- A profile that maps a bone the skeleton does not have: the role is absent, the fallbacks apply, and a stage that needs it says so.
	var broken_skeleton := Fixtures.alternate_skeleton("spine_02")
	var broken := RigBones.from_profile(Fixtures.alternate_profile(), broken_skeleton)
	check(broken.absent.has(&"Chest") and broken.torso == &"spine_01" and broken.spine_chain() == [&"spine_01"], "A mapped bone the skeleton lacks is recorded as absent and the torso falls back to the spine (%s)" % [broken.absent])
	broken.degrade("HandGrip", broken.missing_of([&"LeftIndexProximal"]))
	broken.degrade("Traversal", [])
	check(broken.degraded == ["HandGrip is not built (missing: LeftIndexProximal)", "Traversal is not built"], "A stage that cannot run is reported with the missing role: %s" % [broken.degraded])
	broken_skeleton.free()
	var empty := RigBones.from_profile(null, null)
	check(empty.hips == &"" and empty.left_arm.is_empty() and not empty.has_role(&"Hips"), "No profile gives an empty configuration, never a guess")

	# ---- The production visual runs from its profile, with nothing missing, and no skeleton name is left in generic production code.
	var stage := Node3D.new()
	root.add_child(stage)
	var visual: TacticalCharacterAdapter = VISUAL.instantiate()
	stage.add_child(visual)
	for i in 10:
		await process_frame
	check(visual.rig.bones != null and visual.rig.bones.degraded.is_empty() and visual.rig.bones.profile_name != "" and visual.rig.crouch_modifier != null and visual.rig.locomotion_modifier != null and visual.rig.traversal_modifier != null and visual.rig.grip_modifier != null and visual.rig.weapon_pose_modifier != null,
		"The production visual builds every stage from its profile and reports nothing degraded (%s)" % [visual.rig.bones.degraded])
	stage.queue_free()
	await process_frame
	var dirs := ["presentation", "units", "systems", "art/characters"]
	var literal := RegEx.create_from_string("mixamorig|J_Bip")
	var offenders: Array[String] = []
	for dir_name in dirs:
		_scan(dir_name, literal, offenders)
	check(offenders.is_empty(), "No skeleton bone name is written in production code (the profile holds them): %s" % [offenders])

	print("Rig bones: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _scan(directory: String, pattern: RegEx, offenders: Array[String]) -> void:
	var dir := DirAccess.open("res://" + directory)
	if dir == null:
		return
	for sub in dir.get_directories():
		_scan(directory + "/" + sub, pattern, offenders)
	for file in dir.get_files():
		if file.get_extension() != "gd":
			continue
		var lines: Array[String] = []
		for line in FileAccess.get_file_as_string("res://%s/%s" % [directory, file]).split("\n"):
			var cut := line.find("#")
			lines.append(line if cut < 0 else line.substr(0, cut))
		if pattern.search("\n".join(lines)) != null:
			offenders.append("%s/%s" % [directory, file])
