class_name TacticalCameraAperture
extends MeshInstance3D
## Only authored meshes using the aperture material register here.

const GROUP := &"tactical_camera_apertures"
const TRANSITION_SECONDS := 0.18
const APERTURE_RADIUS := 1.05

var strength := 0.0

func _ready() -> void:
	add_to_group(GROUP)
	set_instance_shader_parameter(&"aperture_radius", APERTURE_RADIUS)

func update_view(eye: Vector3, subject: Vector3, delta: float) -> void:
	var obstructs := false
	if is_visible_in_tree() and subject.is_finite():
		# Include neighboring tiles within the opening. The shader tests the
		# narrower perspective cone before discarding any pixels.
		var bounds := get_aabb().grow(APERTURE_RADIUS)
		var local_eye := to_local(eye)
		obstructs = bounds.intersects_segment(local_eye, to_local(subject)) != null
	var next := move_toward(strength, 1.0 if obstructs else 0.0, delta / TRANSITION_SECONDS)
	if next != strength:
		strength = next
		set_instance_shader_parameter(&"opening", strength)
	if obstructs:
		set_instance_shader_parameter(&"aperture_eye", eye)
		set_instance_shader_parameter(&"aperture_subject", subject)

func restore_view() -> void:
	if strength > 0.0:
		strength = 0.0
		set_instance_shader_parameter(&"opening", strength)
