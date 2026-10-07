extends SceneTree

var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var unit := TacticalUnit.new()
	unit.unit_hud_scene = null
	var visual = load("res://art/characters/vroid_proof/runtime/unit_visual_adapter.tscn").instantiate()
	unit.add_child(visual)
	unit.visual_adapter = visual
	root.add_child(unit)
	await process_frame
	await process_frame
	visual.present_move()
	visual.update_locomotion(Vector3(5, 0, 0), 0.05)
	check(visual.rotation.y > 0.0 and visual.rotation.y < PI / 2, "Turn must be gradual")
	var controller = visual.animation_controller
	var direction: Vector2 = controller.animation_tree.get("parameters/move/Direction/blend_position")
	check(direction.y > 0.9 and absf(direction.x) < 0.01, "Path following must keep the forward clip while turning")
	check(is_equal_approx(controller.animation_tree.get("parameters/move/Pace/scale"), 5.0 / visual.stride_length), "Cadence must match travel speed")
	visual.rotation.y = 0.0
	visual.update_locomotion(Vector3(0, 0, -2), 0.01)
	direction = controller.animation_tree.get("parameters/move/Direction/blend_position")
	check(direction.y > 0.9, "Path reversal must turn and continue using the forward clip")
	unit.move_along_path(PackedVector3Array([Vector3.ZERO, Vector3(1, 0, 1), Vector3(2, 0, 1)]))
	await unit.movement_finished
	check(unit.global_position.is_equal_approx(Vector3(2, 0, 1)), "Diagonal and corner path must reach exact destination")
	check(visual.get_presentation_state() == &"rifle_idle", "Movement must return to idle")
	unit.queue_free()
	await process_frame
	print("Locomotion foundation: %d failure(s)" % failures)
	quit(1 if failures else 0)
