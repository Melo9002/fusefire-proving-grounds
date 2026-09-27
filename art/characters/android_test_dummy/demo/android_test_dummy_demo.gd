extends Node3D

const TARGET := Vector3(0.0, 0.82, 0.0)
const DEFAULT_YAW := deg_to_rad(28.0)
const DEFAULT_PITCH := deg_to_rad(13.0)
const DEFAULT_DISTANCE := 4.2

@onready var display: Node3D = $Display
@onready var camera: Camera3D = $Camera3D
@onready var help_label: Label = $UI/Margin/VBox/Help

var _yaw := DEFAULT_YAW
var _pitch := DEFAULT_PITCH
var _distance := DEFAULT_DISTANCE
var _dragging := false
var _auto_rotate := true


func _ready() -> void:
	_build_reference_grid()
	_update_camera()


func _process(delta: float) -> void:
	if _auto_rotate:
		display.rotate_y(delta * 0.22)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_distance = maxf(2.2, _distance - 0.25)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_distance = minf(7.0, _distance + 0.25)
			_update_camera()
	elif event is InputEventMouseMotion and _dragging:
		_yaw -= event.relative.x * 0.008
		_pitch = clampf(_pitch - event.relative.y * 0.008, deg_to_rad(-12.0), deg_to_rad(55.0))
		_update_camera()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_auto_rotate = not _auto_rotate
			help_label.text = _help_text()
		elif event.keycode == KEY_R:
			_yaw = DEFAULT_YAW
			_pitch = DEFAULT_PITCH
			_distance = DEFAULT_DISTANCE
			display.rotation = Vector3.ZERO
			_update_camera()


func _update_camera() -> void:
	var horizontal := cos(_pitch) * _distance
	camera.position = TARGET + Vector3(sin(_yaw) * horizontal, sin(_pitch) * _distance, cos(_yaw) * horizontal)
	camera.look_at(TARGET, Vector3.UP)


func _help_text() -> String:
	var rotation_state := "ON" if _auto_rotate else "OFF"
	return "Left-drag: orbit    Wheel: zoom    Space: auto-rotation %s    R: reset" % rotation_state


func _build_reference_grid() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.12, 0.72, 0.82, 0.38)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, material)
	for index in range(-2, 3):
		var coordinate := float(index)
		mesh.surface_add_vertex(Vector3(coordinate, 0.006, -2.0))
		mesh.surface_add_vertex(Vector3(coordinate, 0.006, 2.0))
		mesh.surface_add_vertex(Vector3(-2.0, 0.006, coordinate))
		mesh.surface_add_vertex(Vector3(2.0, 0.006, coordinate))
	mesh.surface_end()
	var grid := MeshInstance3D.new()
	grid.name = "OneMetreReferenceGrid"
	grid.mesh = mesh
	add_child(grid)