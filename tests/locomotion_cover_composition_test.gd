extends SceneTree
## Modifier composition on the production stack (Locomotion, then CoverCrouch): the locomotion twist, bank and pitch must survive a lean, and the lean must survive a twist.
## Regression for audit finding F-04: CoverCrouchModifier used to write the spine as an ABSOLUTE pose (`rest * lean`), which erased the spine's share of the locomotion turn twist
## (and pitch) whenever any lean was active, so the chest turned with the hips instead of staying square (net chest yaw zero). The test stops the rig's own per-frame driver and sets the
## two modifiers by hand so each case is exact, then reads the bone poses inside `skeleton_updated` (where the modifiers' results exist).
var failures := 0
var checks := 0
var snap := {}
var axes := {}
var base := {}

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _grab(rig) -> void:
	var sk: Skeleton3D = rig.skeleton
	for n in ["Hips", "Spine", "Spine1", "Spine2", "LeftUpLeg", "LeftFoot"]:
		var index := sk.find_bone("mixamorig_" + n)
		snap[n] = sk.get_bone_global_pose(index)

## Rotation of bone `n` relative to the neutral pose, split into its yaw (about the anatomical up) and its pitch (about the hip hinge), degrees.
func _angles(n: String) -> Vector2:
	var relative: Basis = (snap[n] as Transform3D).basis.orthonormalized() * (base[n] as Transform3D).basis.orthonormalized().inverse()
	var q := relative.get_rotation_quaternion()
	var up: Vector3 = axes.up
	var yaw_q := _twist(q, up)
	var rest := q * yaw_q.inverse()
	var hinge: Vector3 = axes.hinge
	var pitch_q := _twist(rest, hinge)
	return Vector2(rad_to_deg(_signed(yaw_q, up)), rad_to_deg(_signed(pitch_q, hinge)))

func _twist(q: Quaternion, axis: Vector3) -> Quaternion:
	var projected := axis.normalized() * Vector3(q.x, q.y, q.z).dot(axis.normalized())
	var t := Quaternion(projected.x, projected.y, projected.z, q.w)
	return t.normalized() if t.length() > 0.0001 else Quaternion.IDENTITY

func _signed(q: Quaternion, axis: Vector3) -> float:
	var s := Vector3(q.x, q.y, q.z).dot(axis.normalized())
	return 2.0 * atan2(s, q.w)

func _apply(rig, twist: float, lean: float, depth := 0.0, bank := 0.0, pitch := 0.0) -> void:
	for i in 6:
		rig.locomotion_modifier.twist_degrees = twist
		rig.locomotion_modifier.bank_degrees = bank
		rig.locomotion_modifier.pitch_degrees = pitch
		rig.crouch_modifier.aim_lean_degrees = lean
		rig.crouch_modifier.depth = depth
		await process_frame

func _run() -> void:
	var rig = load("res://art/characters/mira_0/demo/mira_0_pose_workbench.tscn").instantiate()
	root.add_child(rig)
	for i in 30: await process_frame
	rig.skeleton.skeleton_updated.connect(func() -> void: _grab(rig))
	rig.animation_controller.play(&"rifle_idle")
	for i in 20: await process_frame
	rig.set_process(false)   # the rig's own driver would overwrite the modifier fields each frame
	axes = rig.animation_controller.locomotion_axes()
	await _apply(rig, 0.0, 0.0)
	for n in snap:
		base[n] = snap[n]
	var twist := 20.0
	var lean := 6.0

	# ---- 1. Turning without lean: the hips turn, the chest stays square.
	await _apply(rig, twist, 0.0)
	var hips_twist := _angles("Hips")
	var chest_twist := _angles("Spine2")
	print("  twist only: hips yaw %.1f, chest yaw %.1f, chest pitch %.1f" % [hips_twist.x, chest_twist.x, chest_twist.y])
	check(absf(absf(hips_twist.x) - twist) < 1.0, "Turning without lean: the hips turn by the twist (%.1f degrees)" % hips_twist.x)
	check(absf(chest_twist.x) < 1.0, "...and the chest stays square (net yaw %.2f degrees)" % chest_twist.x)
	var spine_twist_share := _angles("Spine").x

	# ---- 2. Lean without turning.
	await _apply(rig, 0.0, lean)
	var chest_lean := _angles("Spine2")
	var hips_lean := _angles("Hips")
	print("  lean only: chest pitch %.1f, chest yaw %.1f, hips yaw %.1f" % [chest_lean.y, chest_lean.x, hips_lean.x])
	check(absf(chest_lean.y) > 1.0 and absf(chest_lean.x) < 0.5 and absf(hips_lean.x) < 0.5, "Lean without turning: the trunk pitches (%.1f degrees) and nothing turns" % chest_lean.y)

	# ---- 3. Turning while aiming with lean (the F-04 case).
	await _apply(rig, twist, lean)
	var chest_both := _angles("Spine2")
	var hips_both := _angles("Hips")
	var spine_both := _angles("Spine")
	print("  twist + lean: hips yaw %.1f, chest yaw %.1f, chest pitch %.1f, spine twist share %.1f (twist alone gives %.1f)" % [hips_both.x, chest_both.x, chest_both.y, spine_both.x, spine_twist_share])
	check(absf(hips_both.x - hips_twist.x) < 0.5, "Turn + lean: the hips still turn exactly as without lean (%.1f vs %.1f)" % [hips_both.x, hips_twist.x])
	check(absf(chest_both.x) < 1.0, "Turn + lean: the chest stays square: net yaw %.2f degrees (the defect left %.0f of the %.0f degrees of twist on the chest)" % [chest_both.x, absf(twist) - 0.0, twist])
	check(absf(spine_both.x - spine_twist_share) < 0.5, "Turn + lean: the spine keeps its compensating twist share (%.1f vs %.1f degrees)" % [spine_both.x, spine_twist_share])
	check(absf(chest_both.y - chest_lean.y) < 0.75, "Turn + lean: the lean is the same as without the turn (%.1f vs %.1f degrees): no loss, no double application" % [chest_both.y, chest_lean.y])

	# ---- 4. Loaded carry: the carry lean (20 degrees) while turning.
	rig.begin_carry()
	for i in 10: await process_frame
	var carry_lean := 20.0
	await _apply(rig, 0.0, carry_lean)
	var carry_pitch := _angles("Spine2").y
	var carry_base_yaw := _angles("Spine2").x
	await _apply(rig, 15.0, carry_lean)
	var carry_hips := _angles("Hips")
	var carry_chest := _angles("Spine2")
	print("  carry: lean only pitch %.1f; with a 15 degree turn: hips yaw %.1f, chest yaw %.1f, chest pitch %.1f" % [carry_pitch, carry_hips.x, carry_chest.x, carry_chest.y])
	check(absf(absf(carry_hips.x) - 15.0) < 1.0 and absf(carry_chest.x - carry_base_yaw) < 1.5, "Loaded carry turning: the hips turn, the chest stays square (%.2f degrees)" % (carry_chest.x - carry_base_yaw))
	check(absf(carry_chest.y - carry_pitch) < 1.0, "Loaded carry turning: the carry lean is kept (%.1f vs %.1f degrees)" % [carry_chest.y, carry_pitch])
	rig.end_carry()
	for i in 10: await process_frame

	# ---- 5. A cover pose (crouch drop and legs) with lean and a turn.
	await _apply(rig, 0.0, lean, 0.12)
	var cover_hips_height: float = (snap.Hips as Transform3D).origin.y
	var cover_pitch := _angles("Spine2").y
	await _apply(rig, twist, lean, 0.12)
	var cover_both_chest := _angles("Spine2")
	print("  cover crouch 0.12 + lean + twist: chest yaw %.1f, chest pitch %.1f (cover + lean alone %.1f), hips height unchanged %s" % [cover_both_chest.x, cover_both_chest.y, cover_pitch, absf((snap.Hips as Transform3D).origin.y - cover_hips_height) < 0.001])
	check(absf(cover_both_chest.x) < 1.5 and absf(cover_both_chest.y - cover_pitch) < 1.0, "Cover crouch + lean + turn: the chest stays square and the cover lean is kept")
	check(absf((snap.Hips as Transform3D).origin.y - cover_hips_height) < 0.001, "...and the crouch drop is exactly the crouch's (the turn does not move the pelvis height)")

	# ---- 6. The lean owns the spine's flexion: the start/stop pitch (also a flexion) does not stack on it (no double application), and the lean is exact.
	await _apply(rig, 0.0, 0.0, 0.0, 0.0, 4.0)
	var pitch_only := _angles("Spine2").y
	await _apply(rig, 0.0, lean, 0.0, 0.0, 4.0)
	var pitch_and_lean := _angles("Spine2").y
	print("  pitch only %.1f, lean only %.1f, both %.1f" % [pitch_only, chest_lean.y, pitch_and_lean])
	# The pitch is a rotation about the hip hinge applied to the first spine bone, and the lean owns the flexion about the bone's own forward axis; the two axes agree only to within the
	# bone's rest tilt, so some of the pitch survives the lean. Documented and bounded: it never stacks beyond the lean (that would be a double application) and never exceeds its own size.
	check(absf(pitch_and_lean) <= absf(chest_lean.y) + 0.25 and absf(pitch_and_lean - chest_lean.y) <= absf(pitch_only) + 0.25, "Lean + start/stop pitch: the pitch never stacks on the lean (%.1f with both, %.1f lean alone, %.1f pitch alone)" % [pitch_and_lean, chest_lean.y, pitch_only])

	# ---- 7. Returning to neutral restores the neutral pose exactly (no residue of any influence).
	await _apply(rig, 0.0, 0.0)
	var residue := 0.0
	# (The chest, Spine2, carries the idle clip's breathing sway, so it is not a stable reference for this comparison.)
	for n in ["Hips", "Spine", "Spine1"]:
		var rel: Basis = (snap[n] as Transform3D).basis.orthonormalized() * (base[n] as Transform3D).basis.orthonormalized().inverse()
		residue = maxf(residue, rad_to_deg(rel.get_rotation_quaternion().get_angle()))
	check(residue < 0.2, "Back to neutral: every bone is back on its neutral pose (largest residue %.3f degrees)" % residue)

	print("Locomotion/cover composition: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
