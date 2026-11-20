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
	_readout.text = "state %s\nfeed %.1f m/s, legs follow %.2f m/s\ngait blend %.2f (0 walk, 1 jog, 2 run)  loaded %.2f\ncadence %.2f cycles/s\ntwist %.0f  bank %.1f  pitch %.1f deg%s" % [bench.animation_controller.current_state, bench.preview_speed, r.speed, r.gait, r.loaded, r.cadence, modifier.twist_degrees if modifier != null else 0.0, r.bank, modifier.pitch_degrees if modifier != null else 0.0, cover_line]
