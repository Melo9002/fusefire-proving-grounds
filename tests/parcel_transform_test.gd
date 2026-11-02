extends SceneTree

const TransformRules = preload("res://systems/generation/parcel_transform.gd")

func _initialize() -> void:
	var failures := 0
	var size := Vector2i(16, 32)
	var origin := Vector3i(5, 2, 7)
	for turn in 4:
		var scene_pose: Transform3D = TransformRules.scene_transform(size, origin, turn, Vector2i(96, 80), 2.0)
		var seen := {}
		var rotated: Vector2i = TransformRules.rotated_size(size, turn)
		for x in size.x:
			for z in size.y:
				var point: Vector3i = TransformRules.cell(Vector3i(x, 3, z), size, origin, turn)
				if point.y != 5 or point.x < 5 or point.z < 7 or point.x >= 5 + rotated.x or point.z >= 7 + rotated.y or seen.has(point):
					failures += 1
				seen[point] = true
				var expected_world := Vector3(point.x - 47.5, point.y, point.z - 39.5) * 2.0
				if not (scene_pose * Vector3(x, 3, z)).is_equal_approx(expected_world):
					failures += 1
		if seen.size() != 512:
			failures += 1
	var expected := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
	for turn in 4:
		if TransformRules.direction(Vector2i(0, -1), turn) != expected[turn]:
			failures += 1
	print("Parcel transform: %d failure(s)" % failures)
	quit(1 if failures else 0)
