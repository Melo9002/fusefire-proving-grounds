@tool
extends CharacterRig

@onready var status_label: Label = get_node_or_null("UI/Status") as Label
@onready var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
var side_view := false
var preview_direction := Vector2(0, 1)
## Travel speed the preview feeds the production locomotion presentation (m/s). Walk, jog and run follow from the profile's thresholds.
var preview_speed := 1.3
## Yaw (radians) the character is turning toward at the game's turn rate while moving, or NAN. Set by the test panel's moving turns.
var turn_goal := NAN
## Cover bench (the test panel's Cover row): a synthetic wall with chosen edge distances. The side comes from the production CoverEdgeSelector.choose and the pose
## from the production CoverPostureProfile (yaw_offset, crouch_request), exactly what UnitVisualAdapter uses in the game. Empty = no cover scenario.
var cover_demo := {}
var cover_side := 0
## Target-aware firing in the bench: the scripted AUTHORIZED target (a position relative to the unit, in the unit's own frame at rest: +z toward the wall, -x its right) and
## the plan the production CoverEdgeSelector.plan_attack makes from it. Empty = passive cover. (In the game the same plan comes from the attack result's target position.)
var cover_target: Variant = null
var cover_plan := {}
var _cover_found := {}
var _bench_heading := 0.0
var cover_diagnostics := false
var _cover_group: Node3D
var _cover_lines: MeshInstance3D
var preview_turning := false
var _preview_pivot: Node3D
var _preview_turn_time := 0.0
var _orbit_dragging := false
const ORBIT_FOCUS := Vector3(0, 0.85, 0)

# --- Hand-contact diagnostics (workbench only; see presentation/diagnostics/). Nothing here is created
# until H is pressed, and nothing here changes how the rig poses itself.
var _diagnostics: HandContactDiagnostics
## Diagnostic camera views: 0 is the workbench's own camera (orbit and C still work there).
const DIAGNOSTIC_VIEW_NAMES := ["workbench camera", "full body", "dominant hand close-up", "support hand close-up", "both hands and weapon"]
var _diagnostic_view := 0
## Crouch presets drive the existing CoverCrouchModifier the way UnitVisualAdapter does, with its ramp speeds.
## They exist so crouch, kneel and aim-while-crouched can be inspected here; there is no cover yaw.
const POSE_PRESET_NAMES := ["standing", "crouch", "half-kneel"]
var _pose_preset := 0

func _preview_locomotion(direction: Vector2) -> void:
	preview_turning = false
	if is_instance_valid(_preview_pivot):
		_preview_pivot.rotation.y = 0.0
	preview_direction = direction
	locomotion_direction = direction
	if animation_controller.current_state != &"move":
		animation_controller.play(&"move")
	_update_status()

func _ready() -> void:
	_build_character()
	_build_weapon_attachment()
	_build_arm_ik()
	if Engine.is_editor_hint():
		await get_tree().process_frame
		await get_tree().process_frame
		_align_weapon_to_aim()
		_update_weapon_pose()
		return
	_build_animation_controller()
	skeleton.skeleton_updated.connect(_align_weapon_to_aim)
	camera.look_at(Vector3(0.42, 0.72, 0.0), Vector3.UP)
	_update_status()
	# The interactive locomotion test bench (speed slider, gaits, turns, transitions, views, readout) drives this same rig.
	var test_panel := LocomotionTestPanel.new()
	get_node("UI").add_child(test_panel)
	test_panel.setup(self)
	# BoneAttachment3D receives its final pose after the skeleton modifier pass.
	# Wait for that pose, then establish the proof's authored rifle orientation.
	await get_tree().process_frame
	await get_tree().process_frame
	_align_weapon_to_aim()
	if "--side-view" in OS.get_cmdline_user_args():
		camera.position = Vector3(3.4, 1.3, 0.1)
		camera.look_at(Vector3(0, 0.85, 0), Vector3.UP)
	if "--auto-sequence" in OS.get_cmdline_user_args():
		animation_controller.play_sequence()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_orbit_dragging = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _orbit_dragging:
		var offset := camera.position - ORBIT_FOCUS
		var radius := offset.length()
		var yaw: float = atan2(offset.x, offset.z) - event.relative.x * 0.005
		var elevation := clampf(asin(offset.y / radius) + event.relative.y * 0.005, -0.15, 1.35)
		camera.position = ORBIT_FOCUS + Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * radius
		camera.look_at(ORBIT_FOCUS, Vector3.UP)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_1, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0, KEY_V, KEY_B, KEY_N, KEY_L, KEY_R, KEY_P, KEY_M, KEY_E, KEY_Q, KEY_K, KEY_SPACE]:
			preview_turning = false
			if is_instance_valid(_preview_pivot):
				_preview_pivot.rotation.y = 0.0
		match event.keycode:
			KEY_H:
				_toggle_diagnostics()
			KEY_J:
				if is_instance_valid(_diagnostics): _diagnostics.set_labels_visible(not _diagnostics.labels_visible)
				_update_status()
			KEY_G:
				_mark_contact_reference()
			KEY_Z:
				_cycle_pose_preset()
			KEY_X:
				_cycle_diagnostic_view()
			KEY_R:
				# Pickup from the floor: the passenger lies a metre in front (the same call the game makes with the rescued actor's place).
				finish_interaction_now()
				end_carry()
				begin_pickup(character_root.global_position + character_root.global_basis.orthonormalized().z * 1.0)
				_update_status()
			KEY_Q:
				# Release: lower the passenger to the floor and let go. The passenger is left lying so it can be looked at.
				if is_instance_valid(carry_passenger) and not interaction_active():
					keep_released_passenger = true
					begin_release()
				_update_status()
			KEY_K:
				# Carrier-death interruption: the tactical layer has put the passenger down, so the visual one is dropped at once.
				end_carry()
				animation_controller.play(&"rifle_idle")
				_update_status()
			KEY_O:
				rescue_interaction.paused = not rescue_interaction.paused
				_update_status()
			KEY_COMMA, KEY_PERIOD:
				if interaction_active():
					rescue_interaction.paused = true
					rescue_interaction.scrub(rescue_interaction.time + (0.1 if event.keycode == KEY_PERIOD else -0.1))
				_update_status()
			KEY_Y:
				passenger_motion_enabled = not passenger_motion_enabled
				_update_status()
			KEY_P:
				finish_interaction_now()
				animation_controller.play(&"carry_idle")
			KEY_M:
				finish_interaction_now()
				animation_controller.play(&"carry_move")
			KEY_E:
				finish_interaction_now()
				animation_controller.play(&"boarding")
			KEY_7:
				animation_controller.play(&"cover_low")
			KEY_8:
				animation_controller.play(&"cover_high")
			KEY_9:
				animation_controller.play(&"shoot_left")
			KEY_0:
				animation_controller.play(&"shoot_right")
			KEY_V:
				animation_controller.play(&"vault")
			KEY_B:
				animation_controller.play(&"climb")
			KEY_N:
				animation_controller.play(&"descend")
			KEY_L:
				animation_controller.play(&"land")
			KEY_UP:
				_preview_locomotion(Vector2(0, 1))
			KEY_DOWN:
				_preview_locomotion(Vector2(0, -1))
			KEY_LEFT:
				_preview_locomotion(Vector2(1, 0))   # x is toward the character's left
			KEY_RIGHT:
				_preview_locomotion(Vector2(-1, 0))
			KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
				preview_speed = clampf(preview_speed + (-0.5 if event.keycode == KEY_BRACKETLEFT else 0.5), 0.0, 8.0)
				_update_status()
			KEY_T:
				_preview_locomotion(Vector2(0, 1))
				if not is_instance_valid(_preview_pivot):
					_preview_pivot = Node3D.new()
					_preview_pivot.name = "LocomotionPreviewPivot"
					add_child(_preview_pivot)
					character_root.reparent(_preview_pivot)
				_preview_turn_time = 0.0
				preview_turning = true
				_update_status()
			KEY_I:
				ik_enabled = not ik_enabled
				arm_ik.active = ik_enabled
				_update_status()
			KEY_C:
				side_view = not side_view
				camera.position = Vector3(3.4, 1.3, 0.1) if side_view else Vector3(2.8, 1.65, 3.55)
				camera.look_at(Vector3(0, 0.85, 0) if side_view else Vector3(0.42, 0.72, 0), Vector3.UP)
			KEY_ESCAPE:
				get_tree().quit()
			KEY_1:
				animation_controller.play(&"rifle_idle")
			KEY_2:
				_preview_locomotion(Vector2(0, 1))
			KEY_3:
				animation_controller.play(&"aim")
			KEY_4:
				animation_controller.play(&"shoot")
			KEY_5:
				animation_controller.play(&"hit")
			KEY_6:
				animation_controller.play(&"defeat")
			KEY_SPACE:
				animation_controller.play_sequence()


func _update_status() -> void:
	if not is_instance_valid(status_label):
		return
	var state_name: StringName = animation_controller.current_state if is_instance_valid(animation_controller) else &"setup"
	# Keep controls in the demo so individual poses are easy to inspect.
	status_label.text = "STATE: %s    IK: %s\n1 Idle  2 Move  3 Aim  4 Shoot  5 Hit  6 Defeat\nArrows: forward/back/strafe    T: turn preview\n[ / ]: pace %.1f m/s    Direction: %s\nRMB drag: orbit    C: camera preset\nSpace: sequence    I: IK    Esc: close\nLocomotion preview is in place" % [state_name, "ON" if ik_enabled else "OFF", preview_speed, "turning" if preview_turning else str(preview_direction)]
	status_label.text += "\n7/8: low/high cover    9/0: expose left/right\nV: vault    B: climb    N: descend    L: landing"
	status_label.text += "\nR: pickup    P: carry idle    M: carry move    E: boarding    Q: release    K: carrier-death drop"
	status_label.text += "\nO: pause timeline    , / .: scrub 0.1 s    Y: passenger motion %s    Rescue: %s" % ["on" if passenger_motion_enabled else "off", ("%s %.2f/%.2f s %s" % [RescueInteraction.Kind.keys()[rescue_interaction.kind], rescue_interaction.time, rescue_interaction.duration(), rescue_interaction.phase_name()]) if interaction_active() else "-"]
	var diagnostics_on := is_instance_valid(_diagnostics) and _diagnostics.enabled
	status_label.text += "\nH: hand diagnostics %s    J: labels    G: mark contact    Z: pose %s    X: view %s" % ["ON" if diagnostics_on else "off", POSE_PRESET_NAMES[_pose_preset], DIAGNOSTIC_VIEW_NAMES[_diagnostic_view]]


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if preview_turning and animation_controller.current_state == &"move":
		_preview_turn_time += _delta
		var target_yaw := PI if int(_preview_turn_time / 2.0) % 2 == 0 else 0.0
		_preview_pivot.rotation.y = rotate_toward(_preview_pivot.rotation.y, target_yaw, TAU * _delta)
		var local_travel := _preview_pivot.basis.inverse() * Vector3.FORWARD
		preview_direction = Vector2(local_travel.x, local_travel.z)
		locomotion_direction = preview_direction
	# The production locomotion presentation, fed a preview speed while a movement state is playing (and zero otherwise, which settles it).
	var walking: bool = animation_controller.current_state in [&"move", &"carry_move"] and not interaction_active()
	var heading_rate := 0.0
	if not is_nan(turn_goal):
		var yaw_before := character_root.rotation.y
		character_root.rotation.y = rotate_toward(yaw_before, turn_goal, deg_to_rad(360.0) * _delta)
		heading_rate = angle_difference(yaw_before, character_root.rotation.y) / maxf(_delta, 0.0001)
		if is_equal_approx(character_root.rotation.y, turn_goal):
			turn_goal = NAN
	update_locomotion_presentation(preview_speed if walking else 0.0, heading_rate, _delta)
	_apply_cover_demo(_delta)
	_advance_ladder_demo(_delta)
	_advance_stair_demo(_delta)
	_ramp_pose_preset(_delta)
	_follow_diagnostic_view()
	_update_weapon_pose()


func _on_animation_state_changed(state_name: StringName) -> void:
	var rescue_pose := state_name in [&"pickup", &"carry_idle", &"carry_move", &"boarding"] or interaction_active()
	if rescue_pose:
		begin_carry()   # the same passenger, contacts, lean and slung weapon the game uses
	elif is_instance_valid(carry_passenger):
		end_carry()
		arm_ik.active = ik_enabled
	_update_status()
	super._on_animation_state_changed(state_name)

func _align_weapon_to_aim() -> void:
	if is_instance_valid(carry_passenger):
		return
	super._align_weapon_to_aim()

func _update_weapon_pose() -> void:
	if is_instance_valid(carry_passenger):
		_apply_carry_posture()
		if interaction_active():
			_update_status()
		return
	super._update_weapon_pose()


## H: switches the hand-contact diagnostics (overlay and readout) on or off. They are created on first use.
func _toggle_diagnostics() -> void:
	if not is_instance_valid(_diagnostics):
		_diagnostics = HandContactDiagnostics.attach(self)
		if _diagnostics == null:
			push_warning("Hand-contact diagnostics are unavailable for this rig")
			return
	_diagnostics.set_enabled(not _diagnostics.enabled)
	_update_status()

## G: marks the current hand contact (palms and wrists in the weapon's frame) as the reference for the shift readout.
func _mark_contact_reference() -> void:
	if is_instance_valid(_diagnostics) and _diagnostics.enabled:
		_diagnostics.mark_reference()

## Z: standing, then crouch, then half-kneel. Sets only the public inputs of the existing crouch modifier.
func _cycle_pose_preset() -> void:
	_pose_preset = (_pose_preset + 1) % POSE_PRESET_NAMES.size()
	_update_status()

func _pose_preset_depth() -> float:
	if crouch_modifier == null:
		return 0.0
	match _pose_preset:
		1: return crouch_modifier.clamp_depth(0.41)   # about the depth for hiding behind 1.15 m cover
		2: return crouch_modifier.max_depth           # what the adapter asks for behind cover too low to crouch behind
	return 0.0

func _ramp_pose_preset(delta: float) -> void:
	if crouch_modifier == null or Engine.is_editor_hint() or not cover_demo.is_empty():
		return
	crouch_modifier.depth = move_toward(crouch_modifier.depth, _pose_preset_depth(), UnitVisualAdapter.CROUCH_SPEED * delta)
	crouch_modifier.kneel = move_toward(crouch_modifier.kneel, 1.0 if _pose_preset == 2 else 0.0, UnitVisualAdapter.KNEEL_SPEED * delta)

## X: cycles fixed diagnostic camera views. The close-ups follow the hands as the pose changes.
func _cycle_diagnostic_view() -> void:
	_diagnostic_view = (_diagnostic_view + 1) % DIAGNOSTIC_VIEW_NAMES.size()
	if _diagnostic_view == 0:
		camera.position = Vector3(2.8, 1.65, 3.55)
		camera.look_at(Vector3(0.42, 0.72, 0), Vector3.UP)
		camera.fov = 34.0
	_update_status()

func _follow_diagnostic_view() -> void:
	if _diagnostic_view == 0 or not is_instance_valid(camera) or not is_instance_valid(weapon):
		return
	var facing := character_root.global_basis.orthonormalized()
	var firing := weapon.to_global(handling.firing_grip)
	var support := weapon.to_global(handling.support_grip)
	var focus := ORBIT_FOCUS
	var offset := Vector3.ZERO
	camera.fov = 30.0
	match _diagnostic_view:
		1:
			focus = Vector3(0, 0.82, 0)
			offset = facing * Vector3(-1.4, 0.55, 2.4)
		2:
			focus = firing
			offset = facing * Vector3(-0.50, 0.14, 0.34)
			camera.fov = 26.0
		3:
			focus = support
			offset = facing * Vector3(0.50, 0.14, 0.34)
			camera.fov = 26.0
		4:
			focus = (firing + support) * 0.5
			offset = facing * Vector3(-0.85, 0.30, 0.75)
	camera.position = focus + offset
	camera.look_at(focus, Vector3.UP)


## Starts (or, with an empty spec, ends) a cover scenario. spec: full (bool), height, left / right edge distance (m) and left_ok / right_ok (usable), aim (bool).
func set_cover_demo(spec: Dictionary) -> void:
	cover_demo = spec
	if is_instance_valid(_cover_group):
		_cover_group.queue_free()
	_cover_group = null
	if spec.is_empty():
		cover_side = 0
		animation_controller.play(&"rifle_idle")
		return
	cover_target = null
	cover_plan = {}
	rotation.y = 0.0
	_bench_heading = 0.0
	_cover_found = {"left": {"distance": spec.left, "usable": spec.left_ok}, "right": {"distance": spec.right, "usable": spec.right_ok}, "normal": Vector3(0, 0, 1), "tangent": Vector3(-1, 0, 0)}
	cover_side = CoverEdgeSelector.choose(_cover_found, cover_side, cover_profile)
	animation_controller.play(&"aim" if spec.aim else &"rifle_idle")
	_build_cover_visuals()


## Authorizes (a position) or ends (null) an attack from the current cover scenario. The body turns to face the target (the facing change is absorbed into the cover
## yaw offset exactly as UnitVisualAdapter does, so nothing snaps), the plan picks the posture, and ending it returns to the passive cover pose.
func set_cover_target(target: Variant) -> void:
	if cover_demo.is_empty():
		return
	cover_target = target
	if target == null:
		cover_plan = {}
		_turn_to_heading(0.0)
		animation_controller.play(&"aim" if cover_demo.aim else &"rifle_idle")
		return
	cover_plan = CoverEdgeSelector.plan_attack(_cover_found, bool(cover_demo.full), target as Vector3, int(cover_plan.get("side", 0)), cover_side, 0.5, cover_profile)
	_turn_to_heading(atan2((target as Vector3).x, (target as Vector3).z))
	animation_controller.play(&"aim")


## Shows the plan's shot (shoot / shoot_left / shoot_right), then back to the aimed pose.
func fire_cover_shot() -> void:
	if cover_plan.is_empty():
		return
	var shot := &"shoot"
	match int(cover_plan.mode):
		CoverEdgeSelector.FiringMode.AROUND_LEFT: shot = &"shoot_left"
		CoverEdgeSelector.FiringMode.AROUND_RIGHT: shot = &"shoot_right"
		CoverEdgeSelector.FiringMode.PROTECTED: shot = &"shoot_left" if cover_side < 0 else &"shoot_right"
	animation_controller.play(shot)
	await get_tree().create_timer(0.7).timeout
	if not cover_plan.is_empty():
		animation_controller.play(&"aim")


func _turn_to_heading(heading: float) -> void:
	var change := angle_difference(rotation.y, heading)
	rotation.y = heading
	character_root.rotation.y = wrapf(character_root.rotation.y - change, -PI, PI)
	_bench_heading = heading


func _build_cover_visuals() -> void:
	var spec := cover_demo
	_cover_group = Node3D.new()
	_cover_group.name = "CoverBench"
	_cover_group.top_level = true   # the wall stays put while the unit turns toward a target
	add_child(_cover_group)
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	var width: float = float(spec.left) + float(spec.right)
	box.size = Vector3(width, float(spec.height), 0.25)
	wall.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.55, 0.5, 0.42)
	wall.material_override = material
	# The character faces +z with its right toward -x: the right edge is at x = -right, the left edge at x = +left.
	wall.position = Vector3((float(spec.left) - float(spec.right)) * 0.5, float(spec.height) * 0.5, 0.75)
	_cover_group.add_child(wall)
	for edge in ["left", "right"]:
		var marker := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.08
		ball.height = 0.16
		marker.mesh = ball
		var chosen: bool = (edge == "left" and cover_side < 0) or (edge == "right" and cover_side > 0)
		var color := Color(0.2, 0.9, 0.3) if spec[edge + "_ok"] else Color(0.9, 0.25, 0.2)
		var edge_material := StandardMaterial3D.new()
		edge_material.albedo_color = color
		edge_material.emission_enabled = true
		edge_material.emission = color
		edge_material.emission_energy_multiplier = 1.6 if chosen else 0.4
		marker.material_override = edge_material
		marker.scale = Vector3.ONE * (1.8 if chosen else 1.0)
		marker.visible = cover_diagnostics
		marker.name = "Edge_" + edge
		marker.position = Vector3((float(spec.left) if edge == "left" else -float(spec.right)), float(spec.height) + 0.1, 0.62)
		_cover_group.add_child(marker)
	_cover_lines = MeshInstance3D.new()
	_cover_lines.mesh = ImmediateMesh.new()
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	_cover_lines.material_override = line_material
	_cover_lines.top_level = true
	_cover_group.add_child(_cover_lines)


func _apply_cover_demo(delta: float) -> void:
	if cover_demo.is_empty() or crouch_modifier == null or Engine.is_editor_hint():
		return
	var spec := cover_demo
	var blend := weapon_blend()
	var request := cover_profile.crouch_request(bool(spec.full), float(spec.height), blend, crouch_modifier.standing_head_height)
	crouch_modifier.depth = move_toward(crouch_modifier.depth, crouch_modifier.clamp_depth(request), cover_profile.crouch_speed * delta)
	var kneel_target := clampf((request - crouch_modifier.max_depth) / 0.08, 0.0, 1.0)
	crouch_modifier.kneel = move_toward(crouch_modifier.kneel, kneel_target, cover_profile.kneel_speed * delta)
	var yaw_goal := cover_profile.yaw_offset(bool(spec.full), cover_side, blend)
	if not cover_plan.is_empty():
		yaw_goal = cover_profile.attack_yaw_offset(cover_side, int(cover_plan.side), blend)
	character_root.rotation.y = rotate_toward(character_root.rotation.y, yaw_goal, deg_to_rad(cover_profile.turn_degrees_per_second) * delta)
	if is_instance_valid(_cover_group):
		for edge in ["Edge_left", "Edge_right"]:
			var marker := _cover_group.get_node_or_null(edge) as Node3D
			if marker != null:
				marker.visible = cover_diagnostics
		_draw_cover_lines()


## Optional overlay: facing (blue), the weapon's direction (red), the wall's normal (green). Off during ordinary use.
func _draw_cover_lines() -> void:
	var mesh := _cover_lines.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if not cover_diagnostics:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var chest := global_position + Vector3(0, 1.2, 0)
	var facing := character_root.global_basis.orthonormalized().z
	var segments := [[chest, chest + facing * 1.2, Color(0.3, 0.5, 1.0)], [weapon.global_position, weapon.global_position + muzzle_socket.global_basis.z.normalized() * 1.5, Color(1.0, 0.25, 0.2)], [global_position + Vector3(0, 0.6, 0.62), global_position + Vector3(0, 0.6, -0.4), Color(0.3, 1.0, 0.4)]]
	if cover_target != null:
		segments.append([chest, chest + (cover_target as Vector3).normalized() * 2.5, Color(1.0, 0.9, 0.2)])   # the authorized attack direction
	for segment in segments:
		mesh.surface_set_color(segment[2])
		mesh.surface_add_vertex(segment[0])
		mesh.surface_set_color(segment[2])
		mesh.surface_add_vertex(segment[1])
	mesh.surface_end()


## ---- Environmental traversal bench (ladder). The pose is the production TraversalSolver / TraversalPoseModifier / hand contacts: the bench only supplies the height the
## game would supply (the unit's tactical height up the ladder) and a ladder to look at. The character stays at the origin and the ladder slides past it.
var ladder_demo := {}
var traversal_diagnostics := false
var _ladder_group: Node3D
var _ladder_markers: Array[MeshInstance3D] = []


## Starts a ladder scenario: `length` the ladder's rise (m), `direction` +1 climb / -1 descend, `rate` m/s (0 = hold), `climbed` the starting height.
func start_ladder_demo(length: float, direction: int, rate: float, climbed := -1.0) -> void:
	end_ladder_demo()
	ladder_demo = {"length": length, "direction": direction, "rate": rate, "climbed": (0.0 if direction > 0 else length) if climbed < 0.0 else climbed, "playing": rate > 0.0}
	begin_traversal(&"ladder", length, direction)
	_build_ladder_visuals()
	set_traversal_progress(float(ladder_demo.climbed))
	animation_controller.play(&"rifle_idle")


func end_ladder_demo() -> void:
	ladder_demo = {}
	if is_instance_valid(_ladder_group):
		_ladder_group.queue_free()
	_ladder_group = null
	_ladder_markers.clear()
	end_traversal()


func set_ladder_height(climbed: float) -> void:
	if ladder_demo.is_empty():
		return
	ladder_demo.climbed = clampf(climbed, 0.0, float(ladder_demo.length))
	set_traversal_progress(float(ladder_demo.climbed))


func _advance_ladder_demo(delta: float) -> void:
	if ladder_demo.is_empty():
		return
	if bool(ladder_demo.playing):
		var next: float = float(ladder_demo.climbed) + float(ladder_demo.rate) * float(ladder_demo.direction) * delta
		var length: float = float(ladder_demo.length)
		if next >= length or next <= 0.0:
			ladder_demo.playing = false
		set_ladder_height(next)
	else:
		set_traversal_progress(float(ladder_demo.climbed))
	if is_instance_valid(_ladder_group):
		_ladder_group.position.y = -float(ladder_demo.climbed)
		for marker in _ladder_markers:
			marker.visible = traversal_diagnostics
		_update_ladder_markers()


func _build_ladder_visuals() -> void:
	var profile := traversal_profile
	var length: float = ladder_demo.length
	_ladder_group = Node3D.new()
	_ladder_group.name = "LadderBench"
	_ladder_group.top_level = true
	add_child(_ladder_group)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.87, 0.71, 0.3)
	var plane := profile.ladder_plane_ahead
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(0.06, length, 0.06)
		rail.mesh = rail_mesh
		rail.material_override = material
		rail.position = Vector3(0.35 * side, length * 0.5, plane)
		_ladder_group.add_child(rail)
	for index in TraversalSolver.rung_count_for(profile, length):
		var rung := MeshInstance3D.new()
		var rung_mesh := BoxMesh.new()
		rung_mesh.size = Vector3(0.76, 0.045, 0.045)
		rung.mesh = rung_mesh
		rung.material_override = material
		rung.position = Vector3(0.0, TraversalSolver.rung_height(profile, index, length), plane)
		_ladder_group.add_child(rung)
	var deck := MeshInstance3D.new()
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(3.0, 0.2, 3.0)
	deck.mesh = deck_mesh
	var deck_material := StandardMaterial3D.new()
	deck_material.albedo_color = Color(0.45, 0.47, 0.5)
	deck.material_override = deck_material
	deck.position = Vector3(0.0, length - 0.1, plane + 1.5)
	_ladder_group.add_child(deck)
	var colours := [Color(1, 0.2, 0.2), Color(0.2, 0.4, 1), Color(1, 0.6, 0.2), Color(0.3, 0.8, 1)]   # L hand, R hand, L foot, R foot
	for i in 4:
		var marker := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.04
		ball.height = 0.08
		marker.mesh = ball
		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color = colours[i]
		marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = marker_material
		marker.top_level = true
		marker.visible = false
		add_child(marker)
		_ladder_markers.append(marker)


## Optional diagnostics: the four contact targets (left hand red, right hand blue, left foot orange, right foot cyan).
func _update_ladder_markers() -> void:
	if _ladder_markers.size() < 4 or traversal_pose.is_empty():
		return
	for side in 2:
		_ladder_markers[side].global_position = character_root.to_global(traversal_pose.hands[side])
		_ladder_markers[2 + side].global_position = character_root.to_global(traversal_pose.feet[side])


## ---- Stair bench: the production StairModel / StairFootPlanner / leg IK / pelvis, driven by the progress the game would supply (the unit's place along the stair). The character
## stays at the origin and the stair slides past it, exactly as for the ladder. Planned footholds (green) against the ankle bones (red), tread outlines, optional.
var stair_demo := {}
var stair_diagnostics := false
var _stair_group: Node3D
var _stair_markers: Array[MeshInstance3D] = []
var _stair_actual: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]


## `rise` and `depth` of one tread (m), `count` treads, `ascending`, `rate` m/s along the stair (0 = hold at `start`), `start` the starting distance (-1 = the walk's start).
func start_stair_demo(rise: float, depth: float, count: int, ascending: bool, rate: float, start := -1.0) -> void:
	end_stair_demo()
	var model := StairModel.new()
	model.direction = Vector3.BACK
	model.tread_depth = depth
	model.tread_rise = rise
	model.first_riser = 1.0
	model.count = count
	var enter := 0.0
	var exit := model.riser_s(count)
	var s0 := (enter if ascending else exit) if start < 0.0 else start
	stair_demo = {"model": model, "ascending": ascending, "rate": rate, "s": s0, "enter": enter, "exit": exit, "playing": rate > 0.0, "step_once": false}
	_build_stair_visuals()
	animation_controller.play(&"rifle_idle")
	_set_stair_state(s0)


func end_stair_demo() -> void:
	stair_demo = {}
	if is_instance_valid(_stair_group):
		_stair_group.queue_free()
	_stair_group = null
	_stair_markers.clear()
	end_stairs()


## One frame at the bench's own time step (frame stepping).
func step_stair_demo_frame() -> void:
	if not stair_demo.is_empty():
		stair_demo.playing = false
		stair_demo.step_once = true


func _stair_travel(model: StairModel, s: float) -> Vector3:
	return model.direction * s + Vector3.UP * stair_profile_height(model, s)


func stair_profile_height(model: StairModel, s: float) -> float:
	return model.ride_path_height_at(s, stair_profile.riser_ramp)


func _set_stair_state(s: float) -> void:
	var base: StairModel = stair_demo.model
	var travel := _stair_travel(base, s)
	# The stair slides under the fixed character: a copy of the model whose low point is the base's minus the travel.
	var shifted := StairModel.new()
	shifted.low = base.low - travel
	shifted.direction = base.direction
	shifted.tread_depth = base.tread_depth
	shifted.tread_rise = base.tread_rise
	shifted.first_riser = base.first_riser
	shifted.count = base.count
	if stair_state.is_empty():
		begin_stairs(shifted, bool(stair_demo.ascending), float(stair_demo.enter), float(stair_demo.exit))
	stair_state.model = shifted
	stair_state.step = 0   # re-plan the holds against the shifted model
	set_stair_progress(s, float(stair_demo.rate) if float(stair_demo.rate) > 0.0 else 1.0)
	if is_instance_valid(_stair_group):
		_stair_group.position = -travel


func _advance_stair_demo(delta: float) -> void:
	if stair_demo.is_empty():
		return
	var advance := bool(stair_demo.playing) or bool(stair_demo.step_once)
	if advance:
		var step_delta := delta if bool(stair_demo.playing) else 1.0 / 60.0
		var direction := 1.0 if bool(stair_demo.ascending) else -1.0
		var next: float = float(stair_demo.s) + float(stair_demo.rate if float(stair_demo.rate) > 0.0 else 1.0) * direction * step_delta
		if next >= float(stair_demo.exit) or next <= float(stair_demo.enter):
			stair_demo.playing = false
			next = clampf(next, float(stair_demo.enter), float(stair_demo.exit))
		stair_demo.s = next
		stair_demo.step_once = false
	_set_stair_state(float(stair_demo.s))
	if not stair_pose.is_empty() and _stair_markers.size() == 4:
		for foot in 2:
			_stair_markers[foot].global_position = (stair_pose.feet[foot] as Dictionary).position
			_stair_markers[foot].visible = stair_diagnostics
			_stair_markers[2 + foot].visible = stair_diagnostics
			_stair_markers[2 + foot].global_position = _stair_actual[foot]


func set_stair_demo_s(s: float) -> void:
	if stair_demo.is_empty():
		return
	stair_demo.playing = false
	stair_demo.s = clampf(s, float(stair_demo.enter), float(stair_demo.exit))


func _build_stair_visuals() -> void:
	var model: StairModel = stair_demo.model
	_stair_group = Node3D.new()
	_stair_group.name = "StairBench"
	_stair_group.top_level = true
	add_child(_stair_group)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.45, 0.47, 0.5)
	for k in range(0, model.count + 1):
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		var span_end := model.riser_s(k + 1) if k < model.count else model.riser_s(model.count) + 2.0
		var span_start := model.riser_s(k) if k > 0 else -2.0
		var top := model.tread_top(k) if k > 0 else 0.0
		mesh.size = Vector3(1.4, maxf(top, 0.02), span_end - span_start)
		box.mesh = mesh
		box.material_override = material
		box.position = Vector3(0.0, top * 0.5 if k > 0 else -0.01, (span_start + span_end) * 0.5)
		if k == 0:
			mesh.size = Vector3(1.4, 0.02, span_end - span_start)
		_stair_group.add_child(box)
	var colours := [Color(0.2, 1, 0.3), Color(0.4, 1, 0.8), Color(1, 0.2, 0.2), Color(1, 0.6, 0.2)]   # planned L, planned R, actual L, actual R
	for i in 4:
		var marker := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.035
		ball.height = 0.07
		marker.mesh = ball
		var marker_material := StandardMaterial3D.new()
		marker_material.albedo_color = colours[i]
		marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		marker.material_override = marker_material
		marker.top_level = true
		marker.visible = false
		add_child(marker)
		_stair_markers.append(marker)
	if skeleton != null and not skeleton.skeleton_updated.is_connected(_record_stair_ankles):
		skeleton.skeleton_updated.connect(_record_stair_ankles)


func _record_stair_ankles() -> void:
	if stair_demo.is_empty():
		return
	for foot in 2:
		var bone := skeleton.find_bone("mixamorig_LeftFoot" if foot == 0 else "mixamorig_RightFoot")
		if bone >= 0:
			_stair_actual[foot] = skeleton.global_transform * skeleton.get_bone_global_pose(bone).origin


## ---- Path corridor bench: the production PathRefiner on a synthetic obstacle layout. The tactical route (white), the smoothed walk (cyan), the obstacle footprints (orange) and the
## character footprint (a circle of the body radius) along the walk; a mismatch is written in the readout, never "fixed".
var path_demo := {}
var _path_group: Node3D


func show_path_demo(kind: String) -> void:
	hide_path_demo()
	var radius := 0.319
	var gap_ok := 2.0 * radius + 0.1
	var gap_bad := 2.0 * radius - 0.1
	var parts: Array = []
	var route := PackedVector3Array([Vector3(-3, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 3)])
	match kind:
		"open":
			pass
		"wall":
			parts = [AABB(Vector3(-2.5, 0, -0.9), Vector3(2.0, 2, 0.4))]
		"corner":
			parts = [AABB(Vector3(-3, 0, 0.34), Vector3(2.66, 2, 2.66))]
			route = PackedVector3Array([Vector3(0, 0, 0), Vector3(3, 0, 0), Vector3(3, 0, 3)])
			parts = [AABB(Vector3(0.0, 0, 0.34), Vector3(2.66, 2, 2.66))]
		"narrow":
			parts = [AABB(Vector3(-3, 0, -2.0 - gap_ok * 0.5), Vector3(3.5, 2, 2.0)), AABB(Vector3(-3, 0, gap_ok * 0.5), Vector3(3.5, 2, 2.0))]
			route = PackedVector3Array([Vector3(-3, 0, 0), Vector3(1.5, 0, 0), Vector3(1.5, 0, 2)])
		"too_narrow":
			parts = [AABB(Vector3(-3, 0, -2.0 - gap_bad * 0.5), Vector3(3.5, 2, 2.0)), AABB(Vector3(-3, 0, gap_bad * 0.5), Vector3(3.5, 2, 2.0))]
			route = PackedVector3Array([Vector3(-3, 0, 0), Vector3(1.5, 0, 0)])
		"column":
			parts = [AABB(Vector3(-0.24, 0, 0.76), Vector3(0.48, 2, 0.48))]
			route = PackedVector3Array([Vector3(-3, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 3)])
	var profile := PathPresentationProfile.new()
	profile.enabled = true
	var result := PathRefiner.refine(route, parts, radius, 1.8, profile)
	path_demo = {"kind": kind, "result": result, "parts": parts, "route": route}
	_path_group = Node3D.new()
	_path_group.name = "PathBench"
	_path_group.top_level = true
	add_child(_path_group)
	for part: AABB in parts:
		var box := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(part.size.x, 0.05, part.size.z)
		box.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(1.0, 0.55, 0.15)
		box.material_override = material
		box.position = part.get_center() * Vector3(1, 0, 1) + Vector3(0, 0.03, 0)
		_path_group.add_child(box)
	var lines := MeshInstance3D.new()
	var immediate := ImmediateMesh.new()
	lines.mesh = immediate
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	lines.material_override = line_material
	_path_group.add_child(lines)
	_draw_polyline(immediate, route, Color(1, 1, 1), 0.06)
	_draw_polyline(immediate, result.path, Color(0.2, 0.9, 1.0), 0.09)
	# The character's footprint along the walk, every 0.3 m.
	var walked := result.path as PackedVector3Array
	var travelled := 0.0
	var next_at := 0.0
	for i in range(1, walked.size()):
		var segment := walked[i].distance_to(walked[i - 1])
		while next_at <= travelled + segment:
			var along := (next_at - travelled) / maxf(segment, 0.0001)
			_footprint(walked[i - 1].lerp(walked[i], along), radius)
			next_at += 0.3
		travelled += segment


func hide_path_demo() -> void:
	path_demo = {}
	if is_instance_valid(_path_group):
		_path_group.queue_free()
	_path_group = null


func _draw_polyline(mesh: ImmediateMesh, points: PackedVector3Array, colour: Color, lift: float) -> void:
	mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	for point in points:
		mesh.surface_set_color(colour)
		mesh.surface_add_vertex(Vector3(point.x, lift, point.z))
	mesh.surface_end()


func _footprint(center: Vector3, radius: float) -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.01
	torus.outer_radius = radius
	ring.mesh = torus
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.3, 1.0, 0.4)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = material
	ring.position = Vector3(center.x, 0.02, center.z)
	ring.scale = Vector3(1, 0.1, 1)
	_path_group.add_child(ring)
