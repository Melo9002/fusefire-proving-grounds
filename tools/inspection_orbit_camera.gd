class_name InspectionOrbitCamera
extends RefCounted
## Shared editor-tool camera state. Call handle_mouse() from the owning Control/Node.

var camera: Camera3D
var focus := Vector3.ZERO
var distance := 12.0
var azimuth := 0.65
var altitude := 0.45
var min_distance := 0.35
var max_distance := 250.0

func _init(target_camera: Camera3D) -> void:
	camera = target_camera
	apply()

func frame(bounds: AABB) -> void:
	focus = bounds.get_center()
	var half_extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)) * 0.5
	var half_fov := deg_to_rad(camera.fov * 0.5)
	distance = clampf(maxf(half_extent / maxf(tan(half_fov), 0.01) * 1.65, min_distance * 2.0), min_distance, max_distance)
	apply()

func set_view(new_azimuth: float, new_altitude: float) -> void:
	azimuth = new_azimuth
	altitude = clampf(new_altitude, -0.05, 1.52)
	apply()

func handle_mouse(event: InputEvent) -> bool:
	if event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			azimuth -= event.relative.x * 0.008
			altitude = clampf(altitude + event.relative.y * 0.008, -0.05, 1.52)
			apply()
			return true
		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			var right := camera.global_basis.x.normalized()
			var up := camera.global_basis.y.normalized()
			var speed := distance * 0.0015
			focus += (-right * event.relative.x + up * event.relative.y) * speed
			apply()
			return true
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			distance = maxf(min_distance, distance * 0.86)
			apply()
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			distance = minf(max_distance, distance / 0.86)
			apply()
			return true
	return false

func apply() -> void:
	if not is_instance_valid(camera):
		return
	camera.position = focus + Vector3(sin(azimuth) * cos(altitude), sin(altitude), cos(azimuth) * cos(altitude)) * distance
	camera.look_at(focus)
