extends SceneTree
## The per-frame update-order contract (Task 04 measurement, Task 07 safety net) on the production MIRA visual: every _process (parent, the rig, children) runs BEFORE any skeleton modifier,
## the modifiers run in their declared child order, and skeleton_updated comes after the last modifier. The presenter migration must not change this order; this test fails if it does.
const NODE := preload("res://research/animation_update_order_probe/order_node.gd")
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const EXPECTED_MODIFIER_ORDER := ["Locomotion", "CoverCrouch", "Traversal", "TraversalLegIK", "TraversalFoot", "WeaponPose", "WeaponArmIK", "HandGrip"]
var sink: Array = []
var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _mk(tag: String) -> Node3D:
	var n := Node3D.new()
	n.set_script(NODE)
	n.tag = tag
	n.sink = sink
	return n

func _run() -> void:
	var parent := _mk("parent")
	root.add_child(parent)
	var visual: Node3D = VISUAL.instantiate()
	parent.add_child(visual)
	var child := _mk("child")
	visual.add_child(child)
	for i in 3:
		await process_frame
	var skeleton: Skeleton3D = visual.rig.skeleton
	var modifiers: Array = skeleton.get_children().filter(func(c): return c is SkeletonModifier3D)
	var names: Array = modifiers.map(func(c): return String(c.name))
	print("  modifier order: ", names)
	check(names.size() == EXPECTED_MODIFIER_ORDER.size(), "Modifier count changed (%d)" % names.size())
	for i in mini(names.size(), EXPECTED_MODIFIER_ORDER.size()):
		check(names[i] == EXPECTED_MODIFIER_ORDER[i], "Modifier %d is %s, expected %s" % [i, names[i], EXPECTED_MODIFIER_ORDER[i]])
	for m in modifiers:
		var nm := String(m.name)
		m.modification_processed.connect(func(): sink.append("modifier:" + nm))
	skeleton.skeleton_updated.connect(func(): sink.append("skeleton_updated"))
	sink.clear()
	for i in 4:
		sink.append("|frame")
		await process_frame
	var frames: Array = []
	var current: Array = []
	for e in sink:
		if e == "|frame":
			if not current.is_empty():
				frames.append(current)
			current = []
		else:
			current.append(e)
	check(frames.size() >= 2, "Captured enough frames (%d)" % frames.size())
	for f in frames:
		var process_ticks: Array = f.filter(func(e): return not str(e).begins_with("modifier:") and e != "skeleton_updated" and not str(e).contains("physics"))
		var last_process := -1
		var first_modifier := -1
		var last_modifier := -1
		var updated := -1
		for i in f.size():
			var e := str(f[i])
			if e.begins_with("modifier:"):
				if first_modifier < 0:
					first_modifier = i
				last_modifier = i
			elif e == "skeleton_updated":
				updated = i
			elif e.contains("process") and not e.contains("physics"):
				last_process = i
		if first_modifier >= 0:
			check(last_process < first_modifier, "A _process ran after a skeleton modifier began: %s" % [f])
		if updated >= 0 and last_modifier >= 0:
			check(updated > last_modifier, "skeleton_updated fired before the last modifier: %s" % [f])
		check(process_ticks.size() > 0, "Node _process callbacks were recorded: %s" % [f])
	print("Animation update order: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
