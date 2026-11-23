extends SceneTree
## The supported ladder transfer, on the real rigs and measured in the FINAL skeleton pose: MIRA and Small MIRA, armed and unarmed, up onto a deck and back down, for each landing the host can describe
## (two posts, the ladder's own rails run on above the deck) and for the landings that must NOT be treated as supported (a deck with nothing to hold, a lip out of reach, a deck too small): those keep the
## ordinary height-only climb-out and say why. The host here is a stand-in with the sandbox's motion (climb at the profile's speed, then cross the lip over 0.6 s); progress follows MEASURED frame time, so
## the same run at a different frame rate must give the same verdict (a 30 fps and an uncapped pass). Interruption at acquisition and at release must leave nothing behind.
## What is measured: wrists against the grips they are meant to hold, planted deck feet against their footholds, and the body's volumes against the deck solid and the ladder's rungs and rails. All
## approximate (capsules and sole points taken from joints), see LadderClearance. Tolerances are stated next to each check and are not loosened to pass.
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
const RISE := 3.0
const LIP := LandingFixtures.LIP
const CLIMB_SPEED := 0.85
const DESCEND_SPEED := 0.75
const CROSS_SECONDS := 0.6
const CROSS_DISTANCE := 0.73
const WRIST_TOLERANCE := 0.03
const FOOT_TOLERANCE := 0.03
## RATCHETS, NOT GOALS (owner approved committing them this way, 2026-11-23). These are the worst overlaps MEASURED in the final pose (approximate capsules and sole points), set just above them so any regression
## fails. The goals are the ordinary climb's 35 mm and 20 mm against the deck; MIRA's descent still reaches about 46 mm into the deck (thigh) and about 100 mm into the ladder bars near the top (phase 0.54 to 0.67).
## Lowering these numbers is the follow-up; raising them is a regression.
const SOLE_TOLERANCE := 0.015
const LEG_DECK_TOLERANCE := 0.05
const LEG_LADDER_TOLERANCE := 0.11
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

func _landing(kind: String, geometry: LadderGeometry) -> LadderLanding:
	match kind:
		"posts":
			return LadderLanding.with_posts(LIP, 1.5, 3.0, 0.24, 0.416, 0.025, "test posts")
		"rails":
			return LadderLanding.with_extended_rails(geometry, LIP, 1.5, 3.0, 0.9, "test extended rails")
		"deck only":
			return LadderLanding.deck_only(LIP, 1.5, 3.0)
		"too far":
			return LadderLanding.with_posts(0.6, 1.5, 3.0, 0.24, 0.416)
		"too close":
			return LadderLanding.with_posts(0.05, 1.5, 3.0, 0.24, 0.416)
		"too small":
			return LadderLanding.with_posts(LIP, 0.1, 0.1, 0.24, 0.416)
	return null

func _run() -> void:
	_landing_object_checks()
	var stage := Node3D.new()
	root.add_child(stage)
	var x := 0.0
	for key in SCENES:
		for armed in [true, false]:
			var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
			if not armed:
				host.rig.weapon_scene = null
			stage.add_child(host)
			host.position.x = x
			x += 3.0
			await _frames(30)
			var label := "%s %s" % [key, "armed" if armed else "unarmed"]
			for kind in ["posts", "rails"]:
				for direction in [1, -1]:
					await _transfer(host, "%s %s %s" % [label, kind, "up" if direction > 0 else "down"], kind, direction)
			for kind in ["deck only", "too far", "too close", "too small"]:
				await _fallback(host, "%s %s" % [label, kind], kind)
			for phase in [0.2, 0.85]:
				await _interrupt(host, "%s interrupted at %.2f" % [label, phase], phase, armed)
			host.queue_free()
	# The same verdict at another frame rate.
	Engine.max_fps = 30
	var slow := Node3D.new()
	root.add_child(slow)
	for key in SCENES:
		var host: ExplorationCharacterHost = (load(SCENES[key]) as PackedScene).instantiate()
		slow.add_child(host)
		await _frames(10)
		await _transfer(host, "%s armed posts up at 30 fps" % key, "posts", 1)
		host.queue_free()
	Engine.max_fps = 0
	print("ladder_landing_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## The landing description itself: what it accepts and refuses, and that the reasons are said.
func _landing_object_checks() -> void:
	var geometry := LadderGeometry.for_rise(RISE)
	var mira := LadderTestBodies.mira()
	var small := LadderTestBodies.small_mira()
	for body in [mira, small]:
		check(_landing("posts", geometry).unsupported_reason(geometry, body).is_empty(), "posts on a roomy deck are a supported landing")
		check(_landing("rails", geometry).unsupported_reason(geometry, body).is_empty(), "the ladder's own rails run on above the deck are a supported landing")
		check(_landing("deck only", geometry).unsupported_reason(geometry, body).contains("handhold"), "a deck with nothing to hold is refused for want of a handhold")
		check(_landing("too far", geometry).unsupported_reason(geometry, body).contains("leg can step"), "a lip beyond what the leg can step is refused and says so")
		check(_landing("too close", geometry).unsupported_reason(geometry, body).contains("boot needs"), "a wall nearer the rungs than the boot reaches is refused and says so")
		check(_landing("too small", geometry).unsupported_reason(geometry, body).contains("deck"), "a deck too small for the body is refused and says so")
	var one_post := _landing("posts", geometry)
	one_post.grips = [one_post.grips[0]]
	check(one_post.unsupported_reason(geometry, mira).contains("right"), "a landing with a handhold on one side only is refused (nothing is invented for the other hand)")
	check(_landing("posts", geometry).penetration(Vector3(0.0, RISE - 0.05, geometry.plane_ahead + LIP + 0.2), Vector3(0.0, RISE - 0.05, geometry.plane_ahead + LIP + 0.2), 0.0, geometry) > 0.04, "control: a point 5 cm below the deck surface inside the deck is reported inside it")
	check(_landing("posts", geometry).penetration(Vector3(0.0, RISE + 0.02, geometry.plane_ahead + LIP + 0.2), Vector3(0.0, RISE + 0.1, geometry.plane_ahead + LIP + 0.2), 0.0, geometry) == 0.0, "control: a point above the deck is clear")
	check(_landing("posts", geometry).penetration(Vector3(0.0, RISE - 0.5, geometry.plane_ahead), Vector3(0.0, RISE - 0.5, geometry.plane_ahead), 0.05, geometry) == 0.0, "control: a limb at the rungs, in front of the deck's face, is clear")

## One transfer, up or down, sampled every frame from the final pose.
func _transfer(host: ExplorationCharacterHost, label: String, kind: String, direction: int) -> void:
	var rig: CharacterRig = host.rig
	var metrics := LadderClearance.new(rig)
	var handler := func() -> void: metrics.sample()
	rig.skeleton.skeleton_updated.connect(handler)
	var geometry := LadderGeometry.for_rise(RISE)
	var landing := _landing(kind, geometry)
	var start := TraversalSolver.landing_start(geometry, rig.ladder_body()) - 0.3
	rig.begin_traversal(&"ladder", RISE, direction, landing)
	check(rig.ladder.landing != null and rig.ladder.landing_status.begins_with("supported"), "%s: the landing is accepted as supported (%s)" % [label, rig.ladder.landing_status])
	var climbed := start if direction > 0 else RISE
	var across := 0.0 if direction > 0 else 1.0
	var samples := 0
	var held := 0
	var held_worst := 0.0
	var deck_feet := 0
	var deck_feet_worst := 0.0
	var worst_sole := 0.0
	var worst_leg := 0.0
	var worst_leg_where := ""
	var worst_ladder := 0.0
	var worst_ladder_where := ""
	var mesh_bar := 0.0
	var mesh_deck := 0.0
	var mesh_bar_where := ""
	var mesh_deck_where := ""
	var frames_bar_over_10 := 0
	var frames_bar_over_10_planted := 0
	var frames_deck_over_10 := 0
	var sole_sink_worst := 0.0
	var sole_sink_samples := 0
	var mesh_frames := 0
	var shoulder_error := 0.0
	var shoulder_error_where := ""
	var rejected := 0
	var last := Time.get_ticks_usec()
	var guard := 0
	while guard < 20000:
		guard += 1
		var now := Time.get_ticks_usec()
		var dt := minf(float(now - last) / 1000000.0, 0.1)
		last = now
		if direction > 0:
			if climbed < RISE:
				climbed = minf(climbed + CLIMB_SPEED * dt, RISE)
			else:
				across = minf(across + dt / CROSS_SECONDS, 1.0)
		else:
			if across > 0.0:
				across = maxf(across - dt / CROSS_SECONDS, 0.0)
			else:
				climbed = maxf(climbed - DESCEND_SPEED * dt, start)
		var plane := LadderGeometry.PLANE_AHEAD - smoothstep(0.0, 1.0, across) * CROSS_DISTANCE
		host.position.y = climbed
		host.set_climb_height(climbed, plane, smoothstep(0.0, 1.0, across))
		# Pose and joints from the SAME frame: the skeleton applies the progress just set, then both are read.
		await process_frame
		var pose: LadderPose = rig.ladder.pose
		if pose != null and pose.landing_phase >= 0.0 and pose.weight > 0.99:
			samples += 1
			for side in 2:
				if pose.hand_weight[side] > 0.99 and pose.hand_deck[side] > 0.99:
					held += 1
					# The PLANNED grip, not the claim: the rig lowers a claim that is out of reach, which would make any wrist "exact".
					var target: Vector3 = rig.character_root.to_global(pose.hands[side])
					var wrist: Vector3 = rig.character_root.to_global(metrics.joints.wrist[side])
					held_worst = maxf(held_worst, wrist.distance_to(target))
					if not pose.hand_reachable[side]:
						rejected += 1
				if pose.foot_deck[side] > 0.9:
					deck_feet += 1
					var ankle: Vector3 = rig.character_root.to_global(metrics.joints.ankle[side])
					deck_feet_worst = maxf(deck_feet_worst, ankle.distance_to(rig.foot_targets[side].global_position))
			var deck := metrics.deck_clearance(landing, rig.ladder.geometry, climbed)
			worst_sole = maxf(worst_sole, deck.sole)
			for part in ["knee", "thigh", "shin"]:
				if deck[part] > worst_leg:
					worst_leg = deck[part]
					worst_leg_where = "%s, side %d, phase %.2f" % [part, deck.side, pose.landing_phase]
			var mesh := metrics.mesh_clearance(landing, rig.ladder.geometry, climbed)
			for sole in metrics.planted_sole_vs_rung(pose, rig.ladder.geometry, climbed):
				if not is_nan(sole):
					sole_sink_samples += 1
					sole_sink_worst = minf(sole_sink_worst, sole)
			var mesh_bars := maxf(mesh.rung, mesh.rail)
			mesh_frames += 1
			if mesh_bars > 0.010:
				frames_bar_over_10 += 1
				if pose.foot_swing[0] == 0.0 and pose.foot_swing[1] == 0.0:
					frames_bar_over_10_planted += 1
			if mesh.deck > 0.010:
				frames_deck_over_10 += 1
			if mesh_bars > mesh_bar:
				mesh_bar = mesh_bars
				mesh_bar_where = "%s at phase %.2f, feet on rungs %s swing %s" % [mesh.where, pose.landing_phase, pose.foot_rung, pose.foot_swing]
			if mesh.deck > mesh_deck:
				mesh_deck = mesh.deck
				mesh_deck_where = "%s at phase %.2f" % [mesh.where, pose.landing_phase]
			var on_ladder := metrics.clearance(rig.ladder.geometry, climbed)
			var bar := maxf(on_ladder.knee, maxf(on_ladder.thigh, on_ladder.shin))
			if bar > worst_ladder:
				worst_ladder = bar
				worst_ladder_where = "phase %.2f" % pose.landing_phase
			for side in 2:
				var planned := rig.ladder.body.shoulder_leaned(pose.hips, side, pose.lean_degrees)
				var error: float = planned.distance_to(metrics.joints.shoulder[side])
				if error > shoulder_error:
					shoulder_error = error
					var hips_gap: Vector3 = (metrics.joints.hips as Vector3) - pose.hips
					shoulder_error_where = "phase %.2f lean %.0f, hips actual-planned (%.3f %.3f %.3f)" % [pose.landing_phase, pose.lean_degrees, hips_gap.x, hips_gap.y, hips_gap.z]
		if (direction > 0 and across >= 1.0) or (direction < 0 and across <= 0.0 and climbed <= start):
			break
	print("  MESH %s: bars worst %.1f mm (%s), over 10 mm in %d of %d frames (%d with both feet planted); deck worst %.1f mm (%s), over 10 mm in %d frames; planted sole vs rung top, worst %.1f mm (%d samples)" % [label, mesh_bar * 1000.0, mesh_bar_where, frames_bar_over_10, mesh_frames, frames_bar_over_10_planted, mesh_deck * 1000.0, mesh_deck_where, frames_deck_over_10, sole_sink_worst * 1000.0, sole_sink_samples])
	print("  %s: %d landing samples; %d held grips (wrist worst %.3f m, %d unreachable); %d planted deck feet (ankle worst %.3f m); sole into deck %.3f m; limbs into deck %.3f m (%s); limbs into ladder %.3f m (%s); planned vs actual shoulder %.3f m (%s)" % [label, samples, held, held_worst, rejected, deck_feet, deck_feet_worst, worst_sole, worst_leg, worst_leg_where, worst_ladder, worst_ladder_where, shoulder_error, shoulder_error_where])
	check(samples > 30, "%s: the landing was actually exercised (%d samples)" % [label, samples])
	check(held > 15 and held_worst <= WRIST_TOLERANCE, "%s: each hand holds its grip within 3 cm in the final pose (%d samples, worst %.3f m)" % [label, held, held_worst])
	check(deck_feet > 10 and deck_feet_worst <= FOOT_TOLERANCE, "%s: a planted deck foot is within 3 cm of its foothold (%d samples, worst %.3f m)" % [label, deck_feet, deck_feet_worst])
	check(worst_sole <= SOLE_TOLERANCE, "%s: no sole sinks into the deck by more than %.0f mm (worst %.1f mm)" % [label, SOLE_TOLERANCE * 1000.0, worst_sole * 1000.0])
	check(worst_leg <= LEG_DECK_TOLERANCE, "%s: no knee, thigh or shin sinks into the deck or its face by more than %.0f mm (worst %.1f mm: %s)" % [label, LEG_DECK_TOLERANCE * 1000.0, worst_leg * 1000.0, worst_leg_where])
	check(worst_ladder <= LEG_LADDER_TOLERANCE, "%s: the legs stay out of the rungs and rails (worst %.1f mm)" % [label, worst_ladder * 1000.0])
	check(rejected == 0, "%s: no held grip was beyond the arm's reach in the plan (%d)" % [label, rejected])
	rig.skeleton.skeleton_updated.disconnect(handler)
	rig.end_traversal()
	host.position.y = 0.0
	await _frames(3)

## A landing that is not supported: the ordinary height-only pose, identified as the fallback, with the reason.
func _fallback(host: ExplorationCharacterHost, label: String, kind: String) -> void:
	var rig: CharacterRig = host.rig
	var geometry := LadderGeometry.for_rise(RISE)
	rig.begin_traversal(&"ladder", RISE, 1, _landing(kind, geometry))
	check(rig.ladder.landing == null and rig.ladder.landing_status.begins_with("fallback: "), "%s: refused and identified as the fallback (%s)" % [label, rig.ladder.landing_status])
	var same := true
	for height in [2.0, 2.6, 2.9, RISE]:
		rig.set_traversal_progress(height)
		var expected := TraversalSolver.ladder_pose(rig.traversal_profile, rig.ladder.geometry, rig.ladder.body, height, 1)
		var pose: LadderPose = rig.ladder.pose
		same = same and pose.landing_phase < 0.0 and pose.hips.is_equal_approx(expected.hips) and pose.hands[0].is_equal_approx(expected.hands[0]) and pose.feet[1].is_equal_approx(expected.feet[1])
	check(same, "%s: the pose is exactly the height-only climb-out (no supported transfer was posed)" % label)
	rig.end_traversal()
	await _frames(2)

## Interruption in the middle of acquisition (hands reaching) and of release (feet crossing): nothing of the traversal is left, the hands and the rifle are back.
func _interrupt(host: ExplorationCharacterHost, label: String, phase: float, armed: bool) -> void:
	var rig: CharacterRig = host.rig
	var geometry := LadderGeometry.for_rise(RISE)
	rig.begin_traversal(&"ladder", RISE, 1, _landing("posts", geometry))
	var across := 0.0
	var climbed := RISE
	if phase < 0.72:
		climbed = lerpf(TraversalSolver.landing_start(geometry, rig.ladder_body()), RISE, phase / 0.72)
	else:
		across = (phase - 0.72) / 0.28
	host.position.y = climbed
	host.set_climb_height(climbed, LadderGeometry.PLANE_AHEAD - across * CROSS_DISTANCE, across)
	await _frames(3)
	check(rig.ladder != null and rig.ladder.pose.landing_phase >= 0.0, "%s: the transfer was in progress (phase %.2f)" % [label, rig.ladder.pose.landing_phase if rig.ladder != null else -1.0])
	rig.end_traversal()
	await _frames(3)
	check(rig.ladder == null and not rig.traversal_contacts_active(), "%s: traversal and contacts are released" % label)
	var grip: HandGripModifier = rig.grip_modifier
	if armed:
		check(grip.contact_weight == [0.0, 0.0] and not rig.is_weapon_stowed(), "%s: the rifle is back in the hands and no contact weight is left" % label)
	else:
		check(grip.contact_weight == [CharacterRig.HANGING_HAND_WEIGHT, CharacterRig.HANGING_HAND_WEIGHT], "%s: the unarmed hands are back to the hang" % label)
	host.position.y = 0.0
