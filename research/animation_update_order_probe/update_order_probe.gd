extends SceneTree
## Task 04 evidence (disposable): the real per-frame order of Godot 4.7.2 callbacks for the production character: parent and child _process, the AnimationTree mixer, each
## skeleton modifier, skeleton_updated, physics ticks and the process_frame signal. Run: godot_console --headless --path . --script res://research/animation_update_order_probe/update_order_probe.gd
const NODE := preload("res://research/animation_update_order_probe/order_node.gd")
const VISUAL := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
var sink: Array = []
func _initialize() -> void:
	_run.call_deferred()
func _mk(tag: String) -> Node3D:
	var n := Node3D.new()
	n.set_script(NODE)
	n.tag = tag
	n.sink = sink
	return n
func _run() -> void:
	var unit_like := _mk("unit_like_parent")
	root.add_child(unit_like)
	var visual: Node3D = VISUAL.instantiate()
	unit_like.add_child(visual)
	var child := _mk("child_of_adapter")
	visual.add_child(child)
	var sibling_after := _mk("sibling_after_unit")
	root.add_child(sibling_after)
	await process_frame
	await process_frame
	await process_frame
	var skeleton: Skeleton3D = visual.skeleton
	process_frame.connect(func(): sink.append("SceneTree.process_frame"))
	physics_frame.connect(func(): sink.append("SceneTree.physics_frame"))
	var tree: AnimationTree = visual.animation_controller.animation_tree
	tree.mixer_applied.connect(func(): sink.append("AnimationTree.mixer_applied"))
	tree.mixer_updated.connect(func(): sink.append("AnimationTree.mixer_updated"))
	for m in skeleton.get_children():
		if m is SkeletonModifier3D:
			var nm := String(m.name)
			m.modification_processed.connect(func(): sink.append("modifier_done:" + nm))
	skeleton.skeleton_updated.connect(func(): sink.append("Skeleton3D.skeleton_updated"))
	RenderingServer.frame_pre_draw.connect(func(): sink.append("RenderingServer.frame_pre_draw"))
	RenderingServer.frame_post_draw.connect(func(): sink.append("RenderingServer.frame_post_draw"))
	sink.clear()
	for i in 6:
		sink.append("---- frame boundary")
		await process_frame
	# print the 4th frame block
	var blocks: Array = []
	var cur: Array = []
	for e in sink:
		if e == "---- frame boundary":
			if not cur.is_empty(): blocks.append(cur)
			cur = []
		else:
			cur.append(e)
	blocks.append(cur)
	for i in [2, 3]:
		print("== frame block ", i)
		for e in blocks[i]: print("   ", e)
	print("modifier children order: ", skeleton.get_children().filter(func(c): return c is SkeletonModifier3D).map(func(c): return c.name))
	print("skeleton modifier mode: ", skeleton.modifier_callback_mode_process, " animation callback mode: ", tree.callback_mode_process)
	quit(0)
