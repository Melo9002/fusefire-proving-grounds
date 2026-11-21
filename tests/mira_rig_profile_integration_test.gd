extends SceneTree
## Passive rig-profile integration (Task 07 package 1): the production MIRA visual carries her profile, resolves it ONCE on build with no errors, and the resolved anatomy agrees with what the rig
## and the tuned constants already use. Passive means behaviour is unchanged: clearing the profile must give identical rig measurements and the same modifier stack.
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
	check(v.rig_profile != null, "The production MIRA scene assigns her rig profile")
	var r = v.resolved_rig
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
	# Passive: the same character without a profile builds the same rig.
	var plain: UnitVisualAdapter = VISUAL.instantiate()
	plain.rig_profile = null
	root.add_child(plain)
	await process_frame
	check(plain.resolved_rig == null, "Without a profile nothing is resolved")
	var a := v.skeleton.get_children().filter(func(c): return c is SkeletonModifier3D).map(func(c): return String(c.name))
	var b := plain.skeleton.get_children().filter(func(c): return c is SkeletonModifier3D).map(func(c): return String(c.name))
	check(a == b, "The modifier stack is identical with and without the profile")
	check(v.skeleton.get_bone_count() == plain.skeleton.get_bone_count() and v.character_scale == plain.character_scale, "The rig is otherwise identical")
	print("MIRA rig profile integration: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
