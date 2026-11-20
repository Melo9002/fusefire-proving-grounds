extends SceneTree
## Target-aware cover firing (tactical cover presentation 04). Pure planning rules (CoverEdgeSelector.plan_attack: attack intent beats the passive edge, the nearest-edge
## fallback stays for no-attack and straight-ahead targets, side hysteresis, unusable edges, mismatch diagnostics, determinism) and the production path: a real,
## authorized attack from behind a wall presents the posture of the TARGET's side, keeps it stable, aims at the target, returns to the passive pose, and changes
## nothing tactical (cell, AP cost, no enemy knowledge in the plan).
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## Synthetic edge analysis: normal toward +z, right toward -x (the unit faces +z), both edges `distance` m away.
func _found(left_ok := true, right_ok := true, left_d := 1.5, right_d := 1.5) -> Dictionary:
	return {"left": {"distance": left_d, "usable": left_ok}, "right": {"distance": right_d, "usable": right_ok}, "normal": Vector3(0, 0, 1), "tangent": Vector3(-1, 0, 0)}

func _plan(to_target: Vector3, found := _found(), full := true, previous := 0, passive := 1, profile: CoverPostureProfile = null) -> Dictionary:
	return CoverEdgeSelector.plan_attack(found, full, to_target, previous, passive, 0.5, profile if profile != null else CoverPostureProfile.new())

func _run_pure() -> void:
	var Mode := CoverEdgeSelector.FiringMode
	var Side := CoverEdgeSelector.Side
	# Target behind / beside the unit (the wall is not between them): an ordinary stance, no peeking.
	check(_plan(Vector3(0, 0, -4)).mode == Mode.ORDINARY and _plan(Vector3(0, 0, -4)).side == Side.NONE, "A target on the open side gets an ordinary firing posture")
	# Low cover: over the top, whatever side the target is on.
	check(_plan(Vector3(-3, 0, 3), _found(), false).mode == Mode.OVER_COVER and _plan(Vector3(3, 0, 3), _found(), false).mode == Mode.OVER_COVER, "Low cover is fired over, left or right")
	# Attack intent beats the passive preference: passive says RIGHT (tie), the target is to the LEFT (+x).
	var left_plan := _plan(Vector3(4, 0, 2), _found(), true, Side.NONE, Side.RIGHT)
	check(left_plan.mode == Mode.AROUND_LEFT and left_plan.side == Side.LEFT, "A target to the left is engaged round the left edge although the passive choice is right")
	var right_plan := _plan(Vector3(-4, 0, 2), _found(), true, Side.NONE, Side.LEFT)
	check(right_plan.mode == Mode.AROUND_RIGHT and right_plan.side == Side.RIGHT, "A target to the right is engaged round the right edge although the passive choice is left")
	# Straight ahead: no side is better; the passive (nearest-edge / right-tie) choice stands.
	check(_plan(Vector3(0, 0, 5), _found(), true, 0, Side.LEFT).side == Side.LEFT and _plan(Vector3(0.2, 0, 5), _found(), true, 0, Side.RIGHT).side == Side.RIGHT, "Straight ahead the passive choice stands (nearest edge, right on a tie)")
	# The target's side edge unusable: the passive pose, and the mismatch is recorded, not hidden.
	var blocked := _plan(Vector3(4, 0, 2), _found(false, true), true, 0, Side.RIGHT)
	check(blocked.side == Side.RIGHT and blocked.mismatch == "target_side_edge_unusable", "An unusable target-side edge falls back to the passive pose and records the mismatch")
	var none := _plan(Vector3(4, 0, 2), _found(false, false), true, 0, Side.NONE)
	check(none.mode == Mode.PROTECTED and none.side == Side.NONE and not none.mismatch.is_empty(), "No usable edge at all: a protected posture with a recorded mismatch (the body is never pushed through the wall)")
	# Hysteresis between consecutive attacks: a target near the middle keeps the earlier side; a clearly opposite one switches.
	var near_middle := Vector3(0.9, 0, 4)   # lateral about -0.22 (slightly left)
	check(_plan(near_middle, _found(), true, Side.RIGHT, Side.RIGHT).side == Side.RIGHT, "A target only slightly across the middle keeps the previous side (no left/right flicker)")
	check(_plan(Vector3(4, 0, 2), _found(), true, Side.RIGHT, Side.RIGHT).side == Side.LEFT, "...but a clearly left target switches")
	# A visual ray that crosses the wall's end is reported (the tactical shot was authorized from the cell centre).
	var crossing := _plan(Vector3(1.2, 0, 4), _found(true, true, 3.0, 3.0), true, 0, Side.RIGHT)
	check(crossing.mismatch == "ray_crosses_wall_end", "A ray that cannot clear a long wall's end is recorded as a mismatch")
	var clear := _plan(Vector3(4, 0, 1), _found(true, true, 0.5, 0.5), true, 0, Side.RIGHT)
	check(clear.mismatch.is_empty(), "A ray that clears a short wall's end is not a mismatch")
	# Deterministic and independent of anything but its arguments.
	var again := _plan(Vector3(4, 0, 2), _found(), true, Side.NONE, Side.RIGHT)
	check(again.hash() == left_plan.hash(), "The same inputs give the same plan")
	# Tuning comes from the profile: a wider straight-ahead band turns a mild lateral into the passive choice.
	var wide := CoverPostureProfile.new()
	wide.straight_ahead_threshold = 0.5
	check(_plan(Vector3(2, 0, 4), _found(), true, 0, Side.RIGHT, wide).side == Side.RIGHT, "The straight-ahead band is a profile parameter")
	check(CoverPostureProfile.new().attack_aim_yaw_degrees == 0.0, "By default the aimed attack stance is square to the target (the rifle points where the facing does)")

func _run() -> void:
	_run_pure()
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD)
	f.battle.set_debug_enemy_control(true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	# A FULL wall of three cells at z=12 (x 5..7); the unit stands centred behind it at (6, 0, 11), facing +z (its right is -x).
	for x in [5, 6, 7]:
		f.set_cover(Vector3i(x, 0, 12), MapCellData.CoverType.FULL, 2.2)
	f.place(actor, Vector3i(6, 0, 11))
	f.ready_actor(actor, 6, 8)
	f.act_as(actor)
	var adapter := actor.visual_adapter
	for i in 20: await process_frame
	adapter.present_idle()
	await create_timer(1.0).timeout
	check(adapter.get_presentation_state() == &"cover_high" and adapter.cover_side == CoverEdgeSelector.Side.RIGHT and adapter.attack_plan.is_empty(), "Passive: behind the wall's centre the unit peeks right and has no attack plan (state %s side %d)" % [adapter.get_presentation_state(), adapter.cover_side])

	var cell_before := actor.grid_position
	var world_before := actor.global_position
	var ap_before := actor.stats.current_ap
	var observed := {"states": [], "muzzle_error": 99.0, "worst_rate": 0.0, "plan_mode": -1, "plan_side": 0}
	adapter.shot_fired.connect(func(_timeline: Dictionary) -> void:
		var to_target := enemy.global_position - adapter.muzzle_socket.global_position
		to_target.y = 0.0
		var muzzle_dir := adapter.muzzle_socket.global_basis.z
		muzzle_dir.y = 0.0
		observed.muzzle_error = rad_to_deg(muzzle_dir.angle_to(to_target)))

	# ---- Attack 1: the enemy is far to the LEFT (+x) of the wall, a legal shot. Passive preference was RIGHT.
	f.place(enemy, Vector3i(11, 0, 12))
	var query: AttackQueryResult = f.battle.query_attack(actor, enemy)
	check(query.is_legal(), "Setup: the attack round the left end is tactically legal")
	await _fire_and_measure(f, adapter, actor, enemy, observed)
	var first_plan: Dictionary = adapter.attack_plan_log.back()
	check(int(first_plan.mode) == CoverEdgeSelector.FiringMode.AROUND_LEFT, "A real attack on a target to the left presents AROUND_LEFT (mode %d, lateral %.2f)" % [int(first_plan.mode), float(first_plan.lateral)])
	check(&"shoot_left" in observed.states, "...with the left-leaning shot (states %s)" % [observed.states])
	check(float(observed.muzzle_error) < 8.0, "The rifle points at the target when it fires (error %.1f deg)" % float(observed.muzzle_error))
	check(float(observed.worst_rate) < 900.0, "No muzzle jump through the attack (worst %.0f deg/s)" % float(observed.worst_rate))
	check(actor.grid_position == cell_before and actor.global_position.is_equal_approx(world_before), "The tactical cell and position are untouched by the presentation")
	check(actor.stats.current_ap == ap_before - 1, "The attack cost one AP as before (%d -> %d)" % [ap_before, actor.stats.current_ap])
	check(adapter.attack_plan.is_empty() and adapter.cover_side == CoverEdgeSelector.Side.RIGHT, "After the attack the plan is gone and the passive side (right) is back")
	await create_timer(1.0).timeout
	check(adapter.get_presentation_state() == &"cover_high" and adapter.aim_blend < 0.05, "...and the unit is in its protected cover pose with the weapon down (%s)" % adapter.get_presentation_state())

	# ---- Attack 2: the enemy moves to the RIGHT (-x) side; the next attack uses the other edge, once, with no flicker during the attack.
	observed.states = []
	observed.muzzle_error = 99.0
	observed.worst_rate = 0.0
	f.place(enemy, Vector3i(1, 0, 12))
	check(f.battle.query_attack(actor, enemy).is_legal(), "Setup: the attack round the right end is tactically legal")
	await _fire_and_measure(f, adapter, actor, enemy, observed)
	var second_plan: Dictionary = adapter.attack_plan_log.back()
	check(int(second_plan.mode) == CoverEdgeSelector.FiringMode.AROUND_RIGHT, "The next target, to the right, presents AROUND_RIGHT (mode %d)" % int(second_plan.mode))
	check(&"shoot_right" in observed.states and not (&"shoot_left" in observed.states), "...and only the right-leaning shot is shown (states %s)" % [observed.states])
	check(float(observed.muzzle_error) < 8.0 and float(observed.worst_rate) < 900.0, "Switching targets keeps the rifle on target (error %.1f deg, worst %.0f deg/s)" % [float(observed.muzzle_error), float(observed.worst_rate)])
	check(adapter.attack_plan_log.size() == 2, "Exactly one plan per attack (no mid-attack re-planning): %d" % adapter.attack_plan_log.size())
	await create_timer(1.0).timeout

	# ---- No hidden-target knowledge: the plan depends only on the authorized target position, not on where other units stand.
	var probe_position: Vector3 = f.grid.grid_to_world(Vector3i(11, 0, 12))
	var plan_a := adapter._plan_attack_posture(adapter._cover_context(), probe_position)
	f.place(enemy, Vector3i(6, 0, 16))
	var plan_b := adapter._plan_attack_posture(adapter._cover_context(), probe_position)
	check(plan_a.hash() == plan_b.hash(), "Moving the enemy (not the authorized target position) cannot change the plan")
	var passive_before: int = adapter.cover_side
	adapter.face_world_position(adapter.global_position + Vector3(-5, 0, 0))
	check(adapter.cover_side == passive_before and adapter.attack_plan.is_empty(), "Merely facing somewhere neither plans an attack nor changes the passive side")


	# ---- Damage taken while firing round an edge: the cover pose (crouch, yaw) is held through the hit and the plan ends with the attack.
	for x in [5, 6, 7]:
		f.set_cover(Vector3i(x, 0, 12), MapCellData.CoverType.FULL, 2.2)
	enemy.stats.current_hp = enemy.stats.max_hp   # the earlier attacks must not defeat it
	f.place(enemy, Vector3i(11, 0, 12))
	f.ready_actor(actor, 3, 8)
	adapter.present_idle()
	await create_timer(1.0).timeout
	var hit_done: Array = []
	var shoot := func() -> void:
		await f.battle.try_attack(actor, enemy)
		hit_done.append(true)
	shoot.call()
	var lowest_depth := 99.0
	var hit_sent := false
	var hit_guard := 0
	while (hit_done.is_empty() or adapter.attack_phase != UnitVisualAdapter.AttackPhase.NONE) and hit_guard < 1500:
		hit_guard += 1
		await process_frame
		lowest_depth = minf(lowest_depth, adapter.crouch_modifier.depth) if hit_sent else lowest_depth
		if not hit_sent and adapter.attack_phase == UnitVisualAdapter.AttackPhase.RECOVER:
			hit_sent = true
			adapter.present_hit()
			lowest_depth = adapter.crouch_modifier.depth
	await create_timer(0.3).timeout
	check(hit_sent and lowest_depth > 0.02, "A hit during the shot keeps the cover crouch (lowest depth %.2f)" % lowest_depth)
	await create_timer(1.5).timeout
	check(adapter.attack_plan.is_empty() and adapter.get_presentation_state() == &"cover_high" and adapter.cover_side == CoverEdgeSelector.Side.RIGHT, "...and the unit is back in passive cover on its passive side (%s, side %d)" % [adapter.get_presentation_state(), adapter.cover_side])

	# ---- A side the geometry cannot support: the wall runs far to the right, so the right edge is out of reach. A target on the right gets the conservative
	# passive pose and a recorded mismatch (the presentation never creates a shot: whether such a shot is legal is the tactical layer's answer).
	for x in [2, 3, 4]:
		f.set_cover(Vector3i(x, 0, 12), MapCellData.CoverType.FULL, 2.2)
	adapter.present_idle()
	await create_timer(1.0).timeout
	var cover := adapter._cover_context()
	var unsupported := adapter._plan_attack_posture(cover, f.grid.grid_to_world(Vector3i(0, 0, 14)))
	check(adapter.cover_edges.right.usable == false and adapter.cover_edges.left.usable == true, "Setup: only the left edge is usable")
	check(unsupported.mismatch == "target_side_edge_unusable" and int(unsupported.side) == CoverEdgeSelector.Side.LEFT, "A right-hand target with no usable right edge: passive (left) pose, mismatch recorded (%s)" % unsupported.mismatch)
	check(adapter.attack_plan.is_empty(), "Planning alone starts no attack and shows nothing")
	var left_only := adapter._plan_attack_posture(cover, f.grid.grid_to_world(Vector3i(12, 0, 12)))
	check(int(left_only.mode) == CoverEdgeSelector.FiringMode.AROUND_LEFT and left_only.mismatch.is_empty(), "A left-hand target with the one usable (left) edge is engaged round it with no mismatch")

	# ---- Low cover: a real attack is fired over the top (no lean), square to the target.
	for x in [2, 3, 4, 5, 6, 7]:
		f.set_cover(Vector3i(x, 0, 12), MapCellData.CoverType.LOW, 0.9)
	enemy.stats.current_hp = enemy.stats.max_hp
	f.place(enemy, Vector3i(6, 0, 15))
	f.ready_actor(actor, 3, 8)
	adapter.present_idle()
	await create_timer(1.0).timeout
	var low_query: AttackQueryResult = f.battle.query_attack(actor, enemy)
	check(low_query.is_legal(), "Setup: an attack over low cover is tactically legal")
	var low_states := {"states": [], "muzzle_error": 99.0, "worst_rate": 0.0}
	await _fire_and_measure(f, adapter, actor, enemy, low_states)
	var low_plan: Dictionary = adapter.attack_plan_log.back()
	check(int(low_plan.mode) == CoverEdgeSelector.FiringMode.OVER_COVER and &"shoot" in low_states.states and not (&"shoot_left" in low_states.states or &"shoot_right" in low_states.states), "Low cover is fired over the top with the straight shot (mode %d, states %s)" % [int(low_plan.mode), low_states.states])
	check(float(low_states.worst_rate) < 900.0, "...without a muzzle jump (worst %.0f deg/s)" % float(low_states.worst_rate))

	# ---- Leaving cover right after firing leaves nothing of the attack posture behind.
	enemy.stats.current_hp = enemy.stats.max_hp
	f.place(enemy, Vector3i(11, 0, 12))
	f.ready_actor(actor, 3, 8)
	var moved := []
	var go := func() -> void:
		await f.battle.try_attack(actor, enemy)
		moved.append(await f.battle.try_move(actor, Vector3i(5, 0, 10)))
	go.call()
	var guard := 0
	while moved.is_empty() and guard < 900:
		guard += 1
		await process_frame
	await create_timer(1.0).timeout
	check(adapter.attack_plan.is_empty() and absf(adapter._cover_yaw) < deg_to_rad(1.0) and adapter.crouch_modifier.depth < 0.01, "Attack then move out of cover: no plan, yaw offset or crouch is left behind (plan %s, yaw %.1f, depth %.2f, cell %s, moved %s, AP %d, why %s)" % [adapter.attack_plan, rad_to_deg(adapter._cover_yaw), adapter.crouch_modifier.depth, actor.grid_position, moved, actor.stats.current_ap, f.battle.action_service.last_rejection.message if f.battle.action_service.last_rejection else "-"])

	await f.dispose(self)
	print("Cover target-aware firing: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## Runs one production attack to completion, sampling the muzzle per frame and the presentation states passed through.
func _fire_and_measure(f, adapter: UnitVisualAdapter, actor: TacticalUnit, enemy: TacticalUnit, observed: Dictionary) -> void:
	var done: Array = []
	var attack := func() -> void:
		await f.battle.try_attack(actor, enemy)
		done.append(true)
	attack.call()
	var previous := Vector3.ZERO
	var last_ticks := Time.get_ticks_msec()
	var guard := 0
	while (done.is_empty() or adapter.attack_phase != UnitVisualAdapter.AttackPhase.NONE) and guard < 1200:
		guard += 1
		await process_frame
		var now := Time.get_ticks_msec()
		var dt := maxf((now - last_ticks) / 1000.0, 0.001)
		last_ticks = now
		var direction := adapter.muzzle_socket.global_basis.z.normalized()
		if previous != Vector3.ZERO:
			observed.worst_rate = maxf(float(observed.worst_rate), rad_to_deg(direction.angle_to(previous)) / dt)
		previous = direction
		var state := adapter.get_presentation_state()
		if not (state in observed.states):
			observed.states.append(state)
