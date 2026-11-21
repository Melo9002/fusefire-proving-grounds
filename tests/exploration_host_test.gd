extends SceneTree
## The non-tactical context host (Task 08): the SAME CharacterRig and CharacterPresenter the tactical adapter uses, hosted by ExplorationCharacterHost with no TacticalUnit, turns, AP, combat state or tactical
## services. Covers what research/animation_host_probe (retired) established, through the maintained contract: movement and turning reported to the presenter, crouch and recovery, a simple interaction with a
## meaningful lifecycle (COMPLETED, INTERRUPTED, CANCELLED), equipped and unarmed characters, one presenter tick per frame before the modifiers, and no duplicated animation ownership.
const HOST_SCENE := preload("res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn")
const TACTICAL_SCENE := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
const DT := 1.0 / 60.0
var failures := 0
var checks := 0
var _foot_gap := {}   # host -> peak fore-aft foot separation (metres)
var _ticks := []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _frames(count: int) -> void:
	for i in count:
		await process_frame

func _spawn(stage: Node3D, armed: bool, at := Vector3.ZERO) -> ExplorationCharacterHost:
	var host: ExplorationCharacterHost = HOST_SCENE.instantiate()
	if not armed:
		host.rig.weapon_scene = null   # before the tree: the character is built without a weapon
	host.position = at
	stage.add_child(host)
	_foot_gap[host] = 0.0
	# Pose samples are valid only where the skeleton updates.
	var rig := host.rig
	rig.skeleton.skeleton_updated.connect(func() -> void:
		var left := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(rig.bones.left_leg[2])).origin
		var right := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(rig.skeleton.find_bone(rig.bones.right_leg[2])).origin
		var forward := rig.global_basis.z
		_foot_gap[host] = maxf(_foot_gap[host], absf((left - right).dot(forward))))
	return host

## A controller moving the character: the velocity is reported every frame, as the playground does from its physics step.
func _walk(host: ExplorationCharacterHost, velocity: Vector3, frames: int) -> void:
	for i in frames:
		host.report_velocity(velocity, DT)
		await process_frame

func _stage_names(host: ExplorationCharacterHost) -> Array:
	return host.rig.skeleton.get_children().filter(func(c): return c is SkeletonModifier3D).map(func(c): return String(c.name))

func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var host := _spawn(stage, true)
	await _frames(25)

	# ---- No tactical context at all.
	var tactical := false
	var stack: Array[Node] = [stage]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		tactical = tactical or node is TacticalUnit or node is TacticalCharacterAdapter
		stack.append_array(node.get_children())
	check(not tactical and host.get("tactical_unit") == null and host.get_script() != TacticalCharacterAdapter, "The exploration host has no TacticalUnit, no tactical adapter and no tactical state")
	check(host.rig is CharacterRig and host.presenter == host.rig.presenter and host.presenter.rig == host.rig, "It hosts the shared CharacterRig and that rig's CharacterPresenter")
	var tactical_host: TacticalCharacterAdapter = TACTICAL_SCENE.instantiate()
	var same_rig_scene: bool = tactical_host.get_node("Rig").scene_file_path == host.get_node("Rig").scene_file_path and host.get_node("Rig").scene_file_path.ends_with("mira_0_rig.tscn")
	check(same_rig_scene, "The tactical adapter and the exploration host instance the same rig scene (%s)" % host.get_node("Rig").scene_file_path)
	tactical_host.free()
	check(host.get_presentation_state() == &"rifle_idle" and not host.is_moving(), "It idles at the start (%s)" % host.get_presentation_state())
	check(host.rig.skeleton.get_parent() != null and host.presenter.foot_point_problems().is_empty(), "The foot-point convention holds with no tactical placement")

	# ---- Movement: velocity reported to the presenter, the gait and the clip state follow, the feet step; stopping settles.
	await _walk(host, Vector3(0, 0, 1.4), 90)
	check(host.is_moving() and host.get_presentation_state() == &"move" and host.presenter.speed > 1.3, "Reported velocity reaches the presenter and the movement clip plays (%.2f m/s, %s)" % [host.presenter.speed, host.get_presentation_state()])
	check(float(host.rig.locomotion_report.get("speed", 0.0)) > 1.0, "The gait presentation follows the reported speed (%.2f)" % float(host.rig.locomotion_report.get("speed", 0.0)))
	check(_foot_gap[host] > 0.15, "The feet actually step (peak fore-aft separation %.2f m)" % _foot_gap[host])
	check(absf(angle_difference(host.rig.rotation.y, 0.0)) < deg_to_rad(5.0), "The body faces its direction of travel")
	await _frames(60)
	check(not host.is_moving() and host.get_presentation_state() == &"rifle_idle" and float(host.rig.locomotion_report.get("speed", 9.0)) < 0.1, "Stopping settles the gait to idle")

	# ---- Facing and turning through the presenter.
	host.face_point(Vector3(3, 0, 0))
	await _frames(4)
	check(absf(angle_difference(host.rig.rotation.y, PI * 0.5)) < deg_to_rad(2.0) and host.presenter.facing_mode == PresentationTypes.FacingMode.FACE_POINT, "face_point turns the body to the point within 2 degrees (%.1f)" % rad_to_deg(host.rig.rotation.y))
	await _walk(host, Vector3(-1.4, 0, 0), 45)
	check(absf(angle_difference(host.rig.rotation.y, -PI * 0.5)) < deg_to_rad(8.0) and host.presenter.facing_mode == PresentationTypes.FacingMode.FOLLOW_VELOCITY, "Reported velocity turns the body toward it at the configured rate (%.0f degrees)" % rad_to_deg(host.rig.rotation.y))
	await _frames(40)

	# ---- Crouch and recovery.
	host.set_crouched(true)
	await _frames(70)
	var depth: float = host.rig.crouch_modifier.depth
	check(host.is_crouched() and depth > 0.2 and host.presenter.postures.resolved() == PresentationTypes.Posture.CROUCH, "Crouching lowers the body through a posture request (depth %.2f m)" % depth)
	host.set_crouched(false)
	await _frames(90)
	check(not host.is_crouched() and host.rig.crouch_modifier.depth < 0.02 and host.presenter.postures.resolved() == PresentationTypes.Posture.STAND, "Standing releases the request and the body recovers (depth %.3f m)" % host.rig.crouch_modifier.depth)

	# ---- A simple interaction with a lifecycle: it completes, it can be interrupted, and a second request while one runs is refused.
	var inspected := host.inspect(Vector3(0, 0, 3), 0.8)
	var seen := []
	inspected.when_done(func(outcome: int) -> void: seen.append(outcome))
	await _frames(6)
	check(host.is_interacting() and not inspected.is_done() and absf(angle_difference(host.rig.rotation.y, 0.0)) < deg_to_rad(2.0), "inspect turns to the object and begins (pending handle)")
	var refused := host.inspect(Vector3(0, 0, 3), 0.8)
	check(refused.is_done() and refused.outcome == PresentationTypes.Outcome.CANCELLED and not inspected.is_done(), "A second interaction while one runs is CANCELLED and does not disturb the first")
	await create_timer(0.4).timeout
	check(host.rig.crouch_modifier.depth > 0.1, "The body bends toward the object while it lasts (depth %.2f m)" % host.rig.crouch_modifier.depth)
	await create_timer(1.0).timeout
	check(inspected.is_done() and seen == [PresentationTypes.Outcome.COMPLETED] and not host.is_interacting(), "The interaction completes (COMPLETED, once)")
	await create_timer(1.5).timeout
	check(host.rig.crouch_modifier.depth < 0.02 and host.presenter.postures.resolved() == PresentationTypes.Posture.STAND, "...and the character stands back up afterwards")
	var cut := host.inspect(Vector3(0, 0, 3), 2.0)
	await _frames(20)
	await _walk(host, Vector3(0, 0, 1.4), 3)
	check(cut.is_done() and cut.outcome == PresentationTypes.Outcome.INTERRUPTED and not host.is_interacting() and not host.presenter.is_holding(), "Walking away interrupts the interaction (INTERRUPTED)")
	await _frames(90)
	check(host.rig.crouch_modifier.depth < 0.02, "...and releases its posture")

	# ---- One presenter tick per frame, before the modifier pass of the same frame; modifier order; one owner of animation.
	var samples := []
	host.rig.locomotion_modifier.modification_processed.connect(func() -> void: samples.append([host.presenter.tick_count, host.presenter.last_tick_frame, Engine.get_process_frames()]))
	var first_tick: int = host.presenter.tick_count
	var first_frame := Engine.get_process_frames()
	await _frames(40)
	var elapsed := Engine.get_process_frames() - first_frame
	check(host.presenter.tick_count - first_tick == elapsed, "The presenter ticks exactly once per frame (%d ticks in %d frames)" % [host.presenter.tick_count - first_tick, elapsed])
	var ordered := not samples.is_empty()
	for sample in samples:
		ordered = ordered and sample[1] == sample[2]   # this frame's tick had already run when the modifier ran
	check(ordered, "The presenter's tick precedes the modifier pass of the same frame (%d samples)" % samples.size())
	check(_stage_names(host) == ["Locomotion", "CoverCrouch", "Traversal", "TraversalLegIK", "WeaponPose", "WeaponArmIK", "HandGrip"] and PoseOwnership.validate().is_empty(), "The modifier stack and its ownership declarations are the same ordered set (%s)" % [_stage_names(host)])
	check(host.find_children("*", "AnimationTree", true, false).size() == 1 and host.find_children("*", "Skeleton3D", true, false).size() == 1, "One AnimationTree and one skeleton: no parallel animation driver")
	var controllers := host.find_children("*", "Node", true, false).filter(func(n): return n.get_script() == host.rig.animation_controller.get_script())
	check(controllers.size() == 1 and controllers[0] == host.rig.animation_controller, "One animation controller, owned by the rig")
	check(host.is_processing() and not host.rig.is_processing(), "The host drives the frame; the rig has no frame callback of its own")

	# ---- Equipped and unarmed MIRA in the same host: the same stack, one holding the rifle.
	var bare := _spawn(stage, false, Vector3(3, 0, 0))
	await _frames(25)
	check(host.rig.equipment_state() == PresentationTypes.EquipmentState.HELD and bare.rig.equipment_state() == PresentationTypes.EquipmentState.NONE and host.rig.has_weapon() and not bare.rig.has_weapon(), "Equipped MIRA holds the rifle and unarmed MIRA holds nothing")
	check(bare.rig.bones.degraded.is_empty() and _stage_names(bare) == _stage_names(host), "The unarmed character builds the same full stack")
	await _walk(bare, Vector3(0, 0, 1.4), 90)
	check(bare.get_presentation_state() == &"move" and _foot_gap[bare] > 0.15, "Unarmed MIRA walks through the same host (state %s, foot separation %.2f m)" % [bare.get_presentation_state(), _foot_gap[bare]])
	await _frames(40)
	bare.set_crouched(true)
	await _frames(70)
	check(bare.rig.crouch_modifier.depth > 0.2, "Unarmed MIRA crouches (%.2f m)" % bare.rig.crouch_modifier.depth)
	bare.set_crouched(false)
	var bare_handle := bare.inspect(Vector3(5, 0, 0), 0.6)
	await create_timer(1.2).timeout
	check(bare_handle.is_done() and bare_handle.outcome == PresentationTypes.Outcome.COMPLETED, "Unarmed MIRA inspects with the same lifecycle")
	var armed_handle := host.inspect(Vector3(5, 0, 0), 0.6)
	await create_timer(1.2).timeout
	check(armed_handle.is_done() and armed_handle.outcome == PresentationTypes.Outcome.COMPLETED, "Equipped MIRA inspects with the same lifecycle")

	# ---- Teardown is clean: removing a host releases its presenter's requests and settles pending handles.
	var pending := host.inspect(Vector3(0, 0, 3), 5.0)
	await _frames(5)
	stage.remove_child(host)
	host.free()
	check(pending.is_done(), "Removing the host settles a pending interaction (%s)" % [pending.outcome])
	stage.queue_free()
	await _frames(2)
	print("Exploration host: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
