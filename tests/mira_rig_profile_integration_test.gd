extends SceneTree
## Passive rig-profile integration (Task 07 package 1): the production MIRA visual carries her profile, resolves it ONCE on build with no errors, and the resolved anatomy agrees with what the rig
## and the tuned constants already use. Since Task 07 package 9 the profile also DRIVES the stack (the bone configuration is read from it); package 1's passive contract is retired.
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
	var v: UnitVisualAdapter = VISUAL.instantiate()
	root.add_child(v)
	await process_frame
	check(v.rig.rig_profile != null, "The production MIRA scene assigns her rig profile")
	var r = v.rig.resolved_rig
	check(r != null, "The profile was resolved when the character was built")
	if r == null:
		quit(1)
		return
	check(not r.diagnostics.has_errors(), "MIRA's profile resolves without errors against the production model")
	check(r.has_role(&"Hips") and r.has_role(&"Head") and r.has_role(&"LeftHand") and r.has_role(&"RightHand") and r.has_role(&"LeftFoot"), "The core roles resolve to bones")
	var m = r.measurements
	# The production stair constants were tuned against the measured rig: hips-to-ankle span 0.832 vs the profile's declared stair leg length 0.84.
	check(absf(m.hips_to_ankle - 0.832) < 0.02, "Profile-measured hips-to-ankle span (%.3f) agrees with the measured production value 0.832" % m.hips_to_ankle)
	var stair := StairProfile.new()
	check(absf(stair.leg_length - m.hips_to_ankle) < 0.02, "The production stair profile's leg length (%.3f) agrees with the resolved hips-to-ankle span (%.3f)" % [stair.leg_length, m.hips_to_ankle])
	# Driving (Task 07 package 9, replacing the passive contract of package 1): the profile is the ONLY source of the skeleton's bones. The rig reads its configuration from it, builds every stage, and a role the
	# resolver found is the bone the stack uses.
	check(v.rig.bones != null and v.rig.bones.profile_name == String(v.rig.rig_profile.display_name) and v.rig.bones.degraded.is_empty(), "The rig's bone configuration comes from the profile and nothing is degraded")
	var agree := true
	for pair in [[&"Hips", v.rig.bones.hips], [&"Head", v.rig.bones.head], [&"LeftHand", v.rig.bones.left_arm[2]], [&"RightFoot", v.rig.bones.right_leg[2]], [&"UpperChest", v.rig.bones.torso]]:
		agree = agree and v.rig.skeleton.get_bone_name(r.bone(pair[0])) == String(pair[1])
	check(agree, "The resolver and the stack agree on which bone plays each role")
	var stages := v.rig.skeleton.get_children().filter(func(c): return c is SkeletonModifier3D).map(func(c): return String(c.name))
	check(stages == ["Locomotion", "CoverCrouch", "Traversal", "TraversalLegIK", "WeaponPose", "WeaponArmIK", "HandGrip"], "The full modifier stack is built from the profile: %s" % [stages])
	print("MIRA rig profile integration: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
