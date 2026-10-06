extends SceneTree

const UNIT_SCENE := preload("res://units/tactical_unit.tscn")

var failed := false

func _initialize() -> void:
	var ui_layer := CanvasLayer.new()
	ui_layer.add_to_group("UI_LAYER")
	root.add_child(ui_layer)
	var unit := UNIT_SCENE.instantiate() as TacticalUnit
	unit.position = Vector3(2.0, 1.0, 3.0)
	root.add_child(unit)
	for frame in 4:
		await process_frame
	var adapter := unit.visual_adapter
	_assert(adapter != null, "TacticalUnit exposes a visual adapter")
	_assert(unit.get_node("MeshInstance3D").visible == false, "Bean mesh is hidden")
	_assert(adapter.get_presentation_state() == &"rifle_idle", "unit starts in rifle idle")
	var original_hp := unit.stats.current_hp
	var original_ap := unit.stats.current_ap
	var original_grid := unit.grid_position
	unit.face_world_position(unit.global_position + Vector3.RIGHT * 4.0)
	await process_frame
	# A carried rifle points diagonally; measure body facing from rest toes.
	var rig: Skeleton3D = adapter.skeleton
	var foot_name := &"mixamorig_RightFoot" if rig.find_bone(&"mixamorig_RightFoot") >= 0 else &"J_Bip_R_Foot"
	var toe_name := &"mixamorig_RightToeBase" if rig.find_bone(&"mixamorig_RightToeBase") >= 0 else &"J_Bip_R_ToeBase"
	var foot := rig.get_bone_global_rest(rig.find_bone(foot_name)).origin
	var toe := rig.get_bone_global_rest(rig.find_bone(toe_name)).origin
	var visual_forward := rig.global_basis * (toe - foot)
	visual_forward.y = 0
	visual_forward = visual_forward.normalized()
	_assert(visual_forward.dot(Vector3.RIGHT) > 0.99, "spawn-facing request turns the visual toward opposition")
	# Reproduce generated spawning: placement after _ready must not be mistaken
	# for movement and overwrite a deliberately chosen facing.
	unit.position += Vector3(5, 0, -5)
	await process_frame
	await process_frame
	visual_forward = rig.global_basis * (toe - foot)
	visual_forward.y = 0
	visual_forward = visual_forward.normalized()
	_assert(visual_forward.dot(Vector3.RIGHT) > 0.99, "placement preserves chosen facing")
	unit.position = Vector3(2, 1, 3)
	await process_frame

	unit.move_along_path(PackedVector3Array([Vector3(2.0, 1.0, 3.0), Vector3(2.1, 1.0, 3.0)]))
	await process_frame
	_assert(adapter.get_presentation_state() == &"move", "movement drives move animation")
	unit.present_attack(Vector3(5.0, 1.0, 3.0))
	await process_frame
	_assert(adapter.get_presentation_state() == &"shoot", "attack drives shoot animation")
	unit.stats.take_damage(25)
	await process_frame
	_assert(adapter.get_presentation_state() == &"hit", "damage drives hit animation")
	_assert(unit.stats.current_hp == original_hp - 25, "presentation does not replace authoritative damage")
	_assert(unit.stats.current_ap == original_ap, "presentation does not alter AP")
	_assert(unit.grid_position == original_grid, "presentation does not alter the tactical cell")

	unit.stats.take_damage(1000)
	await process_frame
	_assert(adapter.get_presentation_state() == &"defeat", "zero HP drives defeat animation")
	unit.finish_defeat_presentation()
	await create_timer(1.35).timeout
	_assert(not is_instance_valid(unit), "defeated unit exits cleanly after its presentation")
	if not failed:
		print("[UnitVisualAdapter] PASS — move, shoot, hit, defeat, and teardown follow TacticalUnit without changing tactical authority")
	quit(1 if failed else 0)

func _assert(condition: bool, message: String) -> void:
	if condition:
		return
	failed = true
	push_error("[UnitVisualAdapter] FAIL — %s" % message)
