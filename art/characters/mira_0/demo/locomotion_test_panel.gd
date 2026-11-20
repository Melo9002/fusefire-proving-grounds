class_name LocomotionTestPanel
extends PanelContainer
## An on-screen test bench for locomotion, built into the animation workbench so the production rig can be driven by hand: a speed slider with the gait
## it selects, gait presets, direction, loaded carry, turns in place, moving turns and reversals, scripted transitions, slow motion, camera views and a
## live readout. It only calls the workbench's public controls (which feed the same LocomotionProfile presentation the game uses); nothing here is a
## second implementation of anything.

var bench: Node3D
var _speed_slider: HSlider
var _speed_label: Label
var _readout: Label
var _loaded: CheckButton
var _slow: HSlider
var _scenario_label: Label
var _scenario_time := -1.0
var _scenario := &""
var _ladder_slider: HSlider
var _stair_rise: HSlider
var _stair_depth: HSlider

const VIEWS := {
	"Front": [Vector3(0, 1.1, 3.4), Vector3(0, 0.9, 0)],
	"Side": [Vector3(3.4, 1.1, 0), Vector3(0, 0.9, 0)],
	"Back": [Vector3(0, 1.1, -3.4), Vector3(0, 0.9, 0)],
	"3/4": [Vector3(2.5, 1.3, 2.5), Vector3(0, 0.9, 0)],
	"Feet": [Vector3(1.6, 0.35, 1.2), Vector3(0, 0.3, 0)],
	"Top": [Vector3(0.2, 4.2, 1.0), Vector3(0, 0.5, 0)],
	"Behind": [Vector3(-1.2, 1.6, -2.6), Vector3(0, 0.9, 0.4)],
}


func setup(workbench: Node3D) -> void:
	bench = workbench
	name = "LocomotionTestPanel"
	custom_minimum_size = Vector2(320, 0)
	var box := VBoxContainer.new()
	add_child(box)
	box.add_child(_label("LOCOMOTION TEST BENCH  (production rig)", true))
	_speed_label = _label("")
	box.add_child(_speed_label)
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.0
	_speed_slider.max_value = 8.0
	_speed_slider.step = 0.1
	_speed_slider.value = bench.preview_speed
	_speed_slider.value_changed.connect(func(v: float) -> void: _set_speed(v))
	box.add_child(_speed_slider)
	box.add_child(_row([["Idle", func() -> void: _preset(0.0)], ["Walk", func() -> void: _preset(1.2)], ["Jog", func() -> void: _preset(3.0)], ["Run", func() -> void: _preset(5.0)]]))
	_loaded = CheckButton.new()
	_loaded.text = "Carry a passenger (loaded gaits)"
	_loaded.toggled.connect(_on_loaded_toggled)
	box.add_child(_loaded)
	box.add_child(_row([["Fwd", func() -> void: _direction(Vector2(0, 1))], ["Back", func() -> void: _direction(Vector2(0, -1))], ["Left", func() -> void: _direction(Vector2(1, 0))], ["Right", func() -> void: _direction(Vector2(-1, 0))]]))
	box.add_child(_label("Turn in place (instant facing change, hips catch up)"))
	box.add_child(_row([["-180", func() -> void: _turn_in_place(-180)], ["-90", func() -> void: _turn_in_place(-90)], ["-30", func() -> void: _turn_in_place(-30)], ["+30", func() -> void: _turn_in_place(30)], ["+90", func() -> void: _turn_in_place(90)], ["+180", func() -> void: _turn_in_place(180)]]))
	box.add_child(_label("Moving turn (gradual, 360 deg/s like the game)"))
	box.add_child(_row([["Left 90", func() -> void: _moving_turn(90)], ["Right 90", func() -> void: _moving_turn(-90)], ["Reverse 180", func() -> void: _moving_turn(180)]]))
	box.add_child(_label("Scripted transitions"))
	box.add_child(_row([["Start-Run-Stop", func() -> void: _start_scenario(&"run_stop")], ["Ramp 0-6 m/s", func() -> void: _start_scenario(&"ramp")], ["Walk-Jog-Run", func() -> void: _start_scenario(&"steps")]]))
	_scenario_label = _label("")
	box.add_child(_scenario_label)
	box.add_child(_label("Cover (synthetic wall; side from CoverEdgeSelector, pose from CoverPostureProfile)"))
	box.add_child(_row([["Low", func() -> void: _cover(false, 0.9, 1.5, 1.5, true, true, false)], ["Low aim", func() -> void: _cover(false, 0.9, 1.5, 1.5, true, true, true)], ["Left edge", func() -> void: _cover(true, 2.2, 0.5, 2.0, true, true, false)], ["Right edge", func() -> void: _cover(true, 2.2, 2.0, 0.5, true, true, false)]]))
	box.add_child(_row([["Tie (right)", func() -> void: _cover(true, 2.2, 1.5, 1.5, true, true, false)], ["No edge", func() -> void: _cover(true, 2.2, 3.5, 3.5, false, false, false)], ["Peek aim", func() -> void: _cover(true, 2.2, 0.5, 2.0, true, true, true)], ["Leave", func() -> void: bench.set_cover_demo({})]]))
	box.add_child(_label("Authorized attack (bench target; the plan is the production CoverEdgeSelector.plan_attack)"))
	box.add_child(_row([["Target left", func() -> void: bench.set_cover_target(Vector3(5, 0, 1.5))], ["Target right", func() -> void: bench.set_cover_target(Vector3(-5, 0, 1.5))], ["Target ahead", func() -> void: bench.set_cover_target(Vector3(0, 0, 5))], ["Open side", func() -> void: bench.set_cover_target(Vector3(2, 0, -5))]]))
	box.add_child(_row([["Fire", func() -> void: bench.fire_cover_shot()], ["End attack", func() -> void: bench.set_cover_target(null)], ["Left usable only", func() -> void: _cover(true, 2.2, 0.5, 3.5, true, false, false)], ["Right usable only", func() -> void: _cover(true, 2.2, 3.5, 0.5, false, true, false)]]))
	box.add_child(_label("Environmental traversal: ladder (production solver; the bench supplies the height the game would)"))
	box.add_child(_row([["Climb 4 m", func() -> void: _ladder(4.0, 1, 0.85)], ["Descend 4 m", func() -> void: _ladder(4.0, -1, 0.75)], ["Climb 3 m", func() -> void: _ladder(3.0, 1, 0.85)], ["Stop", func() -> void: bench.end_ladder_demo()]]))
	box.add_child(_row([["Pause / play", func() -> void: _ladder_toggle()], ["Mount (hold)", func() -> void: _ladder_hold(0.25)], ["Top-out (hold)", func() -> void: _ladder_hold(3.6)], ["Mid (hold)", func() -> void: _ladder_hold(2.0)]]))
	_ladder_slider = HSlider.new()
	_ladder_slider.min_value = 0.0
	_ladder_slider.max_value = 4.0
	_ladder_slider.step = 0.01
	_ladder_slider.value_changed.connect(func(v: float) -> void:
		if not bench.ladder_demo.is_empty():
			bench.ladder_demo.playing = false
			bench.set_ladder_height(v))
	box.add_child(_ladder_slider)
	var ladder_markers := CheckButton.new()
	ladder_markers.text = "Contact markers (hands red/blue, feet orange/cyan)"
	ladder_markers.toggled.connect(func(on: bool) -> void: bench.traversal_diagnostics = on)
	box.add_child(ladder_markers)
	box.add_child(_label("Vault / step-over / mantle: solver prototype only (TraversalSolver.vault_pose); not driven here and not in gameplay"))
	box.add_child(_label("Stairs (production planner + leg IK; the bench supplies the progress the game would)"))
	box.add_child(_row([["Up 0.5/0.5", func() -> void: _stairs(0.5, 0.5, 6, true)], ["Down 0.5/0.5", func() -> void: _stairs(0.5, 0.5, 6, false)], ["Up 0.17/0.33", func() -> void: _stairs(0.1667, 0.3333, 12, true)], ["Down 0.17/0.33", func() -> void: _stairs(0.1667, 0.3333, 12, false)]]))
	box.add_child(_row([["Pause/play", func() -> void: _stairs_toggle()], ["Step frame", func() -> void: bench.step_stair_demo_frame()], ["Mid stair", func() -> void: _stairs_hold(2.2)], ["Stop", func() -> void: bench.end_stair_demo()]]))
	box.add_child(_label("Stair rise / tread depth (m) for the custom stair, speed (m/s)"))
	_stair_rise = HSlider.new()
	_stair_rise.min_value = 0.1
	_stair_rise.max_value = 0.6
	_stair_rise.step = 0.01
	_stair_rise.value = 0.2
	box.add_child(_stair_rise)
	_stair_depth = HSlider.new()
	_stair_depth.min_value = 0.2
	_stair_depth.max_value = 0.8
	_stair_depth.step = 0.01
	_stair_depth.value = 0.3
	box.add_child(_stair_depth)
	box.add_child(_row([["Custom up", func() -> void: _stairs(_stair_rise.value, _stair_depth.value, 8, true)], ["Custom down", func() -> void: _stairs(_stair_rise.value, _stair_depth.value, 8, false)]]))
	var stair_markers := CheckButton.new()
	stair_markers.text = "Foot markers (planned green/teal, actual red/orange)"
	stair_markers.toggled.connect(func(on: bool) -> void: bench.stair_diagnostics = on)
	box.add_child(stair_markers)
	box.add_child(_label("Path corridor (PathRefiner on synthetic obstacles: route white, smoothed cyan, footprints green)"))
	box.add_child(_row([["Open", func() -> void: bench.show_path_demo("open")], ["Wall", func() -> void: bench.show_path_demo("wall")], ["Corner", func() -> void: bench.show_path_demo("corner")], ["Column", func() -> void: bench.show_path_demo("column")]]))
	box.add_child(_row([["Narrow ok", func() -> void: bench.show_path_demo("narrow")], ["Too narrow", func() -> void: bench.show_path_demo("too_narrow")], ["Hide", func() -> void: bench.hide_path_demo()]]))
	var overlay := CheckButton.new()
	overlay.text = "Cover diagnostics overlay"
	overlay.toggled.connect(func(on: bool) -> void: bench.cover_diagnostics = on)
	box.add_child(overlay)
	box.add_child(_label("Camera"))
	var views := []
	for view_name in VIEWS:
		views.append([view_name, func() -> void: _view(view_name)])
	box.add_child(_row(views))
	box.add_child(_label("Slow motion (time scale)"))
	_slow = HSlider.new()
	_slow.min_value = 0.05
	_slow.max_value = 1.0
	_slow.step = 0.05
	_slow.value = 1.0
	_slow.value_changed.connect(func(v: float) -> void: Engine.time_scale = v)
	box.add_child(_slow)
	_readout = _label("")
	box.add_child(_readout)
	_set_speed(bench.preview_speed, false)   # showing the slider's value must not set the character walking


func _exit_tree() -> void:
	Engine.time_scale = 1.0


func _label(text: String, bold := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 13 if not bold else 14)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


func _row(buttons: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	for entry in buttons:
		var button := Button.new()
		button.text = entry[0]
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(entry[1])
		row.add_child(button)
	return row


func _set_speed(value: float, start_moving := true) -> void:
	bench.preview_speed = value
	if not is_equal_approx(_speed_slider.value, value):
		_speed_slider.set_value_no_signal(value)
	var gait: String = "idle"
	var blend: float = bench.locomotion_profile.gait_blend(value)
	if value >= bench.locomotion_profile.idle_below:
		gait = ("walk" if blend < 0.5 else "jog") if blend < 1.5 else "run"
	_speed_label.text = "Speed %.1f m/s  ->  %s%s" % [value, gait, " (loaded)" if _loaded != null and _loaded.button_pressed else ""]
	if start_moving and value >= bench.locomotion_profile.idle_below:
		_ensure_moving()


func _ensure_moving() -> void:
	var state: StringName = &"carry_move" if (_loaded != null and _loaded.button_pressed) else &"move"
	if bench.animation_controller.current_state != state:
		bench.animation_controller.play(state)


func _preset(speed: float) -> void:
	_scenario = &""
	_set_speed(speed)


func _direction(direction: Vector2) -> void:
	bench.locomotion_direction = direction
	bench.preview_direction = direction


func _on_loaded_toggled(pressed: bool) -> void:
	bench.finish_interaction_now()
	if pressed:
		bench.begin_carry()
		bench.animation_controller.play(&"carry_idle" if bench.preview_speed < 0.15 else &"carry_move")
	else:
		bench.end_carry()
		bench.animation_controller.play(&"rifle_idle" if bench.preview_speed < 0.15 else &"move")
	_set_speed(bench.preview_speed)


func _turn_in_place(degrees: float) -> void:
	_set_speed(0.0)
	bench.turn_goal = NAN
	var change := deg_to_rad(degrees)
	bench.character_root.rotation.y += change
	bench.begin_turn(change)


func _moving_turn(degrees: float) -> void:
	if bench.preview_speed < 1.0:
		_set_speed(4.0)
	bench.turn_goal = bench.character_root.rotation.y + deg_to_rad(degrees)


func _start_scenario(kind: StringName) -> void:
	_scenario = kind
	_scenario_time = 0.0
	_set_speed(0.0)


func _cover(full: bool, height: float, left: float, right: float, left_ok: bool, right_ok: bool, aim: bool) -> void:
	_set_speed(0.0, false)
	bench.set_cover_demo({"full": full, "height": height, "left": left, "right": right, "left_ok": left_ok, "right_ok": right_ok, "aim": aim})


func _stairs(rise: float, depth: float, count: int, ascending: bool) -> void:
	_set_speed(0.0, false)
	bench.start_stair_demo(rise, depth, count, ascending, 1.4)


func _stairs_toggle() -> void:
	if not bench.stair_demo.is_empty():
		bench.stair_demo.playing = not bool(bench.stair_demo.playing)


func _stairs_hold(s: float) -> void:
	_set_speed(0.0, false)
	if bench.stair_demo.is_empty():
		bench.start_stair_demo(0.5, 0.5, 6, true, 1.4, s)
	bench.stair_demo.playing = false
	bench.set_stair_demo_s(s)


func _ladder(length: float, direction: int, rate: float) -> void:
	_set_speed(0.0, false)
	bench.start_ladder_demo(length, direction, rate)
	_ladder_slider.max_value = length


func _ladder_toggle() -> void:
	if not bench.ladder_demo.is_empty():
		bench.ladder_demo.playing = not bool(bench.ladder_demo.playing)


func _ladder_hold(height: float) -> void:
	_set_speed(0.0, false)
	if bench.ladder_demo.is_empty():
		bench.start_ladder_demo(4.0, 1, 0.0, height)
	else:
		bench.ladder_demo.playing = false
		bench.set_ladder_height(height)


func _view(view_name: String) -> void:
	var view: Array = VIEWS[view_name]
	bench.camera.position = view[0]
	bench.camera.look_at(view[1], Vector3.UP)
	bench.camera.fov = 34.0
	bench._diagnostic_view = 0


func _process(delta: float) -> void:
	# Pinned to the top right of the window (the parent is a CanvasLayer, so there are no anchors to lean on).
	position = Vector2(get_viewport_rect().size.x - size.x - 10.0, 10.0)
	if _scenario != &"":
		# Real time, so slow motion does not stretch the script's own clock out of step with the slider.
		_scenario_time += delta / maxf(Engine.time_scale, 0.01)
		var t := _scenario_time
		var target := 0.0
		match _scenario:
			&"run_stop":
				target = 5.0 if t < 3.0 else 0.0
				_scenario_label.text = "Start-Run-Stop  %.1f s" % t
				if t > 4.2: _scenario = &""
			&"ramp":
				target = clampf(t, 0.0, 6.0)
				_scenario_label.text = "Ramp 0-6 m/s  %.1f s" % t
				if t > 7.0: _scenario = &""
			&"steps":
				target = 1.2 if t < 2.0 else (3.0 if t < 4.0 else (5.0 if t < 6.0 else 0.0))
				_scenario_label.text = "Walk-Jog-Run  %.1f s" % t
				if t > 7.5: _scenario = &""
		_set_speed(target)
		if _scenario == &"":
			_scenario_label.text = ""
	var r: Dictionary = bench.locomotion_report
	var modifier = bench.locomotion_modifier
	var cover_line := "" if bench.cover_demo.is_empty() else "\ncover side %d (+1 right), yaw offset %.0f deg, crouch %.2f" % [bench.cover_side, rad_to_deg(bench.character_root.rotation.y), bench.crouch_modifier.depth]
	if not bench.stair_demo.is_empty() and not bench.stair_pose.is_empty():
		var sp: Dictionary = bench.stair_pose
		cover_line += "\nstair s %.2f / %.2f m  weight %.2f  step every %d tread(s)  pelvis %.2f m%s  feet planted %s/%s" % [float(bench.stair_demo.s), float(bench.stair_demo.exit), float(sp.weight), int(sp.step), float(sp.pelvis.height), "" if bool(sp.pelvis.ok) else " UNREACHABLE", (sp.feet[0] as Dictionary).planted, (sp.feet[1] as Dictionary).planted]
	if not bench.path_demo.is_empty():
		var pr: Dictionary = bench.path_demo.result
		cover_line += "\npath %s: rounded %d, min clearance %s m%s" % [bench.path_demo.kind, int(pr.rounded), "none near" if is_inf(float(pr.min_clearance)) else "%.3f" % float(pr.min_clearance), ("  MISMATCH: " + str(pr.mismatches[0])) if not pr.mismatches.is_empty() else ""]
	if not bench.ladder_demo.is_empty() and not bench.traversal_pose.is_empty():
		var tp: Dictionary = bench.traversal_pose
		cover_line += "\nladder %.2f / %.2f m  weight %.2f  hand rungs %s  foot rungs %s" % [float(bench.ladder_demo.climbed), float(bench.ladder_demo.length), float(tp.weight), tp.hand_rung, tp.foot_rung]
	if not bench.cover_demo.is_empty():
		var plan: Dictionary = bench.cover_plan
		cover_line += "\nintent: %s" % ("none (passive cover)" if plan.is_empty() else "authorized attack  mode %s  side %d  along %.2f lateral %.2f%s" % [CoverEdgeSelector.FiringMode.keys()[int(plan.mode)], int(plan.side), float(plan.along), float(plan.lateral), ("  MISMATCH " + str(plan.mismatch)) if not str(plan.mismatch).is_empty() else ""])
	_readout.text = "state %s\nfeed %.1f m/s, legs follow %.2f m/s\ngait blend %.2f (0 walk, 1 jog, 2 run)  loaded %.2f\ncadence %.2f cycles/s\ntwist %.0f  bank %.1f  pitch %.1f deg%s" % [bench.animation_controller.current_state, bench.preview_speed, r.speed, r.gait, r.loaded, r.cadence, modifier.twist_degrees if modifier != null else 0.0, r.bank, modifier.pitch_degrees if modifier != null else 0.0, cover_line]
