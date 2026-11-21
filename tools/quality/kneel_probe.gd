extends SceneTree
## Disposable probe: prints the half-kneel leg and foot geometry in the character's own frame (x right, y up, z forward), for diagnosing the rear foot.
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
func _initialize() -> void:
	_run.call_deferred()
var _att := {}
func _attach(v: UnitVisualAdapter, bone: String) -> void:
	if _att.has(bone):
		return
	var a := BoneAttachment3D.new()
	a.bone_name = bone
	v.rig.skeleton.add_child(a)
	_att[bone] = a
func _p(v: UnitVisualAdapter, bone: String) -> Vector3:
	var frame := Basis(Vector3.UP.cross(v.rig.character_root.global_basis.z).normalized(), Vector3.UP, v.rig.character_root.global_basis.z.slide(Vector3.UP).normalized())
	return frame.inverse() * ((_att[bone] as BoneAttachment3D).global_position - (_att["mixamorig_Hips"] as BoneAttachment3D).global_position)
func _run() -> void:
	var v: UnitVisualAdapter = VISUAL.instantiate()
	root.add_child(v)
	for i in 20: await process_frame
	for side in ["Left", "Right"]:
		for n in ["UpLeg", "Leg", "Foot", "ToeBase", "Toe_End"]:
			_attach(v, "mixamorig_%s%s" % [side, n])
	_attach(v, "mixamorig_Hips")
	for i in 5: await process_frame
	v.last_cover_contact = {"type": MapCellData.CoverType.LOW, "height": 0.4, "direction": Vector3.FORWARD}
	v.rig.animation_controller.play(&"cover_low")
	for i in 90: await process_frame
	print("kneel_leg=%d kneel=%.2f depth=%.3f" % [v.rig.crouch_modifier.kneel_leg, v.rig.crouch_modifier.kneel, v.rig.crouch_modifier.depth])
	for side in ["Left", "Right"]:
		var names := ["mixamorig_%sUpLeg" % side, "mixamorig_%sLeg" % side, "mixamorig_%sFoot" % side, "mixamorig_%sToeBase" % side, "mixamorig_%sToe_End" % side]
		var pts := []
		for n in names:
			pts.append(_p(v, n))
			print("  %-6s %-24s (%.3f, %.3f, %.3f)" % [side, n, pts[-1].x, pts[-1].y, pts[-1].z])
		var shin: Vector3 = pts[2] - pts[1]
		var foot: Vector3 = pts[4] - pts[2]
		print("  %s shin dir (%.2f, %.2f, %.2f) foot dir (%.2f, %.2f, %.2f) angle shin->foot %.0f deg" % [side, shin.normalized().x, shin.normalized().y, shin.normalized().z, foot.normalized().x, foot.normalized().y, foot.normalized().z, rad_to_deg(shin.angle_to(foot))])
	quit(0)
