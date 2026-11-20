extends Node3D
## EXPERIMENTAL exploration playground (Task 03 companion). Walk MIRA around a tiny sandbox with an over-the-shoulder camera.
##
## This is a throwaway sandbox for feeling the existing character presentation outside tactical combat. It is NOT a gameplay mode: there is no TacticalUnit, no AP,
## no grid, no mission and no battle here. MIRA is the production visual scene driven only through its public presentation calls (`present_move`, `present_idle`,
## `update_locomotion`, `face_world_position`), exactly as research/animation_host_probe does. Everything in this file is local to the playground and meant to be replaced
## by Task 04's intent interface and Task 08's real non-tactical context.
##
## Controls: WASD move, mouse look, wheel zoom, right mouse button recenters behind MIRA, E interact, Esc release the mouse and show the menu.
## Known limitations of the existing presentation (deliberately not worked around): the rifle is always built (no unarmed state), crouching exists only as a cover
## function, there is no sitting or interaction animation, and the production scene's 1 m tactical-origin offset is undone here by placing the visual at the feet.

## Walking speed in metres per second. The walk gait applies up to the locomotion profile's `walk_until` (1.6 m/s); above it the jog starts to blend in.
const MOVE_SPEED := 1.4
## How quickly the body reaches MOVE_SPEED and stops again (m/s per second). Smooths starts and stops so the feet do not slide against an instant velocity.
const ACCELERATION := 9.0
const MOUSE_SENSITIVITY := 0.0025
const PITCH_LIMITS_DEGREES := Vector2(-60.0, 25.0)   # x: looking down (camera high), y: looking up (camera low)
const ZOOM_RANGE := Vector2(1.4, 6.0)
const ZOOM_STEP := 0.4
const DEFAULT_ZOOM := 3.2
const SHOULDER_OFFSET := 0.45
const CAMERA_FOCUS_HEIGHT := 1.45
const CAMERA_FOLLOW_RATE := 14.0
const RECENTER_RATE := 6.0
const INTERACT_DISTANCE := 2.4
const MATCH_SETUP_PATH := "res://ui/match_setup.tscn"
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const ACTIONS := {
	&"playground_forward": KEY_W, &"playground_back": KEY_S, &"playground_left": KEY_A, &"playground_right": KEY_D, &"playground_interact": KEY_E,
}
const RECENTER_ACTION := &"playground_recenter"

var body: CharacterBody3D
var visual: Node3D
var chair_seat: MeshInstance3D
var chair_position := Vector3.ZERO
var camera_pivot: Node3D
var camera_yaw: Node3D
var camera_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var hint_label: Label
var prompt_label: Label
var toast_label: Label
var state_label: Label
var menu_panel: PanelContainer
var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var zoom := DEFAULT_ZOOM
var pivot_position := Vector3.ZERO
var moving := false
var interacted := false
var toast_time := 0.0
var menu_open := false
## What the playground last asked of the mouse (headless runs have no real mouse mode to read back).
var mouse_captured := false
var _registered: Array[StringName] = []
var _seat_materials: Array[StandardMaterial3D] = []

func _ready() -> void:
	_register_inputs()
	_build_world()
	_build_character()
	_build_camera()
	_build_ui()
	pivot_position = _focus_point()
	yaw = PI   # start looking along the character's facing (+Z): the camera sits behind it
	_apply_camera_rotation()
	_set_mouse_captured(true)

func _exit_tree() -> void:
	for action in _registered:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
	if Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

# ---------------------------------------------------------------- setup

func _register_inputs() -> void:
	for action: StringName in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = ACTIONS[action]
		InputMap.action_add_event(action, key)
		_registered.append(action)
	if not InputMap.has_action(RECENTER_ACTION):
		InputMap.add_action(RECENTER_ACTION)
		var button := InputEventMouseButton.new()
		button.button_index = MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(RECENTER_ACTION, button)
		_registered.append(RECENTER_ACTION)

func _material(color: Color, emissive := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	if emissive:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = 0.6
	return material

func _solid(mesh: Mesh, shape: Shape3D, at: Vector3, material: Material, label: String) -> StaticBody3D:
	var static_body := StaticBody3D.new()
	static_body.name = label
	static_body.position = at
	var visible_mesh := MeshInstance3D.new()
	visible_mesh.mesh = mesh
	visible_mesh.material_override = material
	static_body.add_child(visible_mesh)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	static_body.add_child(collider)
	add_child(static_body)
	return static_body

func _box(size: Vector3, at: Vector3, color: Color, label: String) -> StaticBody3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	return _solid(mesh, shape, at, _material(color), label)

func _checker_texture() -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGB8)
	image.set_pixel(0, 0, Color(0.30, 0.34, 0.38))
	image.set_pixel(1, 1, Color(0.30, 0.34, 0.38))
	image.set_pixel(1, 0, Color(0.38, 0.42, 0.46))
	image.set_pixel(0, 1, Color(0.38, 0.42, 0.46))
	return ImageTexture.create_from_image(image)

func _build_world() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.55, 0.65, 0.75)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.8, 0.9)
	environment.ambient_light_energy = 0.55
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	add_child(sun)
	# One-metre checker squares make movement and foot sliding readable.
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(40.0, 40.0)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_texture = _checker_texture()
	floor_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	floor_material.uv1_scale = Vector3(20.0, 20.0, 1.0)
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(40.0, 0.2, 40.0)
	var floor_body := _solid(floor_mesh, floor_shape, Vector3.ZERO, floor_material, "Floor")
	(floor_body.get_child(1) as CollisionShape3D).position = Vector3(0.0, -0.1, 0.0)
	# Primitive props.
	_box(Vector3(1.0, 1.0, 1.0), Vector3(-3.0, 0.5, -2.0), Color(0.75, 0.45, 0.25), "CrateLarge")
	_box(Vector3(0.7, 0.7, 0.7), Vector3(-4.1, 0.35, -2.4), Color(0.55, 0.65, 0.35), "CrateSmall")
	_box(Vector3(7.0, 1.2, 0.3), Vector3(0.0, 0.6, -7.0), Color(0.6, 0.6, 0.65), "Wall")
	var pillar_mesh := CylinderMesh.new()
	pillar_mesh.top_radius = 0.4
	pillar_mesh.bottom_radius = 0.4
	pillar_mesh.height = 2.4
	var pillar_shape := CylinderShape3D.new()
	pillar_shape.radius = 0.4
	pillar_shape.height = 2.4
	_solid(pillar_mesh, pillar_shape, Vector3(2.5, 1.2, 3.5), _material(Color(0.5, 0.55, 0.8)), "Pillar")
	_build_chair(Vector3(4.0, 0.0, -3.0))

## A chair-shaped placeholder: seat, back and four legs, with ONE box collider. Nothing about it is a furniture system.
func _build_chair(at: Vector3) -> void:
	chair_position = at
	var chair := StaticBody3D.new()
	chair.name = "Chair"
	chair.position = at
	chair.rotation.y = deg_to_rad(-30.0)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 0.9, 0.5)
	collider.shape = shape
	collider.position = Vector3(0.0, 0.45, 0.0)
	chair.add_child(collider)
	var wood := _material(Color(0.8, 0.55, 0.25))
	var idle := _material(Color(0.85, 0.6, 0.3))
	_seat_materials = [idle, _material(Color(0.3, 0.8, 0.45), true)]
	var parts := [
		[Vector3(0.5, 0.06, 0.5), Vector3(0.0, 0.45, 0.0), idle],
		[Vector3(0.5, 0.5, 0.06), Vector3(0.0, 0.72, -0.22), wood],
		[Vector3(0.05, 0.42, 0.05), Vector3(-0.21, 0.21, -0.21), wood],
		[Vector3(0.05, 0.42, 0.05), Vector3(0.21, 0.21, -0.21), wood],
		[Vector3(0.05, 0.42, 0.05), Vector3(-0.21, 0.21, 0.21), wood],
		[Vector3(0.05, 0.42, 0.05), Vector3(0.21, 0.21, 0.21), wood],
	]
	for index in parts.size():
		var mesh := BoxMesh.new()
		mesh.size = parts[index][0]
		var piece := MeshInstance3D.new()
		piece.mesh = mesh
		piece.position = parts[index][1]
		piece.material_override = parts[index][2]
		chair.add_child(piece)
		if index == 0:
			chair_seat = piece
	add_child(chair)
	# A flat ring on the floor shows where interaction becomes possible.
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = INTERACT_DISTANCE * 0.5
	ring_mesh.bottom_radius = INTERACT_DISTANCE * 0.5
	ring_mesh.height = 0.01
	var ring := MeshInstance3D.new()
	ring.mesh = ring_mesh
	var ring_material := _material(Color(1.0, 0.85, 0.3, 0.25))
	ring_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring.material_override = ring_material
	ring.position = at + Vector3(0.0, 0.006, 0.0)
	add_child(ring)

func _build_character() -> void:
	body = CharacterBody3D.new()
	body.name = "MiraBody"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	var collider := CollisionShape3D.new()
	collider.shape = capsule
	collider.position = Vector3(0.0, 0.85, 0.0)
	body.add_child(collider)
	add_child(body)
	visual = VISUAL.instantiate()
	body.add_child(visual)
	# The production scene hangs 1 m below a tactical unit's origin (the unit's origin is its body centre); here the body origin IS the floor, so undo that offset.
	visual.position = Vector3.ZERO

func _build_camera() -> void:
	camera_pivot = Node3D.new()
	camera_pivot.name = "CameraPivot"
	camera_pivot.top_level = true
	add_child(camera_pivot)
	camera_yaw = Node3D.new()
	camera_pivot.add_child(camera_yaw)
	camera_pitch = Node3D.new()
	camera_yaw.add_child(camera_pitch)
	spring = SpringArm3D.new()
	spring.spring_length = zoom
	spring.margin = 0.12
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	spring.shape = probe
	spring.add_excluded_object(body.get_rid())
	camera_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 62.0
	camera.current = true
	spring.add_child(camera)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hint_label = Label.new()
	hint_label.text = "EXPERIMENTAL SANDBOX\nWASD move   Mouse look   Wheel zoom   Right mouse: recenter   E: interact   Esc: menu"
	hint_label.position = Vector2(16.0, 12.0)
	layer.add_child(hint_label)
	state_label = Label.new()
	state_label.position = Vector2(16.0, 64.0)
	layer.add_child(state_label)
	prompt_label = Label.new()
	prompt_label.text = "Press E to interact"
	prompt_label.visible = false
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	prompt_label.offset_top = -120.0
	prompt_label.offset_bottom = -96.0
	layer.add_child(prompt_label)
	toast_label = Label.new()
	toast_label.visible = false
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toast_label.offset_top = -168.0
	toast_label.offset_bottom = -144.0
	layer.add_child(toast_label)
	for label in [hint_label, state_label, prompt_label, toast_label]:
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)
	menu_panel = PanelContainer.new()
	menu_panel.visible = false
	menu_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "Exploration playground (experimental)"
	box.add_child(title)
	var resume := Button.new()
	resume.name = "ResumeButton"
	resume.text = "Resume"
	resume.pressed.connect(_close_menu)
	box.add_child(resume)
	var back := Button.new()
	back.name = "BackToMatchSetupButton"
	back.text = "Back to Match Setup"
	back.pressed.connect(exit_to_match_setup)
	box.add_child(back)
	menu_panel.add_child(box)
	layer.add_child(menu_panel)

# ---------------------------------------------------------------- input

func _set_mouse_captured(captured: bool) -> void:
	mouse_captured = captured
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if menu_open:
			_close_menu()
		else:
			_open_menu()
		get_viewport().set_input_as_handled()
		return
	if menu_open:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look((event as InputEventMouseMotion).relative)
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_WHEEL_UP:
				zoom_by(-ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				zoom_by(ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
					_set_mouse_captured(true)
	elif event.is_action_pressed(&"playground_interact"):
		interact()

func look(relative: Vector2) -> void:
	yaw -= relative.x * MOUSE_SENSITIVITY
	pitch = clampf(pitch - relative.y * MOUSE_SENSITIVITY, deg_to_rad(PITCH_LIMITS_DEGREES.x), deg_to_rad(PITCH_LIMITS_DEGREES.y))
	_apply_camera_rotation()

func zoom_by(amount: float) -> void:
	zoom = clampf(zoom + amount, ZOOM_RANGE.x, ZOOM_RANGE.y)

func _open_menu() -> void:
	menu_open = true
	menu_panel.visible = true
	_set_mouse_captured(false)

func _close_menu() -> void:
	menu_open = false
	menu_panel.visible = false
	_set_mouse_captured(true)

## Returns to the previous screen. The mouse is released first so the menu is usable.
func exit_to_match_setup() -> void:
	_set_mouse_captured(false)
	get_tree().change_scene_to_file(MATCH_SETUP_PATH)

# ---------------------------------------------------------------- per-frame

## The move direction in world space: WASD relative to where the camera looks.
func move_direction() -> Vector3:
	var input := Input.get_vector(&"playground_left", &"playground_right", &"playground_back", &"playground_forward")
	if input == Vector2.ZERO or menu_open:
		return Vector3.ZERO
	var forward := -camera_yaw.global_basis.z
	forward.y = 0.0
	var right := camera_yaw.global_basis.x
	right.y = 0.0
	return (right.normalized() * input.x + forward.normalized() * input.y).normalized()

func _physics_process(delta: float) -> void:
	var wanted := move_direction() * MOVE_SPEED
	var velocity := Vector3(body.velocity.x, 0.0, body.velocity.z).move_toward(wanted, ACCELERATION * delta)
	body.velocity = Vector3(velocity.x, -2.0 if body.is_on_floor() else body.velocity.y - 9.8 * delta, velocity.z)
	body.move_and_slide()
	var real := body.get_real_velocity()
	var flat := Vector3(real.x, 0.0, real.z)
	if flat.length() > 0.05:
		if not moving:
			moving = true
			visual.present_move()   # the caller requests the clip state itself (see the research report)
		visual.update_locomotion(flat, delta)   # turns toward the velocity and feeds the gait
	elif moving:
		moving = false
		visual.present_idle()

func _process(delta: float) -> void:
	if Input.is_action_pressed(RECENTER_ACTION) and not menu_open:
		# Behind the character: the camera rig looks along -Z, the character faces +Z at yaw 0.
		var behind := visual.global_rotation.y + PI
		yaw = lerp_angle(yaw, behind, 1.0 - exp(-RECENTER_RATE * delta))
		_apply_camera_rotation()
	pivot_position = pivot_position.lerp(_focus_point(), 1.0 - exp(-CAMERA_FOLLOW_RATE * delta))
	camera_pivot.global_position = pivot_position
	spring.spring_length = lerpf(spring.spring_length, zoom, 1.0 - exp(-10.0 * delta))
	_update_interaction(delta)
	var report: Dictionary = visual.locomotion_report
	state_label.text = "state: %s   speed: %.2f m/s" % [visual.get_presentation_state(), float(report.get("speed", 0.0))]

func _focus_point() -> Vector3:
	var right := Basis(Vector3.UP, yaw).x
	return body.global_position + Vector3(0.0, CAMERA_FOCUS_HEIGHT, 0.0) + right * SHOULDER_OFFSET

func _apply_camera_rotation() -> void:
	camera_yaw.rotation = Vector3(0.0, yaw, 0.0)
	camera_pitch.rotation = Vector3(pitch, 0.0, 0.0)

# ---------------------------------------------------------------- interaction (local to the playground)

func distance_to_chair() -> float:
	var offset := chair_position - body.global_position
	offset.y = 0.0
	return offset.length()

func can_interact() -> bool:
	return distance_to_chair() <= INTERACT_DISTANCE

## The non-tactical interaction REQUEST this sandbox tests: face the object (a production call) and show a visible response. There is no sitting or interaction animation
## to play: the existing presentation has none.
func interact() -> bool:
	if menu_open or not can_interact():
		return false
	visual.face_world_position(Vector3(chair_position.x, 0.0, chair_position.z))
	interacted = not interacted
	chair_seat.material_override = _seat_materials[1 if interacted else 0]
	_show_toast("Interacted with the chair (MIRA turns to it; there is no sitting animation yet)")
	return true

func _update_interaction(delta: float) -> void:
	prompt_label.visible = can_interact() and not menu_open
	if toast_time > 0.0:
		toast_time -= delta
		if toast_time <= 0.0:
			toast_label.visible = false

func _show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	toast_time = 2.5
