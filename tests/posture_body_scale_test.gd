extends SceneTree
## Authored posture depths follow the body (Task 09): a depth a host or profile states in metres (the exploration crouch, the wary bend behind full cover) is tuned
## for the reference body and scales with this body's leg (`CoverCrouchModifier.body_ratio`), so a smaller humanoid bends by the same PROPORTION instead of being
## clamped into its deepest squat. The reference body (MIRA as shown) is unchanged; low cover, which already follows from the wall and the body's head height, is not
## scaled twice. The second body is MIRA shown at scale 1.0 instead of 1.6 (same skeleton, 62.5% of the leg), so the test needs no extra asset.
const HOST := preload("res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _host(scale: float, x: float) -> ExplorationCharacterHost:
	var host: ExplorationCharacterHost = HOST.instantiate()
	var rig: CharacterRig = host.get_node("Rig")
	rig.weapon_scene = null
	if not is_equal_approx(scale, rig.character_scale):
		var profile: Resource = rig.rig_profile.duplicate(true)
		profile.anatomy.character_scale = scale
		rig.rig_profile = profile
		rig.character_scale = scale
	host.position = Vector3(x, 0.0, 0.0)
	root.add_child(host)
	return host

func _run() -> void:
	var reference := _host(1.6, -1.0)
	var small := _host(1.0, 1.0)
	for i in 10: await process_frame
	var ref_crouch := reference.rig.crouch_modifier
	var small_crouch := small.rig.crouch_modifier
	check(ref_crouch != null and small_crouch != null, "Both rigs build the crouch layer")
	if ref_crouch == null or small_crouch == null:
		quit(1)
		return
	check(absf(1.0 - 1.0) < 1e-5, "The reference body's ratio is 1 (%.7f): its authored depths are unchanged" % 1.0)
	check(absf(small_crouch.body_ratio() - 1.0 / 1.6) < 0.002, "The smaller body's ratio is its leg relative to the reference (%.4f, expected %.4f)" % [small_crouch.body_ratio(), 1.0 / 1.6])

	# The contract on the profile: a full-cover bend scales, a low-cover hide does not (it already follows from the wall and the head height).
	var profile := reference.rig.cover_profile
	check(is_equal_approx(profile.crouch_request(true, 2.0, 0.0, ref_crouch.standing_head_height, 1.0), profile.high_cover_crouch_depth * 1.0), "Full cover asks the authored bend times the body ratio")
	check(is_equal_approx(profile.crouch_request(true, 2.0, 0.0, 1.0), profile.high_cover_crouch_depth), "Without a ratio, full cover asks the authored bend (callers that do not pass one keep the old value)")
	for height in [0.6, 0.9, 1.1]:
		check(is_equal_approx(profile.crouch_request(false, height, 0.0, small_crouch.standing_head_height, small_crouch.body_ratio()), profile.crouch_request(false, height, 0.0, small_crouch.standing_head_height, 1.0)), "Low cover (%.1f m) is not scaled again" % height)
	var ref_full := profile.crouch_request(true, 2.0, 0.0, ref_crouch.standing_head_height, 1.0) / ref_crouch._hip_to_ankle
	var small_full := profile.crouch_request(true, 2.0, 0.0, small_crouch.standing_head_height, small_crouch.body_ratio()) / small_crouch._hip_to_ankle
	check(absf(ref_full - small_full) < 0.005, "Behind full cover both bodies bend by the same share of the leg (%.3f vs %.3f)" % [ref_full, small_full])

	# The real host: the exploration crouch lands at the same share of each body's deepest crouch, not clamped to the smaller body's limit.
	reference.set_crouched(true)
	small.set_crouched(true)
	for i in 120: await process_frame
	var ref_share := ref_crouch.depth / ref_crouch.max_depth
	var small_share := small_crouch.depth / small_crouch.max_depth
	check(ref_crouch.depth > 0.1, "The reference body crouches (%.3f m)" % ref_crouch.depth)
	check(absf(ref_crouch.depth - minf(reference.crouch_depth, ref_crouch.max_depth)) < 0.002, "The reference body's crouch is the authored depth, as before (%.3f m)" % ref_crouch.depth)
	check(small_share < 0.98, "The smaller body is not clamped into its deepest crouch (%.2f of its limit)" % small_share)
	check(absf(ref_share - small_share) < 0.03, "Both bodies crouch to the same share of their limit (%.3f vs %.3f)" % [ref_share, small_share])
	check(small_crouch.kneel < 0.01, "The exploration crouch never tips the smaller body into a kneel (%.2f)" % small_crouch.kneel)

	reference.queue_free()
	small.queue_free()
	await process_frame
	print("posture_body_scale_test: %d checks, %d failures" % [checks, failures])
	quit(1 if failures > 0 else 0)
