extends SceneTree
## ADDA Assignment 3: why do the Workbench's ladder close-up captures show leg vertices inside rungs where `ladder_mesh_clearance_test` measures none? This probe measures the SAME body at the SAME heights
## through each path, one factor at a time, and prints how many leg vertices (over 3 mm, the overlay's and the test's threshold) are inside a bar and whether the sample was FRESH:
##   test/progressive    the test's way: a host, `set_traversal_progress` in 2 cm steps with 2 frames each, the foot plan evolving as it climbs
##   test/cold           the same host, but the pose is asked for straight at the height (no climb before it), 4 frames
##   bench/cold          the Workbench's capture way: `start_ladder_demo(4, up, 0, h)`, paused, 4 frames
##   bench/progressive   the Workbench, climbing to the height in 2 cm steps
## Run: godot --headless --path . --script res://tools/quality/adda_ladder_discrepancy_probe.gd -- <mira_0|small_mira_0> <armed|unarmed>
const BENCH := "res://tools/animation_workbench/pose_workbench.tscn"
const SCENES := {
	"mira_0": "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn",
	"small_mira_0": "res://art/characters/small_mira_0/runtime/small_mira_0_exploration_visual.tscn",
}
const HEIGHTS := [1.0, 1.5, 2.0, 2.5, 3.0]
const RISE := 4.0

func _initialize() -> void:
	_run.call_deferred()

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _count(clearance: LadderClearance, geometry: LadderGeometry, height: float) -> String:
	var status := clearance.status()
	var n := clearance.offenders(geometry, height, 0.003, 100000).size()
	var names := {}
	for entry in clearance.offenders(geometry, height, 0.003, 100000):
		names[entry.bar] = true
	return "%d%s%s" % [n, "" if status == Measurement.Status.FRESH else " (STALE)", (" " + str(names.keys())) if n > 0 else ""]

## `trace` mode: ask for the pose cold at 2.5 m and print, per frame, the vertex count and how far the knees and ankles moved since the previous frame. Shows how long a requested pose takes to become the settled one.
func _trace(character: String, armed: bool) -> void:
	var host: ExplorationCharacterHost = (load(SCENES[character]) as PackedScene).instantiate()
	if not armed:
		host.rig.weapon_scene = null
	root.add_child(host)
	await _frames(25)
	var rig := host.rig
	var clearance := LadderClearance.new(rig)
	rig.begin_traversal(&"ladder", RISE, 1)
	host.position.y = 2.5
	rig.set_traversal_progress(2.5)
	var previous := {}
	var line := ""
	for frame in 60:
		await process_frame
		var moved := 0.0
		for key in ["knee", "ankle"]:
			for side in 2:
				var p: Vector3 = clearance.joints[key][side]
				if previous.has("%s%d" % [key, side]):
					moved = maxf(moved, p.distance_to(previous["%s%d" % [key, side]]))
				previous["%s%d" % [key, side]] = p
		line += "%d:%d/%.0fmm " % [frame, clearance.offenders(rig.ladder.geometry, 2.5, 0.003, 100000).size(), moved * 1000.0]
	print("trace %s %s (frame:vertices/joint movement)
%s" % [character, "armed" if armed else "unarmed", line])
	quit(0)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if "trace" in args:
		await _trace(args[0], args[1] == "armed")
		return
	var character: String = args[0] if args.size() > 0 else "mira_0"
	var armed := (args[1] if args.size() > 1 else "unarmed") == "armed"
	# test/progressive and test/cold
	var host: ExplorationCharacterHost = (load(SCENES[character]) as PackedScene).instantiate()
	if not armed:
		host.rig.weapon_scene = null
	root.add_child(host)
	await _frames(25)
	var rig := host.rig
	var clearance := LadderClearance.new(rig)
	rig.begin_traversal(&"ladder", RISE, 1)
	var progressive := {}
	var height := 0.8
	while height < 3.1:
		host.position.y = height
		rig.set_traversal_progress(height)
		await _frames(2)
		for h in HEIGHTS:
			if absf(height - h) < 0.011 and not progressive.has(h):
				progressive[h] = _count(clearance, rig.ladder.geometry, height)
		height += 0.02
	clearance.release()
	rig.end_traversal()
	host.position.y = 0.0
	await _frames(3)
	var cold := {}
	var cold_settled := {}
	for h in HEIGHTS:
		clearance = LadderClearance.new(rig)
		rig.begin_traversal(&"ladder", RISE, 1)
		host.position.y = h
		rig.set_traversal_progress(h)
		await _frames(4)
		cold[h] = _count(clearance, rig.ladder.geometry, h)
		await _frames(36)
		cold_settled[h] = _count(clearance, rig.ladder.geometry, h)
		clearance.release()
		rig.end_traversal()
		host.position.y = 0.0
		await _frames(3)
	host.queue_free()
	await _frames(2)
	# bench/cold and bench/progressive
	WorkbenchSession.character = StringName(character)
	WorkbenchSession.armed = armed
	WorkbenchSession.autostart_scenario = &""
	WorkbenchSession.start_tab = -1
	var bench: Node3D = (load(BENCH) as PackedScene).instantiate()
	root.add_child(bench)
	await _frames(15)
	var bench_cold := {}
	var bench_free := {}
	for h in HEIGHTS:
		bench.start_ladder_demo(RISE, 1, 0.0, h)
		bench.set_sim_paused(true)
		var c := LadderClearance.new(bench.rig)
		await _frames(4)
		bench_cold[h] = _count(c, bench.rig.ladder.geometry, h)
		bench.set_sim_paused(false)
		await _frames(40)
		bench_free[h] = _count(c, bench.rig.ladder.geometry, h)
		c.release()
	var bench_prog := {}
	bench.start_ladder_demo(RISE, 1, 0.0, 0.8)
	var c2 := LadderClearance.new(bench.rig)
	var bh := 0.8
	while bh < 3.1:
		bench.set_ladder_height(bh)
		await _frames(2)
		for h in HEIGHTS:
			if absf(bh - h) < 0.011 and not bench_prog.has(h):
				bench_prog[h] = _count(c2, bench.rig.ladder.geometry, bh)
		bh += 0.02
	c2.release()
	print("ladder discrepancy probe: %s %s (leg vertices over 3 mm inside a rung or rail)" % [character, "armed" if armed else "unarmed"])
	print("  height   test/progressive   test/cold(4f)   test/cold(40f)   bench/cold(paused,4f)   bench/cold(running,40f)   bench/progressive")
	for h in HEIGHTS:
		print("  %.1f m   %-18s %-15s %-16s %-23s %-25s %s" % [h, progressive.get(h, "-"), cold.get(h, "-"), cold_settled.get(h, "-"), bench_cold.get(h, "-"), bench_free.get(h, "-"), bench_prog.get(h, "-")])
	quit(0)
