extends SceneTree

const Compiler = preload("res://systems/generation/authored_scene_map_compiler.gd")
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	var parcel_size := Vector2i(16, 32)
	var origin := Vector3i(8, 0, 8)
	var map_size := Vector2i(64, 64)
	var deck := Rect2i(4, 5, 4, 2)
	for turn in 4:
		var data := FlatMapGenerator.generate(map_size.x, map_size.y, 1.0, 900 + turn)
		var root := Node3D.new()
		root.transform = ParcelTransform.scene_transform(parcel_size, origin, turn, map_size)
		root.set_meta("deck_local_rect", deck)
		root.set_meta("deck_level", 4)
		var ladder := Node.new()
		ladder.set_meta("ladder_local_bottom", Vector3i(4, 0, 4))
		ladder.set_meta("ladder_local_top", Vector3i(4, 4, 5))
		root.add_child(ladder)
		Compiler.compile(root, data, 1.0)
		for x in range(deck.position.x, deck.end.x):
			for z in range(deck.position.y, deck.end.y):
				var expected := ParcelTransform.cell(Vector3i(x, 4, z), parcel_size, origin, turn)
				check(data.get_cell(expected) != null and data.get_cell(expected).walkable, "rotation %d maps local deck cell to %s" % [turn, expected])
		var expected_bottom := ParcelTransform.cell(Vector3i(4, 0, 4), parcel_size, origin, turn)
		var expected_top := ParcelTransform.cell(Vector3i(4, 4, 5), parcel_size, origin, turn)
		check(data.traversal_links.any(func(link): return link.from_cell == expected_bottom and link.to_cell == expected_top), "rotation %d maps the authored ladder endpoints" % turn)
		root.free()
	print("Parcel elevation transform: %d failure(s)" % failures)
	quit(1 if failures else 0)
