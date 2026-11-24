extends SceneTree
## Ladder clearance MEASURED ON THE MESH: the legs' skinned surface (SkinnedSurface, sampled in the final pose inside `skeleton_updated`) against the rungs, the rails and the deck solid, on both bodies, armed and
## unarmed, climbing and descending, and through the supported landing. Three different things are measured elsewhere or here and must not be confused:
##   * CAPSULE overlap (ladder_climb_test, ladder_landing_test): limb volumes around the bones. An approximation, and conservative where the armor is thin and short where it is thick. Those tests keep their
##     original goals and are NOT changed here (they currently fail for want of a gait that fits the armor; see the report).
##   * SAMPLED MESH-VERTEX overlap (this test): how many vertices of the drawn surface are inside a bar, and in how many frames. Surface vertices are sampled points, so a thin crossing between two of them can be
##     missed, and one vertex on a bar's axis reads as the bar's full radius whatever the crossing depth: that is why the COUNT of vertices, not the deepest one, is the severity here.
##   * FULL mesh intersection (triangle against bar): not measured.
## The goal is NO leg vertex inside a bar. The baselines below are what the animation achieves TODAY, set just above it so a regression fails; they are baselines, not quality targets, and each run prints the gap to the
## goal. Raising a baseline is a regression.
const SCENES := {
	"mira": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
const RISE := 4.0
const LANDING_RISE := 3.0
const THRESHOLD := 0.003
## Ordinary climb: baselines (measured: MIRA 0 per frame and 0% of frames with five vertices or more; Small MIRA 0 per frame, 7%).
const CLIMB_MEAN_BASELINE := 1.0
const CLIMB_BAD_FRAME_SHARE_BASELINE := 0.12
## Landing: the share of landing frames with any leg vertex over 10 mm inside a bar or the deck, and the deepest deck overlap. MEASURED by this test (descent, MIRA 23% and 52 mm; Small MIRA 21% and 58 mm, in the frames where the
## lead knee crosses the lip), baselines set just above; the first guesses (22%, 55 mm) were below what is achieved and are replaced by the measurement.
const LANDING_BAD_FRAME_SHARE_BASELINE := 0.27
const LANDING_DECK_BASELINE := 0.065
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

func _run() -> void:
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
			await _frames(25)
			var label := "%s %s" % [key, "armed" if armed else "unarmed"]
			if armed == false and key == "mira":
				await _controls(host)
			for direction in [1, -1]:
				await _climb(host, "%s %s" % [label, "up" if direction > 0 else "down"], direction)
			for kind in ["posts", "rails"]:
				for direction in [1, -1]:
					await _landing(host, "%s %s %s" % [label, kind, "up" if direction > 0 else "down"], kind, direction)
			host.queue_free()
	print("ladder_mesh_clearance_test: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## Negative controls: the measurement is able to see (1) a surface that does not follow the pose (the defect this test was written after: the skinned mesh was read outside the signal and stayed at the base
## pose), (2) a body in a bar.
func _controls(host: ExplorationCharacterHost) -> void:
	var rig := host.rig
	var clearance := LadderClearance.new(rig)
	rig.begin_traversal(&"ladder", RISE, 1)
	var geometry := rig.ladder.geometry
	var centroids: Array[Vector3] = []
	for height in [1.0, 1.12]:
		host.position.y = height
		rig.set_traversal_progress(height)
		await _frames(3)
		var surface_points := clearance.offenders(geometry, height, -1.0, 100000)
		var sum := Vector3.ZERO
		for entry in surface_points:
			sum += entry.point
		centroids.append(sum / maxf(float(surface_points.size()), 1.0))
	check(centroids[0].distance_to(centroids[1]) > 0.02, "control: the skinned leg surface FOLLOWS the pose (its centre moved %.3f m between two heights; a surface read outside the signal does not move)" % centroids[0].distance_to(centroids[1]))
	# A ladder dropped through the body: many vertices must be inside bars.
	host.position.y = 2.0
	rig.set_traversal_progress(2.0)
	await _frames(3)
	var clean := clearance.offenders(geometry, 2.0, THRESHOLD, 100000).size()
	geometry.plane_ahead -= 0.10
	var through := clearance.offenders(geometry, 2.0, THRESHOLD, 100000).size()
	geometry.plane_ahead += 0.10
	check(through > clean + 20, "control: moving the rung plane 10 cm toward the body, through the legs, puts many vertices inside bars (%d, from %d)" % [through, clean])
	rig.end_traversal()
	await _frames(2)

func _climb(host: ExplorationCharacterHost, label: String, direction: int) -> void:
	var rig := host.rig
	var clearance := LadderClearance.new(rig)
	rig.begin_traversal(&"ladder", RISE, direction)
	var frames := 0
	var bad := 0
	var vertices := 0
	var worst := 0
	var height := 0.8 if direction > 0 else 3.2
	while height > 0.7 and height < 3.3:
		host.position.y = height
		rig.set_traversal_progress(height)
		await _frames(2)
		var count := clearance.offenders(rig.ladder.geometry, height, THRESHOLD, 100000).size()
		frames += 1
		vertices += count
		worst = maxi(worst, count)
		bad += 1 if count >= 5 else 0
		height += 0.02 * direction
	var mean := float(vertices) / float(frames)
	var share := float(bad) / float(frames)
	print("  %s: leg vertices inside bars (over 3 mm): mean %.2f per frame, worst frame %d, five or more in %.0f%% of frames (goal 0; baselines %.1f and %.0f%%)" % [label, mean, worst, share * 100.0, CLIMB_MEAN_BASELINE, CLIMB_BAD_FRAME_SHARE_BASELINE * 100.0])
	check(mean <= CLIMB_MEAN_BASELINE, "%s: mean vertices inside bars %.2f is within the baseline %.1f (goal 0)" % [label, mean, CLIMB_MEAN_BASELINE])
	check(share <= CLIMB_BAD_FRAME_SHARE_BASELINE, "%s: frames with five or more vertices inside bars %.0f%% within the baseline %.0f%% (goal 0)" % [label, share * 100.0, CLIMB_BAD_FRAME_SHARE_BASELINE * 100.0])
	clearance.release()
	rig.end_traversal()
	host.position.y = 0.0
	await _frames(2)

func _landing(host: ExplorationCharacterHost, label: String, kind: String, direction: int) -> void:
	var rig := host.rig
	var clearance := LadderClearance.new(rig)
	var geometry := LadderGeometry.for_rise(LANDING_RISE)
	var landing := LandingFixtures.make(kind, geometry)
	rig.begin_traversal(&"ladder", LANDING_RISE, direction, landing)
	var start := TraversalSolver.landing_start(geometry, rig.ladder_body()) - 0.2
	var frames := 0
	var bad := 0
	var deck_worst := 0.0
	var steps := 90
	for i in steps + 1:
		var t := float(i) / float(steps)
		# Up: climb to the top over the first 60%, then cross the lip over the rest. Down: the reverse.
		var phase := t if direction > 0 else 1.0 - t
		var climbed := lerpf(start, LANDING_RISE, clampf(phase / 0.6, 0.0, 1.0))
		var across := clampf((phase - 0.6) / 0.4, 0.0, 1.0)
		host.position.y = climbed
		host.set_climb_height(climbed, LadderGeometry.PLANE_AHEAD - smoothstep(0.0, 1.0, across) * 0.73, smoothstep(0.0, 1.0, across))
		await _frames(2)
		var pose: LadderPose = rig.ladder.pose
		if pose == null or pose.landing_phase < 0.0:
			continue
		frames += 1
		var mesh := clearance.mesh_clearance(landing, rig.ladder.geometry, climbed)
		deck_worst = maxf(deck_worst, mesh.deck)
		bad += 1 if (maxf(mesh.rung, mesh.rail) > 0.010 or mesh.deck > 0.010) else 0
	var share := float(bad) / float(maxi(frames, 1))
	print("  %s: landing frames with a leg vertex over 10 mm inside a bar or the deck: %d of %d (%.0f%%), deepest deck overlap %.0f mm (goal 0; baselines %.0f%% and %.0f mm)" % [label, bad, frames, share * 100.0, deck_worst * 1000.0, LANDING_BAD_FRAME_SHARE_BASELINE * 100.0, LANDING_DECK_BASELINE * 1000.0])
	check(frames > 30, "%s: the landing was exercised (%d frames)" % [label, frames])
	check(share <= LANDING_BAD_FRAME_SHARE_BASELINE, "%s: landing frames over 10 mm %.0f%% within the baseline %.0f%% (goal 0)" % [label, share * 100.0, LANDING_BAD_FRAME_SHARE_BASELINE * 100.0])
	check(deck_worst <= LANDING_DECK_BASELINE, "%s: the deepest deck overlap %.0f mm is within the baseline %.0f mm (goal 0)" % [label, deck_worst * 1000.0, LANDING_DECK_BASELINE * 1000.0])
	clearance.release()
	rig.end_traversal()
	host.position.y = 0.0
	host.position.z = 0.0
	await _frames(2)
