extends SceneTree
## INVARIANT: equal poses are equal. CONTRACT: ownership thresholds stay unchanged.
const Compare := preload("res://tests/support/pose_comparison.gd")
func _initialize() -> void:
	var same := Transform3D(Basis.from_euler(Vector3(PI * 61892.0 / 100000.0, 0.0, 0.0)), Vector3.ZERO)
	var small := Transform3D(Basis(Vector3.RIGHT, 0.0005), Vector3.ZERO)
	var changed := Transform3D(Basis(Vector3.RIGHT, 0.01), Vector3.ZERO)
	var shifted := Transform3D(Basis.IDENTITY, Vector3(0.0002, 0, 0))
	var tests := [not Compare.differs(same, same), not Compare.differs(Transform3D.IDENTITY, small), Compare.differs(Transform3D.IDENTITY, changed), Compare.differs(Transform3D.IDENTITY, shifted)]
	var failed := tests.count(false)
	print("Pose comparison: %d checks, %d failure(s); identical angle %.9f" % [tests.size(), failed, Compare.rotation_distance(same.basis, same.basis)])
	quit(1 if failed else 0)
