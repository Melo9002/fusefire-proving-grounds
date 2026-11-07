class_name TacticalCameraAperture
extends MeshInstance3D
## Only authored meshes using the aperture material register here.

const GROUP := &"tactical_camera_apertures"
const TRANSITION_SECONDS := 0.18

var strength := 0.0

func _ready() -> void:
	add_to_group(GROUP)

func update_view(eye: Vector3, subject: Vector3, delta: float) -> void:
	var obstructs := false
	if is_visible_in_tree() and subject.is_finite():
		var bounds := get_aabb().grow(0.12)
		var local_eye := to_local(eye)
		# Pad the center ray slightly so the edge of a post opens smoothly.
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
