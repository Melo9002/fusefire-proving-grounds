extends SceneTree
## Provisional balance baseline, not a claim about human playtest enjoyment.
## Exercises real query/commit/Guard resolution with fixed seeds and physical cover.
const SAMPLES := 128
const FIRST_SEED := 60000
var checks := 0
var failures := 0
var grid: GridManager
var floor_mesh: CSGBox3D
var turns: TurnManager
var service: TacticalActionService
var actor: TacticalUnit
var target: TacticalUnit
var rows: Array[Dictionary] = []
var samples := SAMPLES
var case_filter := ""

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _unit(id: StringName, faction: TacticalUnit.Faction) -> TacticalUnit:
	var unit := TacticalUnit.new()
	unit.tactical_id = id
	unit.faction = faction
	unit.show_world_hud = false
	unit.attack_range = 10
	unit.stats = UnitStats.new()
	unit.stats.base_ap = 3
	unit.tactical_state = TacticalState.new()
	unit.add_child(unit.stats)
	unit.add_child(unit.tactical_state)
	root.add_child(unit)
	return unit

func _place(unit: TacticalUnit, cell: Vector3i) -> void:
	grid.update_unit_position(unit, unit.grid_position, cell)
	unit.global_position = grid.grid_to_world(cell) + Vector3.UP * unit.standing_height

func _prepare(spec: Dictionary) -> void:
	grid.map_data = TacticalMapBuilder.generate(32, 32, 1, 17)
	grid.occupancy_map.clear()
	var source := Vector3i(5, 0, 16)
	var destination := Vector3i(10, 0, 16)
	var distance: float = spec.get("distance", 5.0)
	var height: float = spec.get("height", 0.0)
	var horizontal := sqrt(distance * distance - height * height)
	var cover_height: float = spec.get("cover", 0.0)
	if cover_height > 0:
		var scene := Node3D.new()
		var part := Node3D.new()
		part.position = grid.get_cell_data(destination).support_center + Vector3(-0.65, cover_height * 0.5, 0)
		part.set_meta("solid_size", Vector3(1, cover_height, 0.4))
		scene.add_child(part)
		AuthoredSceneMapCompiler.compile(scene, grid.map_data, 1)
		scene.free()
		SurfaceNavigation.resolve_map(grid.map_data, 1)
		if spec.get("flank", false): source = Vector3i(15, 0, 16)
	# Controlled actual heights/distance are applied AFTER the compiler resolves
	# base support. Compiling earlier offsets resets them to supported ground.
	grid.get_cell_data(source).world_position.y = height
	if not spec.get("flank", false):
		grid.get_cell_data(source).world_position.x = grid.get_cell_data(destination).world_position.x - horizontal
	_place(actor, source)
	_place(target, destination)

func _reset_states(spec: Dictionary) -> void:
	for unit in [actor, target]:
		unit.tactical_state.reset()
		unit.stats.current_hp = 100
		unit.stats.set_available_ap_for_setup(3)
		unit.stats.current_supply_points = 4
	turns.current_phase = TurnManager.TurnPhase.PLAYER_TURN
	turns.active_unit = actor
	if spec.get("shield", false):
		var facing := CombatRules.shield_direction(target.grid_position, actor.grid_position, grid)
		if spec.get("rear", false): facing = -facing
		target.tactical_state.establish_shield(facing)

func _case(spec: Dictionary) -> void:
	_prepare(spec)
	_reset_states(spec)
	var is_guard: bool = spec.get("guard", false)
	var chance := -1
	var on_hit := -1
	var hits := 0
	var total_damage := 0
	var all_hit_salvos := 0
	var salvo_hits := 0
	var worst_miss_streak := 0
	var miss_streak := 0
	var evidence := ""
	for index in samples:
		# Long synchronous batches must let engine/deferred work drain.
		if index % 32 == 0: await process_frame
		_reset_states(spec)
		service._combat_rng.seed = FIRST_SEED + index
		if spec.get("aim", false):
			var aim := await service.submit_aim(service.make_aim_request(actor, TacticalActionRequest.Source.PLAYER), true)
			check(aim != null and actor.stats.current_ap == 2, "Aim pays its actual AP cost")
		var before_rng := service.get_combat_rng_state()
		var query := service.query_attack(actor.tactical_id, target.tactical_id)
		check(query.is_legal(), "Controlled shot is legal: " + spec.name)
		if not query.is_legal(): return
		var predicted_chance := query.hit_chance
		var predicted_damage := query.damage_on_hit
		if is_guard:
			var guard := await service.submit_overwatch(service.make_overwatch_request(actor, TacticalActionRequest.Source.PLAYER), true)
			check(guard != null and actor.stats.current_ap == 0, "Guard pays all remaining AP")
			var reaction := service.query_guard_reaction(actor, target)
			check(reaction.can_fire, "Guard has a real legal opportunity")
			predicted_chance = reaction.evaluation.hit_chance
			predicted_damage = CombatRules.cover_tuning.damage_for_hit(reaction.evaluation.shield_damage_multiplier)
		check(service.get_combat_rng_state() == before_rng, "Predictions consume no rolls")
		var result: AttackActionResult
		if is_guard:
			turns.current_phase = TurnManager.TurnPhase.ENEMY_TURN
			turns.active_unit = target
			result = await service.submit_attack(service.make_attack_request(target, actor, TacticalActionRequest.Source.AI), true)
		else:
			result = await service.submit_attack(service.make_attack_request(actor, target, TacticalActionRequest.Source.PLAYER), true)
		check(result != null, "Controlled attack commits")
		if result == null: return
		var hit := result.did_hit
		var damage := result.damage
		var roll := result.roll
		var actual_chance := result.hit_chance
		var mirror := RandomNumberGenerator.new()
		mirror.seed = FIRST_SEED + index
		var expected_roll := mirror.randf() * 100.0
		if is_guard:
			check(result.reaction_events.size() == 1, "Guard fires exactly once")
			if result.reaction_events.size() != 1: return
			var event := result.reaction_events[0]
			hit = event.did_hit
			damage = event.damage
			roll = event.roll
			actual_chance = event.hit_chance
			expected_roll = mirror.randf() * 100.0
			check(not actor.tactical_state.is_overwatching and actor.stats.current_supply_points == 3, "Hit or miss consumes one Guard reservation and SP")
		check(is_equal_approx(roll, expected_roll) and actual_chance == predicted_chance and hit == AttackActionResult.roll_hits(expected_roll, predicted_chance), "Actual deterministic roll agrees with prediction")
		check(damage == (predicted_damage if hit else 0), "Accuracy never scales damage on hit")
		if chance < 0:
			check(predicted_damage == spec.get("damage", 25), "Deliberate fixed damage baseline: " + spec.name)
			chance = predicted_chance
			on_hit = predicted_damage
		check(chance == predicted_chance and on_hit == predicted_damage, "Trials preserve the same encounter")
		hits += int(hit)
		total_damage += damage
		salvo_hits += int(hit)
		miss_streak = 0 if hit else miss_streak + 1
		worst_miss_streak = maxi(worst_miss_streak, miss_streak)
		if index % 4 == 3:
			all_hit_salvos += int(salvo_hits == 4)
			salvo_hits = 0
		evidence = (evidence + "%s:%s:%s;" % [roll, hit, damage]).sha256_text()
	var observed := float(hits) / samples
	var probability := float(chance) / 100
	# Fixed sample + six binomial standard errors: distribution diagnostic,
	# not a balance assertion or permission to change the seed to get a pass.
	var tolerance := 6 * sqrt(probability * (1 - probability) / samples) + 1.0 / samples
	check(absf(observed - probability) <= tolerance, "Seeded hit rate matches advertised probability: " + spec.name)
	if chance == 100: check(hits == samples and worst_miss_streak == 0, "100% means guaranteed")
	check(chance == spec.chance, "Deliberate provisional chance baseline: " + spec.name)
	var row := {"name": spec.name, "chance": chance, "damage_on_hit": on_hit, "hits": hits, "shots": samples, "observed_percent": observed * 100, "mean_damage": float(total_damage) / samples, "all_four_hit_salvos": all_hit_salvos, "salvos": samples / 4, "longest_miss_streak": worst_miss_streak, "evidence_hash": evidence}
	rows.append(row)
	print("[Reliability] ", JSON.stringify(row))

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 1: case_filter = args[1]
	if args.size() > 2: samples = maxi(4, int(args[2]))
	# The combined 34k-shot process reproducibly crashes in native shutdown.
	# Keep ordinary coverage bounded; measure every large condition in its own
	# process with tools/measure_combat_reliability.ps1. No assertion is omitted.
	if samples > 2048 or (samples > SAMPLES and case_filter.is_empty()):
		push_error("Large measurements require one exact condition per process (maximum 2048 trials). Use tools/measure_combat_reliability.ps1.")
		quit(2)
		return
	grid = GridManager.new()
	root.add_child(grid)
	# Match real battles: spatial shot indexing needs the owning floor. A
	# floor-less grid takes the legacy whole-map fallback on every sample.
	floor_mesh = CSGBox3D.new()
	floor_mesh.size = Vector3(32, 0.1, 32)
	floor_mesh.position.y = -0.05
	root.add_child(floor_mesh)
	grid.map_floor = floor_mesh
	turns = TurnManager.new()
	root.add_child(turns)
	actor = _unit(&"StudyPlayer", TacticalUnit.Faction.PLAYER)
	target = _unit(&"StudyEnemy", TacticalUnit.Faction.ENEMY)
	target.shield_capability = ShieldCapability.new()
	turns.player_units.assign([actor])
	turns.enemy_units.assign([target])
	service = TacticalActionService.new()
	root.add_child(service)
	service.setup(turns, grid, null, FIRST_SEED, Callable())
	check(service.register_actor(actor) and service.register_actor(target), "Study actors register")
	var tuning_signature: String = CombatRules.cover_tuning.signature()
	var specs := [
		{"name": "exposed_close", "chance": 100},
		{"name": "low_cover", "cover": 0.8, "chance": 80},
		{"name": "full_cover_high", "cover": 1.3, "height": 2.2, "chance": 71},
		{"name": "full_cover_level", "cover": 1.3, "chance": 60},
		{"name": "full_cover_level_aim", "cover": 1.3, "aim": true, "chance": 95},
		{"name": "flanked_low_cover", "cover": 0.8, "flank": true, "chance": 100},
		{"name": "low_cover_aim", "cover": 0.8, "aim": true, "chance": 100},
		{"name": "range_70", "distance": 7.0, "chance": 96},
		{"name": "range_80", "distance": 8.0, "chance": 83},
		{"name": "range_90", "distance": 9.0, "chance": 61},
		{"name": "range_limit", "distance": 10.0, "chance": 30},
		{"name": "range_limit_aim", "distance": 10.0, "aim": true, "chance": 65},
		{"name": "range_limit_high_aim", "distance": 10.0, "height": 2.0, "aim": true, "chance": 75},
		{"name": "range_limit_low", "distance": 10.0, "height": -2.0, "chance": 20},
		{"name": "shield_front", "shield": true, "chance": 80, "damage": 9},
		{"name": "shield_rear", "shield": true, "rear": true, "chance": 100},
		{"name": "guard_close", "guard": true, "chance": 85},
	]
	for spec in specs:
		if case_filter.is_empty() or (spec.name == case_filter if samples > SAMPLES else case_filter in spec.name): await _case(spec)
	check(not rows.is_empty(), "At least one condition matches the requested filter")
	check(CombatRules.cover_tuning.signature() == tuning_signature, "Measurement does not mutate balance")
	var output := "res://artifacts/combat-reliability.json"
	if args.size() > 0: output = args[0]
	var file := FileAccess.open(output, FileAccess.WRITE)
	check(file != null, "Write repeatable balance measurements")
	if file:
		file.store_string(JSON.stringify({"first_seed": FIRST_SEED, "samples_per_case": samples, "tuning_signature": tuning_signature, "rows": rows}, "\t"))
		file.close()
	# Match battle teardown: release nodes on a frame boundary, after all
	# synchronous action continuations/signals have unwound.
	for node in [service, actor, target, turns, grid, floor_mesh]: node.queue_free()
	await process_frame
	await process_frame
	print("Combat reliability: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
