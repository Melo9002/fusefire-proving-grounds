extends SceneTree
## Measures what the Task 13 motion contract costs per call (CPU, headless): presenting a frame through each family, and the humanoid bridge against the direct presenter calls it translates into.
##   godot --headless --path . --script res://tools/quality/motion_contract_overhead_probe.gd
const ROUNDS := 20000
const RIG := "res://art/characters/mira_0/runtime/mira_0_rig.tscn"

func _initialize() -> void:
	_run.call_deferred()

func _time(label: String, work: Callable) -> void:
	var start := Time.get_ticks_usec()
	for i in ROUNDS:
		work.call()
	print("  %-52s %6.2f us per call" % [label, float(Time.get_ticks_usec() - start) / ROUNDS])

func _run() -> void:
	var entity := Node3D.new()
	root.add_child(entity)
	var wheeled := PrimitiveBodies.build_wheeled(entity)
	var platform := WheeledPresenter.new()
	platform.wheels = wheeled.wheels
	platform.steer_pivots = wheeled.steer_pivots
	var flying := PrimitiveBodies.build_drone(entity)
	var drone := DronePresenter.new()
	drone.visual = flying.visual
	drone.tilt_pivot = flying.tilt_pivot
	drone.rotors = flying.rotors
	var rig: CharacterRig = (load(RIG) as PackedScene).instantiate()
	root.add_child(rig)
	for i in 10:
		await process_frame
	var bridge := HumanoidMotionBridge.new(rig.presenter)
	var velocity := Vector3(1.0, 0.5, 3.0)
	var delta := 1.0 / 60.0
	print("motion_contract_overhead_probe (CPU, %d calls each):" % ROUNDS)
	_time("build one MotionRequest", func() -> void: MotionRequest.make(delta, velocity, entity.global_transform))
	_time("WheeledPresenter.present", func() -> void: platform.present(MotionRequest.make(delta, velocity, entity.global_transform)))
	_time("DronePresenter.present", func() -> void: drone.present(MotionRequest.make(delta, velocity, entity.global_transform).facing_yaw_of(1.0)))
	_time("humanoid direct: report_velocity + tick", func() -> void:
		rig.presenter.report_velocity(velocity, delta, 360.0)
		rig.presenter.tick(delta))
	_time("humanoid via bridge.present (same work + translation)", func() -> void: bridge.present(MotionRequest.make(delta, velocity).facing_toward_velocity()))
	quit()
