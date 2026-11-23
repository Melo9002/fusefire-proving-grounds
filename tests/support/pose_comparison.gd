extends RefCounted
## CONTRACT: preserve the ownership test's 0.1 mm / 0.001 rad thresholds.
const POSITION_EPSILON := 0.0001
const ANGLE_EPSILON := 0.001
static func rotation_distance(a: Basis, b: Basis) -> float:
	# atan2 on the relative quaternion avoids acos amplifying near-unit roundoff.
	var relative := a.get_rotation_quaternion().inverse() * b.get_rotation_quaternion()
	return 2.0 * atan2(Vector3(relative.x, relative.y, relative.z).length(), absf(relative.w))
static func differs(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) > POSITION_EPSILON or rotation_distance(a.basis, b.basis) > ANGLE_EPSILON
