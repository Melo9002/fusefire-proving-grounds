extends SceneTree
## CharacterPresenter foundation (Task 07 package 2). Proves: the contract works with no TacticalUnit and no rig at all; presentation time is advanced once per tick and never scaled again;
## the production visual ticks its presenter exactly once per frame and BEFORE the modifiers run (same-frame application); reporting a velocity turns the body toward it; the moving
## decision settles the gait; the intent snapshot reflects state that has one owner; teardown releases everything; and the presenter's locomotion path equals feeding the rig directly
## (parity with the workbench's direct feed, so the workbench can be migrated later without a behaviour change). Structural headless checks say nothing about how any pose looks.
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

func _spawn() -> UnitVisualAdapter:
	var v: UnitVisualAdapter = VISUAL.instantiate()
	root.add_child(v)
	return v

func _run() -> void:
	# ---- 1. The contract needs neither a TacticalUnit nor a rig.
	var bare := CharacterPresenter.new()
	bare.tick(0.25)
	bare.report_velocity(Vector3(0, 0, 3), 0.1, 360.0)
	check(is_equal_approx(bare.time, 0.25) and bare.tick_count == 1, "A presenter with no rig ticks and keeps presentation time")
	var bare_intent := bare.intent()
	check(bare_intent.posture == PresentationTypes.Posture.STAND and bare_intent.facing_mode == PresentationTypes.FacingMode.HOLD, "Its intent snapshot is a valid idle state")
	bare.postures.set_posture(&"test/crouch", PresentationTypes.Posture.CROUCH, PresentationTypes.PRIORITY_CONTEXT, 0.3)
	check(bare.intent().posture == PresentationTypes.Posture.CROUCH and is_equal_approx(bare.intent().posture_yaw_offset, 0.3), "Posture requests resolve into the intent snapshot")
	bare.teardown()
	check(bare.postures.request_count() == 0 and bare.intent().posture == PresentationTypes.Posture.STAND, "teardown() releases every posture request")

	# ---- 2. Time is the host's delta, advanced once per tick, never scaled by Engine.time_scale.
	var timed := CharacterPresenter.new()
	Engine.time_scale = 0.25
	for i in 10:
		timed.tick(0.1)
	Engine.time_scale = 1.0
	check(is_equal_approx(timed.time, 1.0) and timed.tick_count == 10, "Presentation time is the sum of the deltas it was given (%.3f), whatever Engine.time_scale is" % timed.time)

	# ---- 3. The production visual: one tick per frame, before the modifiers, no TacticalUnit involved.
	var v := _spawn()
	for i in 5:
		await process_frame
	check(is_instance_valid(v.presenter) and v.presenter.rig == v and v.tactical_unit == null, "The production visual owns a presenter bound to itself and has no tactical unit")
	var ticks_at_modifier: Array = []
	var frame_at_modifier: Array = []
	v.locomotion_modifier.modification_processed.connect(func() -> void:
		ticks_at_modifier.append(v.presenter.tick_count)
		frame_at_modifier.append([v.presenter.last_tick_frame, Engine.get_process_frames()]))
	for i in 12:
		await process_frame
	var steps_ok := ticks_at_modifier.size() >= 10
	for i in range(1, ticks_at_modifier.size()):
		steps_ok = steps_ok and ticks_at_modifier[i] - ticks_at_modifier[i - 1] == 1
	check(steps_ok, "The presenter ticks exactly once per frame (never skipped, never doubled): %s" % [ticks_at_modifier.slice(0, 6)])
	var same_frame := true
	for pair in frame_at_modifier:
		same_frame = same_frame and pair[0] == pair[1]
	check(same_frame, "The tick of a frame has happened before that frame's modifiers run (same-frame application)")
	var t0 := v.presenter.time
	await process_frame
	await process_frame
	check(v.presenter.time > t0, "The presenter's presentation clock advances, and it is the only one (the adapter keeps no clock of its own)")

	# ---- 4. A reported velocity turns the body toward it and drives the gait; silence settles it.
	v.global_rotation.y = 0.0
	v.update_locomotion(Vector3(4, 0, 0), 0.05)   # +X: a yaw of +90 degrees
	var turned := v.global_rotation.y
	check(turned > 0.0 and turned <= deg_to_rad(v.turn_speed_degrees) * 0.05 + 0.0001, "Facing follows the velocity at the configured turn rate (%.3f rad in 0.05 s)" % turned)
	check(absf(v.presenter.speed - 4.0) < 0.0001 and v.presenter.velocity.is_equal_approx(Vector3(4, 0, 0)), "The presenter holds the reported speed and velocity")
	check(v.presenter.intent().facing_mode == PresentationTypes.FacingMode.FOLLOW_VELOCITY, "While reported moving the intent's facing mode is FOLLOW_VELOCITY")
	for i in 30:
		v.update_locomotion(Vector3(4, 0, 0), 1.0 / 60.0)
		await process_frame
	check(v.locomotion_report.speed > 0.5, "A moving report is turned into gait speed by the production locomotion (%.2f m/s)" % v.locomotion_report.speed)
	for i in 60:
		await process_frame
	check(v.presenter.speed == 0.0 and v.presenter.velocity == Vector3.ZERO and v.locomotion_report.speed < 0.05, "With no reports the character settles to a stop (speed %.3f)" % v.locomotion_report.speed)
	check(v.presenter.intent().facing_mode == PresentationTypes.FacingMode.HOLD, "...and the intent says HOLD")
	# A movement authority overrides the inference.
	v.set_process(false)   # the host re-asserts its own authority every frame, so tick by hand to test the presenter's rule
	v.update_locomotion(Vector3(3, 0, 0), 1.0 / 60.0)
	v.presenter.set_movement_authority(false)
	await process_frame
	v.presenter.tick(1.0 / 60.0)
	check(v.presenter.speed == 0.0, "When authority says the unit is not moving, a fresh report does not keep it moving")
	v.presenter.clear_movement_authority()
	v.set_process(true)

	# ---- 5. The snapshot reads state that has one owner (readiness and equipment stay the rig's; the presenter only reads them).
	v.readiness.request(&"test", WeaponReadiness.Level.AIMED)
	check(v.presenter.intent().readiness == WeaponReadiness.Level.AIMED, "Readiness in the snapshot is the rig's own request table (not a copy)")
	v.readiness.release(&"test")
	check(v.presenter.intent().equipment == PresentationTypes.EquipmentState.HELD, "A carried rifle reads as HELD")
	v.stow_weapon()
	check(v.presenter.intent().equipment == PresentationTypes.EquipmentState.SLUNG, "A stowed rifle reads as SLUNG")
	v.unstow_weapon()

	# ---- 6. Parity: the presenter's locomotion path equals feeding the rig directly (what the workbench does today).
	var a := _spawn()
	var b := _spawn()
	await process_frame
	a.set_process(false)
	b.set_process(false)
	var dt := 1.0 / 60.0
	var worst := 0.0
	for i in 90:
		var speed := 4.0 if i < 60 else 0.0
		var rate := 0.8 if i % 20 < 10 else -0.8
		a.presenter.speed = speed
		a.presenter.heading_rate = rate
		a.presenter.set_movement_authority(speed > 0.0)
		a.presenter.tick(dt)
		b.update_locomotion_presentation(speed, rate if speed > 0.0 else 0.0, dt)
		worst = maxf(worst, absf(a.locomotion_report.gait - b.locomotion_report.gait) + absf(a.locomotion_report.cadence - b.locomotion_report.cadence) + absf(a.locomotion_report.bank - b.locomotion_report.bank) + absf(a.locomotion_report.speed - b.locomotion_report.speed))
		await process_frame
	check(worst < 0.0001, "The presenter path and the direct rig feed give the same gait, cadence, bank and speed every frame (worst difference %.6f)" % worst)
	# A second tick in the same frame must not feed (and so must not advance the smoothing) twice.
	var before: float = a.locomotion_report.speed
	a.presenter.speed = 4.0
	a.presenter.set_movement_authority(true)
	a.presenter.tick(dt)
	var after_one: float = a.locomotion_report.speed
	a.presenter.tick(dt)
	check(a.locomotion_report.speed == after_one and after_one != before, "A second tick in the same frame advances presentation time but never feeds the gait twice")

	print("CharacterPresenter: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
