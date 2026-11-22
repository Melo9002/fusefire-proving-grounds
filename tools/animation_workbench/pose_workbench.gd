@tool
extends Node3D
## The animation workbench: a HOST of the shared character architecture, like the tactical adapter but for inspection. It drives a CharacterRig (its child) and that rig's CharacterPresenter exactly as the game does
## (presenter tick, then the action stage, then the rig's weapon pose), and adds the test panel, the cover and ladder and stair benches and the diagnostics around it.

## Where this host's CharacterRig child is (the scene's "Rig" node by default).
@export var rig_path := NodePath("Rig")
## Which character's rig to inspect: a key of CHARACTER_RIGS, or empty for the rig this scene carries (MIRA). `--character=<key>` on the command line chooses one too. The same host, panel and diagnostics serve every
## character; only the rig scene differs (its model, rig profile, handling and arm configuration).
@export var character: StringName = &""
const CHARACTER_RIGS := {
	&"mira_0": "res://art/characters/mira_0/runtime/mira_0_rig.tscn",
	&"small_mira_0": "res://art/characters/small_mira_0/runtime/small_mira_0_rig.tscn",
}
## The cameras are framed for the reference body (MIRA); another body's views are scaled by its leg (RigBones.body_ratio) so it fills the frame the same way. Set once the rig is built.
var view_scale := 1.0
## The CharacterRig this host drives and the presenter it owns: plain variables (resolved as soon as the scene is instantiated, before it enters the tree), because a host reads them every frame.
var rig: CharacterRig
var presenter: CharacterPresenter

func _notification(what: int) -> void:
	if what == NOTIFICATION_SCENE_INSTANTIATED:
		_resolve_rig()

func _enter_tree() -> void:
	_resolve_rig()

func _resolve_rig() -> void:
	if rig == null:
		_swap_character()
		rig = get_node_or_null(rig_path) as CharacterRig
		if rig != null:
			presenter = rig.presenter

## Replaces this scene's own rig with the chosen character's rig scene (same node name and place), before anything has built.
func _swap_character() -> void:
	if Engine.is_editor_hint():
		return
	var key := character
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="):
			key = StringName(argument.trim_prefix("--character="))
	if key == &"" or not CHARACTER_RIGS.has(key):
		return
	var old := get_node_or_null(rig_path)
	if old == null:
		return
	var replacement: Node = (load(CHARACTER_RIGS[key]) as PackedScene).instantiate()
	var name_kept := old.name
	remove_child(old)
	old.free()
	replacement.name = name_kept
	add_child(replacement)
	move_child(replacement, 0)


## A reference-body camera position or focus, scaled to this character.
func _view(point: Vector3) -> Vector3:
	return point * view_scale


@onready var status_label: Label = get_node_or_null("UI/Status") as Label
@onready var camera: Camera3D = get_node_or_null("Camera3D") as Camera3D
var side_view := false
var preview_direction := Vector2(0, 1)
## Travel speed the preview feeds the production locomotion presentation (m/s). Walk, jog and run follow from the profile's thresholds.
var preview_speed := 1.3
## Yaw (radians) the character is turning toward at the game's turn rate while moving, or NAN. Set by the test panel's moving turns.
var turn_goal := NAN
## Cover bench (the test panel's Cover row): a synthetic wall with chosen edge distances. The side comes from the production CoverEdgeSelector.choose and the pose
## from the production CoverPostureProfile (yaw_offset, crouch_request), exactly what TacticalCharacterAdapter uses in the game. Empty = no cover scenario.
var cover_demo := {}
const COVER_DEMO_SOURCE := &"workbench/cover"
const POSE_PRESET_SOURCE := &"workbench/pose_preset"
var cover_side := 0
## The edge-selection policy the bench stands in for the tactical host with (the same CoverEdgePolicy resource the game uses).
var cover_policy := CoverEdgePolicy.new()
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
## Crouch presets drive the existing CoverCrouchModifier the way TacticalCharacterAdapter does, with its ramp speeds.
## They exist so crouch, kneel and aim-while-crouched can be inspected here; there is no cover yaw.
const POSE_PRESET_NAMES := ["standing", "crouch", "half-kneel"]
var _pose_preset := 0

func _preview_locomotion(direction: Vector2) -> void:
	preview_turning = false
	if is_instance_valid(_preview_pivot):
		_preview_pivot.rotation.y = 0.0
	preview_direction = direction
	rig.locomotion_direction = direction
	if rig.animation_controller.current_state != &"move":
		rig.animation_controller.play(&"move")
	_update_status()

func _ready() -> void:
	if Engine.is_editor_hint():
		return   # the rig poses itself in the editor (its own _ready)
	rig.animation_controller.state_changed.connect(_on_animation_state_changed)
	view_scale = rig.body_ratio()
	camera.position = _view(camera.position)
	camera.look_at(_view(Vector3(0.42, 0.72, 0.0)), Vector3.UP)
	_update_status()
	# The interactive locomotion test bench (speed slider, gaits, turns, transitions, views, readout) drives this same rig.
	var test_panel := LocomotionTestPanel.new()
	get_node("UI").add_child(test_panel)
	test_panel.setup(self)
	await get_tree().process_frame   # the rig aligns its own weapon once the skeleton has posed (its _ready)
	await get_tree().process_frame
	if "--side-view" in OS.get_cmdline_user_args():
		camera.position = _view(Vector3(3.4, 1.3, 0.1))
		camera.look_at(_view(Vector3(0, 0.85, 0)), Vector3.UP)
	if "--auto-sequence" in OS.get_cmdline_user_args():
		rig.animation_controller.play_sequence()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_orbit_dragging = event.pressed
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if event.pressed else Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion and _orbit_dragging:
		var offset := camera.position - _view(ORBIT_FOCUS)
		var radius := offset.length()
		var yaw: float = atan2(offset.x, offset.z) - event.relative.x * 0.005
		var elevation := clampf(asin(offset.y / radius) + event.relative.y * 0.005, -0.15, 1.35)
		camera.position = _view(ORBIT_FOCUS) + Vector3(sin(yaw) * cos(elevation), sin(elevation), cos(yaw) * cos(elevation)) * radius
		camera.look_at(_view(ORBIT_FOCUS), Vector3.UP)
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
				rig.finish_interaction_now()
				rig.end_carry()
				rig.begin_pickup(rig.character_root.global_position + rig.character_root.global_basis.orthonormalized().z * 1.0)
				_update_status()
			KEY_Q:
				# Release: lower the passenger to the floor and let go. The passenger is left lying so it can be looked at.
				if is_instance_valid(rig.carry_passenger) and not rig.interaction_active():
					rig.keep_released_passenger = true
					rig.begin_release()
				_update_status()
			KEY_K:
				# Carrier-death interruption: the tactical layer has put the passenger down, so the visual one is dropped at once.
				rig.end_carry()
				rig.animation_controller.play(&"rifle_idle")
				_update_status()
			KEY_O:
				rig.rescue_interaction.paused = not rig.rescue_interaction.paused
				_update_status()
			KEY_COMMA, KEY_PERIOD:
				if rig.interaction_active():
					rig.rescue_interaction.paused = true
					rig.rescue_interaction.scrub(rig.rescue_interaction.time + (0.1 if event.keycode == KEY_PERIOD else -0.1))
				_update_status()
			KEY_Y:
				rig.passenger_motion_enabled = not rig.passenger_motion_enabled
				_update_status()
			KEY_P:
				rig.finish_interaction_now()
				rig.animation_controller.play(&"carry_idle")
			KEY_M:
				rig.finish_interaction_now()
				rig.animation_controller.play(&"carry_move")
			KEY_E:
				rig.finish_interaction_now()
				rig.animation_controller.play(&"boarding")
			KEY_7:
				rig.animation_controller.play(&"cover_low")
			KEY_8:
				rig.animation_controller.play(&"cover_high")
			KEY_9:
				rig.animation_controller.play(&"shoot_left")
			KEY_0:
				rig.animation_controller.play(&"shoot_right")
			KEY_V:
				rig.animation_controller.play(&"vault")
			KEY_B:
				rig.animation_controller.play(&"climb")
			KEY_N:
				rig.animation_controller.play(&"descend")
			KEY_L:
				rig.animation_controller.play(&"land")
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
					rig.add_child(_preview_pivot)
					rig.character_root.reparent(_preview_pivot)
				_preview_turn_time = 0.0
				preview_turning = true
				_update_status()
			KEY_I:
				rig.ik_enabled = not rig.ik_enabled
				rig.arm_ik.active = rig.ik_enabled
				_update_status()
			KEY_C:
				side_view = not side_view
				camera.position = _view(Vector3(3.4, 1.3, 0.1) if side_view else Vector3(2.8, 1.65, 3.55))
				camera.look_at(_view(Vector3(0, 0.85, 0) if side_view else Vector3(0.42, 0.72, 0)), Vector3.UP)
			KEY_ESCAPE:
				get_tree().quit()
			KEY_1:
				rig.animation_controller.play(&"rifle_idle")
			KEY_2:
				_preview_locomotion(Vector2(0, 1))
			KEY_3:
				rig.animation_controller.play(&"aim")
			KEY_4:
				rig.animation_controller.play(&"shoot")
			KEY_5:
				rig.animation_controller.play(&"hit")
			KEY_6:
				rig.animation_controller.play(&"defeat")
			KEY_SPACE:
				rig.animation_controller.play_sequence()


func _update_status() -> void:
	if not is_instance_valid(status_label):
		return
	var state_name: StringName = rig.animation_controller.current_state if is_instance_valid(rig.animation_controller) else &"setup"
	# Keep controls in the demo so individual poses are easy to inspect.
	status_label.text = "STATE: %s    IK: %s\n1 Idle  2 Move  3 Aim  4 Shoot  5 Hit  6 Defeat\nArrows: forward/back/strafe    T: turn preview\n[ / ]: pace %.1f m/s    Direction: %s\nRMB drag: orbit    C: camera preset\nSpace: sequence    I: IK    Esc: close\nLocomotion preview is in place" % [state_name, "ON" if rig.ik_enabled else "OFF", preview_speed, "turning" if preview_turning else str(preview_direction)]
	status_label.text += "\n7/8: low/high cover    9/0: expose left/right\nV: vault    B: climb    N: descend    L: landing"
	status_label.text += "\nR: pickup    P: carry idle    M: carry move    E: boarding    Q: release    K: carrier-death drop"
	status_label.text += "\nO: pause timeline    , / .: scrub 0.1 s    Y: passenger motion %s    Rescue: %s" % ["on" if rig.passenger_motion_enabled else "off", ("%s %.2f/%.2f s %s" % [RescueInteraction.Kind.keys()[rig.rescue_interaction.kind], rig.rescue_interaction.time, rig.rescue_interaction.duration(), rig.rescue_interaction.phase_name()]) if rig.interaction_active() else "-"]
	var diagnostics_on := is_instance_valid(_diagnostics) and _diagnostics.enabled
	status_label.text += "\nH: hand diagnostics %s    J: labels    G: mark contact    Z: pose %s    X: view %s" % ["ON" if diagnostics_on else "off", POSE_PRESET_NAMES[_pose_preset], DIAGNOSTIC_VIEW_NAMES[_diagnostic_view]]


func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if preview_turning and rig.animation_controller.current_state == &"move":
		_preview_turn_time += _delta
		var target_yaw := PI if int(_preview_turn_time / 2.0) % 2 == 0 else 0.0
		_preview_pivot.rotation.y = rotate_toward(_preview_pivot.rotation.y, target_yaw, TAU * _delta)
		var local_travel := _preview_pivot.basis.inverse() * Vector3.FORWARD
		preview_direction = Vector2(local_travel.x, local_travel.z)
		rig.locomotion_direction = preview_direction
	# The production locomotion presentation, fed a preview speed while a movement state is playing (and zero otherwise, which settles it).
	var walking: bool = rig.animation_controller.current_state in [&"move", &"carry_move"] and not rig.interaction_active()
	var heading_rate := 0.0
	if not is_nan(turn_goal):
		heading_rate = rig.presenter.turn_root_toward(turn_goal, 360.0, _delta)
		if is_equal_approx(rig.character_root.rotation.y, turn_goal):
			turn_goal = NAN
	rig.presenter.set_scripted_motion(preview_speed if walking else 0.0, heading_rate)   # authored preview motion, fed as given (a turn preview keeps its heading rate while idle)
	rig.presenter.tick(_delta)
	_apply_cover_demo(_delta)
	_advance_ladder_demo(_delta)
	_advance_stair_demo(_delta)
	_ramp_pose_preset(_delta)
	_follow_diagnostic_view()
	rig.presenter.advance_actions(_delta)   # the same action stage the tactical host runs: the presenter advances the rescue clock, this rig applies it
	rig.update_weapon_pose()
	if is_instance_valid(rig.carry_passenger) and rig.interaction_active():
		_update_status()


## The workbench's own response to the clip that plays: a rescue pose takes the carry (the same passenger, contacts, lean and slung weapon the game uses); anything else lets it go.
func _on_animation_state_changed(state_name: StringName) -> void:
	var rescue_pose := state_name in [&"pickup", &"carry_idle", &"carry_move", &"boarding"] or rig.interaction_active()
	if rescue_pose:
		rig.begin_carry()
	elif is_instance_valid(rig.carry_passenger):
		rig.end_carry()
		rig.arm_ik.active = rig.ik_enabled
	_update_status()

## H: switches the hand-contact diagnostics (overlay and readout) on or off. They are created on first use.
func _toggle_diagnostics() -> void:
	if not is_instance_valid(_diagnostics):
		_diagnostics = HandContactDiagnostics.attach(rig, self)
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
	if rig.crouch_modifier == null:
		return 0.0
	match _pose_preset:
		1: return rig.crouch_modifier.clamp_depth(0.41)   # about the depth for hiding behind 1.15 m cover
		2: return rig.crouch_modifier.max_depth           # what the adapter asks for behind cover too low to crouch behind
	return 0.0

func _ramp_pose_preset(delta: float) -> void:
	if rig.crouch_modifier == null or Engine.is_editor_hint() or not cover_demo.is_empty():
		return
	# A diagnostic preset is a BASE-priority posture request: a cover demo (CONTEXT) wins over it, and releasing the preset returns to standing.
	if _pose_preset == 0:
		rig.presenter.postures.release(POSE_PRESET_SOURCE)
	else:
		var posture := PresentationTypes.Posture.KNEEL if _pose_preset == 2 else PresentationTypes.Posture.CROUCH
		# A kneel is asked for as one blend range past the deepest crouch.
		var request := _pose_preset_depth() + (rig.KNEEL_BLEND_RANGE if _pose_preset == 2 else 0.0)
		rig.presenter.postures.set_posture(POSE_PRESET_SOURCE, posture, PresentationTypes.PRIORITY_BASE, 0.0, request)
	rig.presenter.apply_posture(delta, rig.cover_profile, false)

## X: cycles fixed diagnostic camera views. The close-ups follow the hands as the pose changes.
func _cycle_diagnostic_view() -> void:
	_diagnostic_view = (_diagnostic_view + 1) % DIAGNOSTIC_VIEW_NAMES.size()
	if _diagnostic_view == 0:
		camera.position = _view(Vector3(2.8, 1.65, 3.55))
		camera.look_at(_view(Vector3(0.42, 0.72, 0)), Vector3.UP)
		camera.fov = 34.0
	_update_status()

func _follow_diagnostic_view() -> void:
	if _diagnostic_view == 0 or not is_instance_valid(camera) or not is_instance_valid(rig.weapon):
		return
	var facing := rig.character_root.global_basis.orthonormalized()
	var firing := rig.weapon.to_global(rig.handling.firing_grip)
	var support := rig.weapon.to_global(rig.handling.support_grip)
	var focus := _view(ORBIT_FOCUS)
	var offset := Vector3.ZERO
	camera.fov = 30.0
	match _diagnostic_view:
		1:
			focus = _view(Vector3(0, 0.82, 0))
			offset = facing * _view(Vector3(-1.4, 0.55, 2.4))
		2:
			focus = firing
			offset = facing * _view(Vector3(-0.50, 0.14, 0.34))
			camera.fov = 26.0
		3:
			focus = support
			offset = facing * _view(Vector3(0.50, 0.14, 0.34))
			camera.fov = 26.0
		4:
			focus = (firing + support) * 0.5
			offset = facing * _view(Vector3(-0.85, 0.30, 0.75))
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
		rig.presenter.postures.release(COVER_DEMO_SOURCE)
		rig.animation_controller.play(&"rifle_idle")
		return
	cover_target = null
	cover_plan = {}
	rig.presenter.face_yaw(0.0, false, false)   # square to the wall again, at once: no hips catching up, no absorption
	_bench_heading = 0.0
	_cover_found = {"left": {"distance": spec.left, "usable": spec.left_ok}, "right": {"distance": spec.right, "usable": spec.right_ok}, "normal": Vector3(0, 0, 1), "tangent": Vector3(-1, 0, 0)}
	cover_side = CoverEdgeSelector.choose(_cover_found, cover_side, cover_policy)
	rig.animation_controller.play(&"aim" if spec.aim else &"rifle_idle")
	_build_cover_visuals()


## Authorizes (a position) or ends (null) an attack from the current cover scenario. The body turns to face the target (the facing change is absorbed into the cover
## yaw offset exactly as TacticalCharacterAdapter does, so nothing snaps), the plan picks the posture, and ending it returns to the passive cover pose.
func set_cover_target(target: Variant) -> void:
	if cover_demo.is_empty():
		return
	cover_target = target
	if target == null:
		cover_plan = {}
		_turn_to_heading(0.0)
		rig.animation_controller.play(&"aim" if cover_demo.aim else &"rifle_idle")
		return
	cover_plan = CoverEdgeSelector.plan_attack(_cover_found, bool(cover_demo.full), target as Vector3, int(cover_plan.get("side", 0)), cover_side, 0.5, cover_policy)
	_turn_to_heading(atan2((target as Vector3).x, (target as Vector3).z))
	rig.animation_controller.play(&"aim")


## Shows the plan's shot (shoot / shoot_left / shoot_right), then back to the aimed pose.
func fire_cover_shot() -> void:
	if cover_plan.is_empty():
		return
	rig.animation_controller.play(CoverEdgeSelector.shot_state(bool(cover_demo.full), cover_plan, cover_side))   # the same decision the tactical unit's attack makes
	await get_tree().create_timer(0.7).timeout
	if not cover_plan.is_empty():
		rig.animation_controller.play(&"aim")


func _turn_to_heading(heading: float) -> void:
	rig.presenter.face_yaw(heading, true, false)   # the cover pose absorbs the change (no snap); the bench shows no hips catching up
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
	if cover_demo.is_empty() or rig.crouch_modifier == null or Engine.is_editor_hint():
		return
	var spec := cover_demo
	var blend := rig.weapon_blend()
	var request := rig.cover_profile.crouch_request(bool(spec.full), float(spec.height), blend, rig.crouch_modifier.standing_head_height, rig.crouch_modifier.body_ratio())
	var yaw_goal := rig.cover_profile.yaw_offset(bool(spec.full), cover_side, blend)
	if not cover_plan.is_empty():
		yaw_goal = rig.cover_profile.attack_yaw_offset(cover_side, int(cover_plan.side), blend)
	# The demo is a CONTEXT-priority posture request, followed by the same shared ramp the tactical unit uses.
	var posture := PresentationTypes.Posture.KNEEL if request > rig.crouch_modifier.max_depth + rig.KNEEL_BLEND_RANGE * 0.5 else PresentationTypes.Posture.CROUCH
	rig.presenter.postures.set_posture(COVER_DEMO_SOURCE, posture, PresentationTypes.PRIORITY_CONTEXT, yaw_goal, request)
	rig.presenter.apply_posture(delta, rig.cover_profile, true)
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
	var chest := rig.global_position + Vector3(0, 1.2, 0)
	var facing := rig.character_root.global_basis.orthonormalized().z
	var segments := [[chest, chest + facing * 1.2, Color(0.3, 0.5, 1.0)], [rig.weapon.global_position, rig.weapon.global_position + rig.muzzle_socket.global_basis.z.normalized() * 1.5, Color(1.0, 0.25, 0.2)], [global_position + Vector3(0, 0.6, 0.62), global_position + Vector3(0, 0.6, -0.4), Color(0.3, 1.0, 0.4)]]
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
	rig.begin_traversal(&"ladder", length, direction)
	_build_ladder_visuals()
	rig.set_traversal_progress(float(ladder_demo.climbed))
	rig.animation_controller.play(&"rifle_idle")


func end_ladder_demo() -> void:
	ladder_demo = {}
	if is_instance_valid(_ladder_group):
		_ladder_group.queue_free()
	_ladder_group = null
	_ladder_markers.clear()
	rig.end_traversal()


func set_ladder_height(climbed: float) -> void:
	if ladder_demo.is_empty():
		return
	ladder_demo.climbed = clampf(climbed, 0.0, float(ladder_demo.length))
	rig.set_traversal_progress(float(ladder_demo.climbed))


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
		rig.set_traversal_progress(float(ladder_demo.climbed))
	if is_instance_valid(_ladder_group):
		_ladder_group.position.y = -float(ladder_demo.climbed)
		for marker in _ladder_markers:
			marker.visible = traversal_diagnostics
		_update_ladder_markers()


func _build_ladder_visuals() -> void:
	var profile := rig.traversal_profile
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
	if _ladder_markers.size() < 4 or rig.ladder == null or rig.ladder.pose == null:
		return
	for side in 2:
		_ladder_markers[side].global_position = rig.character_root.to_global(rig.ladder.pose.hands[side])
		_ladder_markers[2 + side].global_position = rig.character_root.to_global(rig.ladder.pose.feet[side])


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
	rig.animation_controller.play(&"rifle_idle")
	_set_stair_state(s0)


func end_stair_demo() -> void:
	stair_demo = {}
	if is_instance_valid(_stair_group):
		_stair_group.queue_free()
	_stair_group = null
	_stair_markers.clear()
	rig.end_stairs()


## One frame at the bench's own time step (frame stepping).
func step_stair_demo_frame() -> void:
	if not stair_demo.is_empty():
		stair_demo.playing = false
		stair_demo.step_once = true


func _stair_travel(model: StairModel, s: float) -> Vector3:
	return model.direction * s + Vector3.UP * stair_profile_height(model, s)


func stair_profile_height(model: StairModel, s: float) -> float:
	return model.ride_path_height_at(s, rig.stair_profile.riser_ramp)


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
	if rig.stairs == null:
		rig.begin_stairs(shifted, bool(stair_demo.ascending), float(stair_demo.enter), float(stair_demo.exit))
	rig.stairs.model = shifted
	rig.stairs.step = 0   # re-plan the holds against the shifted model
	rig.set_stair_progress(s, float(stair_demo.rate) if float(stair_demo.rate) > 0.0 else 1.0)
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
	if rig.stairs != null and rig.stairs.pose != null and _stair_markers.size() == 4:
		for foot in 2:
			_stair_markers[foot].global_position = rig.stairs.pose.feet[foot].position
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
	if rig.skeleton != null and not rig.skeleton.skeleton_updated.is_connected(_record_stair_ankles):
		rig.skeleton.skeleton_updated.connect(_record_stair_ankles)


func _record_stair_ankles() -> void:
	if stair_demo.is_empty():
		return
	for foot in 2:
		var bone := rig.skeleton.find_bone(rig.bones.left_leg[2] if foot == 0 else rig.bones.right_leg[2])
		if bone >= 0:
			_stair_actual[foot] = rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(bone).origin


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
