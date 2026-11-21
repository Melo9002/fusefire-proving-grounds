extends SceneTree
## The exploration mode's fall safety net (ExplorationSpawnGuard): a body that falls out of the world is let fall for a moment, then returned to the spawn point nearest to where it last stood, with its velocity cleared;
## with no spawn point it returns to where the guard first saw it; and it is NOT returned while it stands on the floor, however far the floor is below its first position.
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _world(points: Array[Vector3]) -> Array:
	var stage := Node3D.new()
	root.add_child(stage)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 0.2, 10.0)
	shape.shape = box
	shape.position = Vector3(0, -0.1, 0)
	floor_body.add_child(shape)
	stage.add_child(floor_body)
	for position in points:
		var marker := Marker3D.new()
		marker.position = position
		marker.add_to_group(ExplorationSpawnGuard.SPAWN_GROUP)
		stage.add_child(marker)
	var body := CharacterBody3D.new()
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	collider.shape = capsule
	collider.position = Vector3(0, 0.85, 0)
	body.add_child(collider)
	stage.add_child(body)
	var guard := ExplorationSpawnGuard.new()
	guard.body = body
	guard.fall_depth = 3.0
	stage.add_child(guard)
	return [stage, body, guard]

## Steps the body like a controller does (gravity and move_and_slide) for `seconds`.
func _simulate(body: CharacterBody3D, seconds: float) -> float:
	var lowest := body.global_position.y
	var elapsed := 0.0
	while elapsed < seconds:
		await process_frame
		var delta := 1.0 / 60.0
		body.velocity.y = -2.0 if body.is_on_floor() else body.velocity.y - 9.8 * delta
		body.move_and_slide()
		lowest = minf(lowest, body.global_position.y)
		elapsed += delta
	return lowest

func _run() -> void:
	# ---- Two spawn points: the nearest to where the body last stood is used.
	var made := _world([Vector3(-3, 0.05, 0), Vector3(3, 0.05, 0)])
	var body: CharacterBody3D = made[1]
	var guard: ExplorationSpawnGuard = made[2]
	var seen := []
	guard.respawned.connect(func(point: Node3D, position: Vector3) -> void: seen.append([point, position]))
	body.position = Vector3(2.0, 0.05, 0.0)
	var standing_low := await _simulate(body, 0.5)
	check(seen.is_empty() and body.is_on_floor(), "Standing on the floor nothing happens")
	body.global_position = Vector3(2.0, 0.05, 0.0)
	body.velocity = Vector3(4.0, 0.0, 0.0)
	var lowest := 0.0
	for i in 200:
		await process_frame
		if not seen.is_empty():
			break   # returned this frame: look at the body as the guard left it
		body.velocity.x = 4.0 if body.global_position.x < 5.5 else body.velocity.x
		body.velocity.y = -2.0 if body.is_on_floor() else body.velocity.y - 9.8 / 60.0
		body.move_and_slide()
		lowest = minf(lowest, body.global_position.y)
	check(lowest < -1.0, "It was allowed to fall first (lowest %.1f m)" % lowest)
	check(seen.size() == 1 and (seen[0][0] as Node3D).global_position.is_equal_approx(Vector3(3, 0.05, 0)), "It returned to the spawn point nearest to where it last stood (right side)")
	check(body.global_position.distance_to(Vector3(3, 0.05, 0)) < 0.01 and body.velocity == Vector3.ZERO, "...placed there with its velocity cleared")
	await _simulate(body, 1.0)
	check(body.is_on_floor() and seen.size() == 1, "...and it stands there (no repeated respawn)")
	(made[0] as Node).queue_free()
	await process_frame

	# ---- Without spawn points it returns to where the guard first saw it.
	var bare := _world([])
	var body2: CharacterBody3D = bare[1]
	var guard2: ExplorationSpawnGuard = bare[2]
	var seen2 := []
	guard2.respawned.connect(func(point: Node3D, position: Vector3) -> void: seen2.append([point, position]))
	body2.position = Vector3(-1.0, 0.05, 1.0)
	await _simulate(body2, 0.4)
	body2.global_position = Vector3(20.0, 1.0, 0.0)
	for i in 240:
		await _simulate(body2, 0.02)
		if not seen2.is_empty():
			break
	check(seen2.size() == 1 and seen2[0][0] == null and body2.global_position.distance_to(Vector3(-1.0, 0.05, 1.0)) < 0.2, "With no spawn point it returns to where it was first seen (%s)" % [body2.global_position])
	(bare[0] as Node).queue_free()
	await process_frame
	print("Exploration spawn guard: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
