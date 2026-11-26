extends SceneTree
## Rendered side-step calibration, separate from combat authority.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
const OFFSET := Vector3(0.24, 0.0, 0.0)

var adapter: TacticalCharacterAdapter
var actor: TacticalUnit
var grid: GridManager
var rest: Vector3
var home: Vector3
var ankles: Array[Vector3] = []
var bone_ids: Array[int] = []
var hips_height := 0.0
var trial_input: TraversalPoseInput
var sample := Vector3.ZERO
var planted_trial := false
var measuring := false
var max_ankle_error := 0.0
var weapon_contacts := 0
var frames := 0
var last_muzzle := Vector3.ZERO
var captures := ""
var failure := false

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty(): captures = args[0]
	if not captures.is_empty(): DirAccess.make_dir_recursive_absolute(captures)
	var fixture := Fixture.new()
	await fixture.setup(self, 2, 1)
	grid = fixture.grid
	actor = fixture.turns.player_units[0]
	var ally: TacticalUnit = fixture.turns.player_units[1]
	var target: TacticalUnit = fixture.turns.enemy_units[0]
	fixture.place(actor, Vector3i(16, 0, 10))
	fixture.place(target, Vector3i(16, 0, 15))
	rest = grid.grid_to_world(actor.grid_position)
	var wall := Node3D.new()
	wall.position = rest + Vector3(-0.425, 1.15, 1.20)
	wall.set_meta("solid_size", Vector3(1.0, 2.3, 0.10))
	var visual := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 2.3, 0.10)
	visual.mesh = mesh
	wall.add_child(visual)
	fixture.level.add_child(wall)
	AuthoredSceneMapCompiler.compile(wall, grid.map_data, 1.0)
	SurfaceNavigation.resolve_map(grid.map_data, 1.0)
	fixture.rebuild_graph()
	fixture.act_as(actor)
	var blocked := fixture.battle.query_attack(actor, target)
	sample = blocked.aim_point
	_check(not blocked.is_legal() and blocked.reason == "Blocked" and blocked.evaluation.firing_solution == null, "Central shot is rejected by wall")
	_check(_body_path(OFFSET), "Reference shift has support, clear swept body and valid reverse")
	_negative_controls(fixture, ally)
	adapter = actor.visual_adapter
	home = adapter.position
	trial_input = adapter.rig.traversal_modifier.input
	var camera := fixture.level.get_node("CameraRig") as TacticalCamera
	camera.set_process(false)
	camera._cancel_selection_focus()
	camera.camera.global_position = rest + Vector3(3.3, 2.7, -2.4)
	camera.camera.look_at(rest + Vector3(0.0, 0.9, 1.1))
	adapter.face_world_position(target.global_position)
	await create_timer(0.6).timeout
	var before := BattleStateFingerprint.capture(fixture.turns, grid, fixture.level.objective_manager)
	var rng := fixture.battle.action_service.get_combat_rng_state()
	var revision := fixture.battle.action_service.state_revision
	await _capture("rest")
	await _trial(target, false)
	await _trial(target, true)
	_check(before == BattleStateFingerprint.capture(fixture.turns, grid, fixture.level.objective_manager)
		and rng == fixture.battle.action_service.get_combat_rng_state() and revision == fixture.battle.action_service.state_revision,
		"Neither visual trial changes occupancy, authority, resources or RNG")
	await fixture.dispose(self)
	print("Contextual reference calibration: ", "failure" if failure else "completed")
	quit(1 if failure else 0)

func _check(ok: bool, text: String) -> void:
	if not ok:
		failure = true
		push_error(text)

func _body_path(offset: Vector3) -> bool:
	var end := rest + offset
	var data := grid.map_data
	return grid.world_to_grid(end) == actor.grid_position and offset.length() <= data.body_radius 		and SurfaceNavigation.supported(data, end, data.body_radius) and SurfaceNavigation.body_clear(data, end) 		and SurfaceNavigation.edge_clear(data, rest, end) and SurfaceNavigation.edge_clear(data, end, rest) 		and SurfaceNavigation.units_clear(grid, rest, end, actor) and SurfaceNavigation.units_clear(grid, end, rest, actor)

func _negative_controls(fixture, ally: TacticalUnit) -> void:
	_check(not _body_path(Vector3.RIGHT * 0.31) and not _body_path(Vector3.RIGHT * 0.55), "Excessive and cross-cell offsets are rejected")
	var obstruction := AABB(rest + Vector3(0.43, 0, -0.1), Vector3(0.1, 2, 0.2))
	grid.map_data.movement_parts.append(obstruction)
	SurfaceNavigation._rebuild_movement_index(grid.map_data)
	_check(SurfaceNavigation.body_clear(grid.map_data, rest) and not _body_path(OFFSET), "Nearby solid blocks shift while leaving home clear")
	grid.map_data.movement_parts.erase(obstruction)
	SurfaceNavigation._rebuild_movement_index(grid.map_data)
	var ally_origin := ally.grid_position
	var neighbor := rest + Vector3.RIGHT * 0.7
	var ally_cell := grid.get_cell_data(grid.world_to_grid(neighbor))
	var original := ally_cell.world_position
	ally_cell.world_position = neighbor
	fixture.place(ally, ally_cell.grid_position)
	_check(SurfaceNavigation.units_clear(grid, rest, rest, actor) and not _body_path(OFFSET), "Neighbor body blocks shift without blocking home")
	ally_cell.world_position = original
	fixture.place(ally, ally_origin)
	print("[Controls] excessive, solid and unit rejected")

func _trial(target: TacticalUnit, planted: bool) -> void:
	planted_trial = planted
	frames = 0
	weapon_contacts = 0
	max_ankle_error = 0
	var sk := adapter.rig.skeleton
	bone_ids.assign([sk.find_bone(adapter.rig.bones.left_leg[2]), sk.find_bone(adapter.rig.bones.right_leg[2])])
	ankles.clear()
	for bone in bone_ids: ankles.append(sk.global_transform * sk.get_bone_global_pose(bone).origin)
	var hips_id := sk.find_bone(adapter.rig.bones.hips)
	hips_height = (sk.global_transform * sk.get_bone_global_pose(hips_id).origin).y
	if planted: _apply_shift(0.0)
	var observer := _observe_frame
	sk.skeleton_updated.connect(observer)
	measuring = true
	await _animate_shift(0.0, 1.0)
	var rest_muzzle := adapter.rig.muzzle_socket
	var handle := adapter.present_attack(target.global_position)
	if not handle.shot.is_done(): await handle.shot.finished
	last_muzzle = rest_muzzle.global_position
	var open := CombatRules.get_blocking_cell(last_muzzle, sample, grid) == null
	var angle := rad_to_deg(rest_muzzle.global_basis.z.angle_to(sample - last_muzzle))
	print("[Fire] planted_trial=", planted_trial, " muzzle=", last_muzzle, " clear=", open, " aim_error_deg=", angle)
	if planted: await _capture("step-at-fire")
	if not handle.is_done(): await handle.finished
	await _animate_shift(1.0, 0.0)
	measuring = false
	sk.skeleton_updated.disconnect(observer)
	trial_input.clear()
	await process_frame
	_check(adapter.position.is_equal_approx(home) and actor.grid_position == Vector3i(16, 0, 10), "Visual root returns without tactical movement")
	print("[Motion] planted_trial=", planted_trial, " samples=", frames, " ankle_error_m=", max_ankle_error,
		" weapon_envelope_intersection_frames=", weapon_contacts)

func _animate_shift(from: float, to: float) -> void:
	var tween := create_tween()
	tween.tween_method(_apply_shift, from, to, 0.46)
	await tween.finished

func _apply_shift(p: float) -> void:
	adapter.position = home + OFFSET * smoothstep(0.0, 1.0, p)
	if not planted_trial: return
	# Diagnostic reuse of the existing contact stage. Its stairs mode is used
	# only as a bench interface to the same two-bone leg IK and foot levelling.
	trial_input.mode = TraversalPoseInput.Mode.STAIRS
	trial_input.solved = true
	trial_input.weight = 1.0
	trial_input.pelvis_height = hips_height - sin(p * PI) * 0.035
	for side in 2:
		var swing := smoothstep(0.0, 0.5, p) if side == 0 else smoothstep(0.5, 1.0, p)
		trial_input.ankles_world[side] = ankles[side] + OFFSET * swing + Vector3.UP * (sin(PI * swing) * 0.055)
		trial_input.planted[side] = true # Request level feet throughout this bench trial.

func _observe_frame() -> void:
	if not measuring: return
	frames += 1
	var rig := adapter.rig
	if planted_trial:
		for side in 2:
			var foot := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(bone_ids[side]).origin
			max_ankle_error = maxf(max_ankle_error, foot.distance_to(trial_input.ankles_world[side]))
	else:
		for side in 2:
			var foot := rig.skeleton.global_transform * rig.skeleton.get_bone_global_pose(bone_ids[side]).origin
			var horizontal := (foot - ankles[side]) * Vector3(1, 0, 1)
			max_ankle_error = maxf(max_ankle_error, horizontal.length())
	for instance: MeshInstance3D in rig.weapon.find_children("*", "MeshInstance3D", true, false):
		if not instance.mesh or instance == rig.muzzle_flash: continue
		var bounds := instance.global_transform * instance.mesh.get_aabb()
		for part in grid.map_data.movement_parts:
			if bounds.intersects(part):
				weapon_contacts += 1
				return

func _capture(name: String) -> void:
	if captures.is_empty() or DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	_check(root.get_texture().get_image().save_png(captures.path_join(name + ".png")) == OK, "Write frame " + name)
