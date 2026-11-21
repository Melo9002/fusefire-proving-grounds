extends SceneTree
## One shared frame driver (Task 07 package 3): the tactical visual (TacticalCharacterAdapter) and the animation workbench both advance presentation through their rig's CharacterPresenter, exactly
## once per frame and before that frame's modifiers, with no second path to the locomotion feed. The workbench feeds authored preview motion through the same presenter and keeps its idle
## heading-rate behaviour. This does NOT claim the inheritance-to-composition conversion: both hosts still ARE the rig.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const WORKBENCH := preload("res://tools/animation_workbench/pose_workbench.tscn")
var failures := 0
var checks := 0

func _initialize() -> void:
	Engine.max_fps = 60
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## Records, at the moment this host's first modifier finishes, how many ticks the presenter has had and on which engine frame the latest one ran.
func _watch(host: Node3D, samples: Array) -> void:
	host.rig.locomotion_modifier.modification_processed.connect(func() -> void:
		samples.append([host.presenter.tick_count, host.presenter.last_tick_frame, Engine.get_process_frames(), host.presenter.time]))

func _verify_driver(label: String, samples: Array) -> void:
	var one_per_frame := samples.size() >= 20
	var before_modifiers := true
	for i in range(1, samples.size()):
		one_per_frame = one_per_frame and samples[i][0] - samples[i - 1][0] == 1
	for s in samples:
		before_modifiers = before_modifiers and s[1] == s[2]
	check(one_per_frame, "%s: the presenter ticks exactly once per frame (no skipped or doubled ticks)" % label)
	check(before_modifiers, "%s: each frame's tick happened before that frame's modifiers (same-frame application)" % label)

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var adapter: TacticalCharacterAdapter = VISUAL.instantiate()
	stage.add_child(adapter)
	var bench: Node3D = WORKBENCH.instantiate()
	root.add_child(bench)
	for i in 10:
		await process_frame
	var adapter_samples := []
	var bench_samples := []
	_watch(adapter, adapter_samples)
	_watch(bench, bench_samples)
	for i in 30:
		await process_frame
	_verify_driver("Tactical visual", adapter_samples)
	_verify_driver("Workbench", bench_samples)
	check(adapter.presenter != bench.presenter and adapter.presenter.rig == adapter.rig and bench.presenter.rig == bench.rig, "Each host has its own presenter bound to its own rig")

	# ---- Same elapsed time on both, advanced once per frame by the engine's delta.
	var t0_a := adapter.presenter.time
	var t0_b: float = bench.presenter.time
	var frames0 := Engine.get_process_frames()
	for i in 20:
		await process_frame
	var frames := Engine.get_process_frames() - frames0
	var elapsed_a := adapter.presenter.time - t0_a
	var elapsed_b: float = bench.presenter.time - t0_b
	check(absf(elapsed_a - elapsed_b) < 0.0001 and elapsed_a > 0.0, "Both hosts advance presentation time by the same engine deltas (%.4f s over %d frames)" % [elapsed_a, frames])

	# ---- The workbench feeds authored motion through the shared presenter: a preview walk reaches the gait; its idle heading rate is preserved.
	bench.rig.animation_controller.play(&"move")
	for i in 60:
		await process_frame
	check(bench.presenter.speed > 0.5 and bench.rig.locomotion_report.speed > 0.5, "A preview walk is fed through the presenter into the production locomotion (%.2f m/s)" % bench.rig.locomotion_report.speed)
	bench.rig.animation_controller.play(&"rifle_idle")
	bench.turn_goal = bench.rig.character_root.rotation.y + deg_to_rad(120.0)
	var saw_idle_heading := false
	for i in 20:
		await process_frame
		saw_idle_heading = saw_idle_heading or (bench.presenter.speed == 0.0 and absf(bench.presenter.heading_rate) > 0.1)
	check(saw_idle_heading, "While idle, a turn preview still feeds its heading rate (speed 0, heading %.2f rad/s at some frame): the workbench behaviour is preserved" % bench.presenter.heading_rate)

	# ---- No second path: neither host calls the locomotion feed or writes the posture ramps itself.
	for path in ["res://tools/animation_workbench/pose_workbench.gd", "res://presentation/tactical/tactical_character_adapter.gd"]:
		var text := FileAccess.get_file_as_string(path)
		check(not text.contains("update_locomotion_presentation("), "%s no longer drives the locomotion feed directly" % path.get_file())
		check(not text.contains("crouch_modifier.depth =") and not text.contains("crouch_modifier.kneel ="), "%s no longer writes the crouch depth or kneel directly" % path.get_file())

	print("Presentation frame driver: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
