extends Node3D
## Task 13 demonstration: three bodies of different families driven by ONE kind of context request. A scripted CONTEXT (this script) is the movement authority: it decides where each entity is and how fast it is going, moves
## the entity's own node, and then asks the family's presenter to show it through MotionRequest. The presenters only draw: wheels, rotors, lean and the humanoid's gait come from the supplied motion and the context never
## reads them back.
##   left   a HUMANOID (the existing exploration host, unchanged, its own presenter) walking back and forth with stops (the compatibility reference: it is fed the way every host feeds it);
##   middle a WHEELED platform driving a loop with a stop (wheel spin from distance, steering from the slip between heading and travel);
##   right  a DRONE that climbs, flies sideways while facing the middle, hovers and descends (full 3D motion, facing independent of travel).
## `step(dt)` advances the script by one frame; `_process` calls it unless `manual` is set (the capture and the test step by hand, deterministically).

const HUMANOID_SCENE := "res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn"
const CYCLE := 14.0

var manual := false
var time := 0.0
var humanoid: ExplorationCharacterHost
var platform_entity: Node3D
var platform: WheeledPresenter
var drone_entity: Node3D
var drone: DronePresenter
var readout: Label
var _frame := 0
var _platform_angle := 0.0
var _platform_yaw := 0.0
var _platform_last := Vector3.ZERO
var _drone_velocity := Vector3.ZERO
var _altitude_line: MeshInstance3D
const PLATFORM_CENTRE := Vector3(0, 0, 0)
const PLATFORM_RADIUS := 3.0
const DRONE_HOME := Vector3(6, 1.2, 0)
const HUMANOID_HOME := Vector3(-6, 0, -3)

func _ready() -> void:
	_build_stage()
	humanoid = (load(HUMANOID_SCENE) as PackedScene).instantiate()
	humanoid.position = HUMANOID_HOME
	add_child(humanoid)
	platform_entity = Node3D.new()
	platform_entity.name = "PlatformEntity"
	add_child(platform_entity)
	var wheeled := PrimitiveBodies.build_wheeled(platform_entity)
	platform = WheeledPresenter.new()
	platform.wheels = wheeled.wheels
	platform.steer_pivots = wheeled.steer_pivots
	platform.wheel_radius = wheeled.wheel_radius
	_platform_last = PLATFORM_CENTRE + Vector3(0, 0, PLATFORM_RADIUS)
	platform_entity.position = _platform_last
	drone_entity = Node3D.new()
	drone_entity.name = "DroneEntity"
	drone_entity.position = DRONE_HOME
	add_child(drone_entity)
	var flying := PrimitiveBodies.build_drone(drone_entity)
	drone = DronePresenter.new()
	drone.visual = flying.visual
	drone.tilt_pivot = flying.tilt_pivot
	drone.rotors = flying.rotors

func _process(delta: float) -> void:
	if not manual:
		step(delta)

## Advances the context by one frame: move each entity (authority), then present it (appearance).
func step(delta: float) -> void:
	if platform == null or delta <= 0.0:
		return
	time += delta
	_frame += 1
	var phase := fposmod(time, CYCLE)
	_drive_humanoid(delta, phase)
	_drive_platform(delta, phase)
	_drive_drone(delta, phase)
	_update_altitude_line()
	if is_instance_valid(readout):
		readout.text = _readout_text()

func _window(phase: float, from: float, to: float) -> float:
	return pow(sin(PI * clampf((phase - from) / (to - from), 0.0, 1.0)), 2.0) if phase >= from and phase <= to else 0.0

func _drive_humanoid(delta: float, phase: float) -> void:
	var walking := _window(phase, 0.5, 6.0) + _window(phase, 7.0, 12.5)
	var direction := 1.0 if phase < 6.5 else -1.0
	var velocity := Vector3(0, 0, direction * 2.4 * walking)
	humanoid.position += velocity * delta
	humanoid.report_velocity(velocity, delta)

func _drive_platform(delta: float, phase: float) -> void:
	var driving := clampf(2.0 * _window(phase, 0.0, 9.0), 0.0, 1.0) if phase < 9.0 else 0.0
	_platform_angle += (3.2 * driving / PLATFORM_RADIUS) * delta
	var at := PLATFORM_CENTRE + Vector3(sin(_platform_angle), 0, cos(_platform_angle)) * PLATFORM_RADIUS
	var velocity := (at - _platform_last) / delta
	_platform_last = at
	platform_entity.position = at
	# The context turns its own body toward the travel, at a limited rate (so it lags in a bend and the wheels must steer to it).
	if velocity.length() > 0.2:
		_platform_yaw = rotate_toward(_platform_yaw, atan2(velocity.x, velocity.z), deg_to_rad(80.0) * delta)
	platform_entity.rotation.y = _platform_yaw
	platform.present(MotionRequest.make(delta, velocity, platform_entity.global_transform, _frame))

func _drive_drone(delta: float, phase: float) -> void:
	var velocity := Vector3(0, 2.0, 0) * _window(phase, 0.0, 3.0) + Vector3(0, 0, 2.4) * _window(phase, 3.0, 6.0) + Vector3(0, -2.0, 0) * _window(phase, 8.0, 11.0) + Vector3(0, 0, -2.4) * _window(phase, 8.0, 11.0)
	drone_entity.position += velocity * delta
	var request := MotionRequest.make(delta, velocity, drone_entity.global_transform, _frame).facing_world_point(PLATFORM_CENTRE)
	drone.present(request)
	if absf(phase - 12.0) < delta * 0.5 and not drone.is_acting():
		drone.request_action(MotionPresenter.ACTION_REACTION, 0.6)   # a hit while hovering low

func _readout_text() -> String:
	var bridge := HumanoidMotionBridge.new(humanoid.presenter)   # only to describe the humanoid's capabilities; it presents nothing here
	var humanoid_line := "HUMANOID   walking %.2f m/s   state %s   (the existing exploration host, its own presenter)\n   can: %s" % [humanoid.presenter.speed, humanoid.get_presentation_state(), ", ".join(bridge.capabilities().map(func(c: StringName) -> String: return String(c)))]
	return "%s\n%s\n%s\n(the context moves every entity; the presenters only draw it)" % [humanoid_line, MotionReadout.text(platform.snapshot()), MotionReadout.text(drone.snapshot())]

func _update_altitude_line() -> void:
	var mesh := _altitude_line.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_set_color(Color(1, 1, 1, 0.6))
	mesh.surface_add_vertex(Vector3(drone_entity.position.x, 0.02, drone_entity.position.z))
	mesh.surface_set_color(Color(1, 1, 1, 0.6))
	mesh.surface_add_vertex(drone_entity.position)
	mesh.surface_end()

func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.04, 0.06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.66, 0.78)
	env.ambient_light_energy = 1.0
	environment.environment = env
	add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50, -30, 0)
	key.light_energy = 1.3
	key.shadow_enabled = true
	add_child(key)
	var floor := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(22, 12)
	floor.mesh = plane
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color(0.14, 0.17, 0.22)
	floor.material_override = floor_material
	add_child(floor)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 6.5, 13.5)
	camera.fov = 46.0
	add_child(camera)
	camera.look_at(Vector3(0, 1.6, 0), Vector3.UP)
	camera.current = true
	var layer := CanvasLayer.new()
	add_child(layer)
	readout = Label.new()
	readout.position = Vector2(20, 14)
	readout.add_theme_font_size_override("font_size", 16)
	readout.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
	readout.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	readout.add_theme_constant_override("outline_size", 5)
	layer.add_child(readout)
	_altitude_line = MeshInstance3D.new()
	_altitude_line.mesh = ImmediateMesh.new()
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	_altitude_line.material_override = line_material
	_altitude_line.top_level = true
	add_child(_altitude_line)
