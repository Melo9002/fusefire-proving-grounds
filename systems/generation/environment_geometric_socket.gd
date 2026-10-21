class_name EnvironmentGeometricSocket
extends RefCounted
## Measured visual mating frame. +Z is the outward normal, +X is the seam
## tangent and +Y completes the frame. This is deliberately separate from
## tactical access/connectivity.

enum Role { RECEIVER, PLUG, EXTERNAL_INTERFACE }

var socket_id: StringName
var family: StringName
var role := Role.RECEIVER
var local_frame := Transform3D.IDENTITY
var seam_size := Vector2.ONE
var allowed_roll_quarters: Array[int] = [0]
var position_tolerance := 0.015
var angular_tolerance_degrees := 1.0
var required := false

func _init(id: StringName = &"", socket_family: StringName = &"") -> void:
	socket_id = id
	family = socket_family

static func attachment_transform(fixed: EnvironmentGeometricSocket, moving: EnvironmentGeometricSocket, roll_quarters := 0) -> Dictionary:
	var compatibility := compatibility_failure(fixed, moving, roll_quarters)
	if not compatibility.is_empty():
		return {"ok": false, "code": compatibility}
	var flip := Transform3D(Basis(Vector3.RIGHT, PI), Vector3.ZERO)
	var roll := Transform3D(Basis(Vector3.FORWARD, float(roll_quarters) * PI * 0.5), Vector3.ZERO)
	return {"ok": true, "transform": fixed.local_frame * roll * flip * moving.local_frame.affine_inverse()}

static func compatibility_failure(a: EnvironmentGeometricSocket, b: EnvironmentGeometricSocket, roll_quarters := 0) -> StringName:
	if a.family != b.family:
		return &"INCOMPATIBLE_SOCKET_FAMILY"
	if a.role == b.role or Role.EXTERNAL_INTERFACE in [a.role, b.role]:
		return &"INCOMPATIBLE_SOCKET_ROLE"
	if absf(a.seam_size.x - b.seam_size.x) > maxf(a.position_tolerance, b.position_tolerance) or absf(a.seam_size.y - b.seam_size.y) > maxf(a.position_tolerance, b.position_tolerance):
		return &"SEAM_DIMENSION_MISMATCH"
	if roll_quarters not in a.allowed_roll_quarters or roll_quarters not in b.allowed_roll_quarters:
		return &"UNSUPPORTED_ROTATION"
	return &""

static func validate_alignment(a: EnvironmentGeometricSocket, a_component: Transform3D, b: EnvironmentGeometricSocket, b_component: Transform3D) -> StringName:
	var wa := a_component * a.local_frame
	var wb := b_component * b.local_frame
	if wa.origin.distance_to(wb.origin) > maxf(a.position_tolerance, b.position_tolerance):
		return &"SOCKET_ALIGNMENT_ERROR"
	var normal_error := rad_to_deg(wa.basis.z.angle_to(-wb.basis.z))
	if normal_error > maxf(a.angular_tolerance_degrees, b.angular_tolerance_degrees):
		return &"SOCKET_ANGULAR_ERROR"
	var tangent_error := rad_to_deg(wa.basis.x.angle_to(wb.basis.x))
	if tangent_error > maxf(a.angular_tolerance_degrees, b.angular_tolerance_degrees):
		return &"UNSUPPORTED_ROTATION"
	return &""
