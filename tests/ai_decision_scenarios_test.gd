extends SceneTree
## Milestone 05 step 3: controlled AI decision scenarios.
## Each scenario fixes a setup, lists the legal options from the shared queries, and
## states what a reasonable decision looks like. Hard rules (legality, resources,
## explanation) are asserted for every scenario. Preferences are asserted as properties
## ("the chosen target is no worse than the best legal one"), never as one exact tile.
## Behavior the AI does not have yet is documented in docs/claude/ai-scenarios-2026-11-18.md
## instead of being asserted here.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

signal release_extraction

var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

## Rules every decision must obey, whatever the preference outcome.
func hard_rules(f, unit, r: Dictionary, label: String) -> void:
	print("[Scenario] %s start %s end %s AP spent %d actions %s committed %s | %s" % [label, r.start, r.end, r.ap_spent,
		r.actions, r.committed, String(r.decisions[-1].reason) if not r.decisions.is_empty() else "no decision recorded"])
	check(r.rejected.is_empty(), "%s: no action is rejected by the authoritative service" % label)
	check(r.ap_spent <= 3, "%s: AP stays within budget" % label)
	if r.present:  # a unit that extracted has left the battle; there is nothing more to check on its cell
		check(unit.stats.current_ap >= 0 and unit.stats.current_supply_points >= 0, "%s: AP and ammo never go negative" % label)
		var cell: MapCellData = f.grid.get_cell_data(r.end)
		var occupant: TacticalUnit = f.grid.get_unit_at(r.end)
		check(cell != null and (cell.walkable or cell.cover_type == MapCellData.CoverType.LOW) and occupant == unit,
			"%s: ends on a legal cell it alone occupies (cell %s walkable %s occupant %s)" % [label, cell != null, cell.walkable if cell else "-", occupant.name if occupant else "none"])
	check(not r.decisions.is_empty() and not String(r.decisions[-1].reason).is_empty(), "%s: the decision is explained" % label)

func _run() -> void:
	Engine.time_scale = 12.0
	await _cover_changes_target_choice()
	await _flank_opportunity()
	await _wounded_finisher()
	await _shielded_target()
	await _height_advantage()
	await _empty_ammo_reloads()
	await _blocked_corridor()
	await _open_corridor()
	await _guard_explains_its_trigger()
	await _flat_map_approach()
	await _reposition_for_a_better_shot()
	await _good_shot_is_kept()
	await _reposition_needs_ap_to_fire()
	await _reposition_is_deterministic()
	await _easy_does_not_reposition()
	await _wound_priority_uses_shot_reliability()
	await _evacuation_intercept()
	await _evacuation_intercept(false)
	await _mission_route_never_rolls_a_lapse()
	await _shield_when_stuck_under_fire()
	await _no_shield_without_a_threat()
	await _shield_over_last_shot()
	await _shot_over_shield_for_a_kill()
	await _extraction_in_zone()
	await _extraction_handoff_waits_for_settlement()
	await _extraction_en_route()
	await _rescue_pickup()
	await _carrier_corridor_recovery(true)
	await _carrier_corridor_recovery(false)
	await _carrier_corridor_recovery(true, true)
	await _carrier_corridor_recovery(true, false, true)
	await _carrier_handoff_after_defeat()
	Engine.time_scale = 1.0
	print("AI decision scenarios: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _duel(enemies := 2, mission: MissionDefinition = null, archetypes: Array[StringName] = []):
	var f := Fixture.new()
	await f.setup(self, 1, enemies, 0, mission, AIDifficultyPolicy.Tier.HARD, archetypes)
	return f

## S1 cover: two equal hostiles, one behind real low cover.
## Options: both legal, the covered one with a lower chance. Reasonable: shoot the exposed one.
func _cover_changes_target_choice() -> void:
	var f = await _duel()
	var actor: TacticalUnit = f.turns.player_units[0]
	var covered: TacticalUnit = f.turns.enemy_units[0]
	var exposed: TacticalUnit = f.turns.enemy_units[1]
	f.place(actor, Vector3i(5, 0, 10)); f.place(covered, Vector3i(10, 0, 8)); f.place(exposed, Vector3i(10, 0, 12))
	f.set_cover(Vector3i(9, 0, 8), MapCellData.CoverType.LOW, 0.9)
	f.ready_actor(actor)
	var legal: Dictionary = f.legal_attacks(actor)
	check(legal.size() == 2 and legal[String(covered.name)].hit_chance < legal[String(exposed.name)].hit_chance, "S1 setup: both shots are legal and cover lowers one chance")
	var chosen: TacticalUnit = f.choose_target(actor)
	check(chosen != null and legal[String(chosen.name)].expected_damage >= f.best_expected_damage(actor) - 0.001, "S1: the chosen target is no worse than the best legal expected damage")
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S1")
	check("attack" in r.committed, "S1: with legal shots and AP the unit shoots")
	await f.dispose(self)

## S2 wounded: one hostile can be defeated by a single hit.
func _wounded_finisher() -> void:
	var f = await _duel()
	var actor: TacticalUnit = f.turns.player_units[0]
	var wounded: TacticalUnit = f.turns.enemy_units[0]
	var healthy: TacticalUnit = f.turns.enemy_units[1]
	f.place(actor, Vector3i(5, 0, 10)); f.place(wounded, Vector3i(10, 0, 8)); f.place(healthy, Vector3i(10, 0, 12))
	f.ready_actor(actor)
	wounded.stats.current_hp = 25
	var legal: Dictionary = f.legal_attacks(actor)
	check(legal.size() == 2 and legal[String(wounded.name)].damage_on_hit >= wounded.stats.current_hp, "S2 setup: one hit defeats the wounded hostile")
	var chosen: TacticalUnit = f.choose_target(actor)
	check(chosen == wounded, "S2: a legal single-hit finisher is chosen over a healthy equal target")
	await f.dispose(self)

## S3 shielded: one hostile holds Shield Stance toward the shooter (hits deal 9, not 25).
func _shielded_target() -> void:
	var archetypes: Array[StringName] = [&"shieldbearer", &"generic"]
	var f = await _duel(2, null, archetypes)
	var actor: TacticalUnit = f.turns.player_units[0]
	var shielded: TacticalUnit = f.turns.enemy_units[0]
	var open: TacticalUnit = f.turns.enemy_units[1]
	f.place(actor, Vector3i(5, 0, 10)); f.place(shielded, Vector3i(10, 0, 8)); f.place(open, Vector3i(10, 0, 12))
	f.ready_actor(actor)
	shielded.stats.set_available_ap_for_setup(3)
	f.act_as(shielded)
	var service: TacticalActionService = f.battle.action_service
	var raised = await service.submit_shield(service.make_shield_request(shielded, actor, TacticalActionRequest.Source.AI), true)
	check(raised != null and shielded.tactical_state.is_shielding, "S3 setup: the hostile raises Shield Stance")
	f.act_as(actor)
	f.ready_actor(actor)
	var legal: Dictionary = f.legal_attacks(actor)
	check(legal.has(String(shielded.name)) and legal.has(String(open.name)) and legal[String(shielded.name)].damage_on_hit < legal[String(open.name)].damage_on_hit, "S3 setup: Shield reduces predicted damage")
	var chosen: TacticalUnit = f.choose_target(actor)
	check(chosen != null and legal[String(chosen.name)].expected_damage >= f.best_expected_damage(actor) - 0.001, "S3: the chosen target is no worse than the best legal expected damage")
	check(chosen == open, "S3: the unshielded hostile is preferred at equal range and health")
	await f.dispose(self)

## S4 height: equal targets at long range, one standing lower (height advantage helps the shooter).
func _height_advantage() -> void:
	var f = await _duel()
	var actor: TacticalUnit = f.turns.player_units[0]
	var level_target: TacticalUnit = f.turns.enemy_units[0]
	var low_target: TacticalUnit = f.turns.enemy_units[1]
	# Offsets (8,1) and (8,0) with a one-level drop give equal 3D distance (sqrt 65 each),
	# so only the height modifier differs between the two shots.
	f.grid.get_cell_data(Vector3i(11, 0, 10)).world_position.y -= 1.0
	f.place(actor, Vector3i(3, 0, 10)); f.place(level_target, Vector3i(11, 0, 11)); f.place(low_target, Vector3i(11, 0, 10))
	f.ready_actor(actor)
	var legal: Dictionary = f.legal_attacks(actor)
	check(legal.size() == 2 and legal[String(low_target.name)].hit_chance > legal[String(level_target.name)].hit_chance, "S4 setup: the lower target is easier to hit")
	var chosen: TacticalUnit = f.choose_target(actor)
	check(chosen != null and legal[String(chosen.name)].expected_damage >= f.best_expected_damage(actor) - 0.001, "S4: the chosen target is no worse than the best legal expected damage")
	await f.dispose(self)

## S5 ammo: no Supply Points, a clear shot available, two AP.
## Reasonable: reload first (an Attack with no ammo is illegal), then shoot with what remains.
func _empty_ammo_reloads() -> void:
	var f = await _duel(1)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(5, 0, 10)); f.place(enemy, Vector3i(10, 0, 10))
	f.ready_actor(actor, 2, 0)
	check(f.legal_attacks(actor).is_empty(), "S5 setup: with no ammo no attack is legal")
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S5")
	var reload_at: int = r.committed.find("reload")
	var attack_at: int = r.committed.find("attack")
	check(reload_at >= 0, "S5: the unit reloads rather than idling with a target in range")
	check(attack_at == -1 or attack_at > reload_at, "S5: no attack is committed before ammo is restored")
	await f.dispose(self)

## S6 crowded corridor: a one-cell corridor with an ally standing in it, hostile beyond.
## No legal passage exists. Reasonable: hold or reposition legally, with a stated reason.
func _blocked_corridor() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 1, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var ally: TacticalUnit = f.turns.allied_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.wall_band(10, 14, 28)
	f.place(actor, Vector3i(3, 0, 28)); f.place(ally, Vector3i(12, 0, 28)); f.place(enemy, Vector3i(28, 0, 28))
	f.ready_actor(actor)
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S6")
	check(r.end.x < 10 and f.grid.get_unit_at(Vector3i(12, 0, 28)) == ally, "S6: the unit does not pass or displace the ally in the corridor")
	# Issue #42: the reason must say the route is blocked and by whom, not that no destination exists.
	var wait_reason := String(r.decisions[-1].reason) if not r.decisions.is_empty() else ""
	check(wait_reason.contains(String(ally.name)) and wait_reason.contains("blocked"), "S6: the wait reason names the blocking ally (%s)" % wait_reason)
	check(not wait_reason.contains("no reachable legal destination"), "S6: the wait reason no longer claims there is no legal destination (%s)" % wait_reason)
	var wait_id := int(r.decisions[-1].decision_id)
	check(r.outcomes.any(func(outcome: Dictionary) -> bool:
		return outcome.action == "wait" and outcome.stage == "committed" and outcome.decision_id == wait_id),
		"S6: the blocked-route Wait links to its authoritative submission")
	await f.dispose(self)

## S6b the same corridor with the ally gone: progress through it must be possible.
func _open_corridor() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.wall_band(10, 14, 28)
	f.place(actor, Vector3i(3, 0, 28)); f.place(enemy, Vector3i(28, 0, 28))
	f.ready_actor(actor)
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S6b")
	check(r.end.x > 3, "S6b: with the corridor free the unit advances toward the hostile")
	await f.dispose(self)

func _guard_explains_its_trigger() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1)
	var actor: TacticalUnit = f.turns.player_units[0]
	var hostile: TacticalUnit = f.turns.enemy_units[0]
	var start := Vector3i(5, 0, 12)
	f.place(actor, start)
	f.place(hostile, Vector3i(17, 0, 12))
	var walls: Array[Vector3i] = []
	for dx in range(-1, 2):
		for dz in range(-1, 2):
			if dx != 0 or dz != 0: walls.append(start + Vector3i(dx, 0, dz))
	f.set_walls(walls)
	f.ready_actor(actor, 1)
	var run := await f.activate(actor, self)
	hard_rules(f, actor, run, "Guard trace")
	var guards: Array = run.decisions.filter(func(row: Dictionary) -> bool: return row.action == "Guard")
	check("overwatch" in run.committed and guards.size() == 1, "Guard trace: boxed actor reserves an authoritative reaction")
	if not guards.is_empty():
		check(guards[0].reason.contains(String(hostile.name)) and guards[0].reason.contains("within one move of range"),
			"Guard trace names the threat and the heuristic the planner used")
		var receipt: Dictionary = guards[0].get("linked_outcome", {})
		check(receipt.get("action") == "overwatch" and receipt.get("sp_before") == receipt.get("sp_after"),
			"Guard trace links to its commitment without reporting spent reaction ammo")
	await f.dispose(self)

## S6c legacy flat map (no surface placement), open ground, hostile 21 cells away. Reasonable: advance.
## Issue #44: the approach used to find no path to the occupied target cell and the unit just waited.
func _flat_map_approach() -> void:
	var f = await _duel(1)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	check(not f.grid.map_data.surface_placement_enabled, "S6c setup: the fixture map is the legacy flat map")
	f.place(actor, Vector3i(3, 0, 12)); f.place(enemy, Vector3i(24, 0, 12))
	f.ready_actor(actor)
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S6c")
	check(r.end.x > 3 and "move" in r.committed, "S6c: on a flat map the unit advances toward a distant hostile (end %s, committed %s)" % [r.end, r.committed])
	await f.dispose(self)

## S9 Move then Attack. A poor shot at the edge of range, and one move reaches a cell with a far better
## shot. Reasonable: reposition once, then fire from the better cell. Not asserted: which tile.
func _poor_shot_setup(ap := 3) -> Array:
	var f = await _duel(1)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(3, 0, 12)); f.place(enemy, Vector3i(13, 0, 12))
	f.ready_actor(actor, ap, 4)
	return [f, actor, enemy]

func _reposition_for_a_better_shot() -> void:
	var setup: Array = await _poor_shot_setup()
	var f = setup[0]
	var actor: TacticalUnit = setup[1]
	var enemy: TacticalUnit = setup[2]
	var before: AttackQueryResult = f.battle.query_attack(actor, enemy)
	check(before.is_legal(), "S9 setup: the edge-of-range shot is legal")
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S9")
	check(r.committed.size() >= 2 and r.committed[0] == "move", "S9: a clearly better shot one move away is taken first (committed %s)" % str(r.committed))
	var reasons := ""
	for decision in r.decisions: reasons += String(decision.reason) + " | "
	check(reasons.contains("Repositioned"), "S9: the move says why (%s)" % reasons.substr(0, 200))
	check("attack" in r.committed, "S9: the unit fires after repositioning")
	check(r.committed.filter(func(action: String) -> bool: return action == "move").size() <= 1, "S9: it repositions at most once")
	if is_instance_valid(enemy) and enemy.stats.current_hp < enemy.stats.max_hp or r.end != r.start:
		var after: AttackQueryResult = f.battle.query_attack(actor, enemy) if is_instance_valid(enemy) else null
		if after != null and after.is_legal():
			check(after.hit_chance > before.hit_chance, "S9: the new cell's shot is better (%d%% to %d%%)" % [before.hit_chance, after.hit_chance])
	await f.dispose(self)

## S9b A good shot stays where it is: no move is worth the AP.
func _good_shot_is_kept() -> void:
	var f = await _duel(1)
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(3, 0, 12)); f.place(enemy, Vector3i(8, 0, 12))
	f.ready_actor(actor)
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S9b")
	check(not r.committed.is_empty() and r.committed[0] != "move", "S9b: a good shot is not abandoned for a move (committed %s)" % str(r.committed))
	check("attack" in r.committed, "S9b: the unit shoots")
	await f.dispose(self)

## S9c A reposition must leave AP to fire: with one AP the unit shoots from where it stands.
func _reposition_needs_ap_to_fire() -> void:
	var setup: Array = await _poor_shot_setup(1)
	var f = setup[0]
	var actor: TacticalUnit = setup[1]
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S9c")
	check(not ("move" in r.committed and r.committed.find("move") < r.committed.find("attack")), "S9c: with one AP it never moves first (committed %s)" % str(r.committed))
	check(r.ap_spent <= 1, "S9c: it stays within its single AP (%d)" % r.ap_spent)
	await f.dispose(self)

## S9d The plan uses no random draws: the same setup gives the same decision.
func _reposition_is_deterministic() -> void:
	var first: Array = await _poor_shot_setup()
	var rf: Dictionary = await first[0].activate(first[1], self)
	var committed_first: Array = rf.committed
	var end_first: Vector3i = rf.end
	await first[0].dispose(self)
	var second: Array = await _poor_shot_setup()
	var rs: Dictionary = await second[0].activate(second[1], self)
	check(rs.committed == committed_first and rs.end == end_first, "S9d: the same setup gives the same plan (%s vs %s)" % [str(committed_first), str(rs.committed)])
	await second[0].dispose(self)

## S9e Easy keeps shooting from where it stands: repositioning is not part of that tier yet.
func _easy_does_not_reposition() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, null, AIDifficultyPolicy.Tier.EASY)
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(3, 0, 12)); f.place(f.turns.enemy_units[0], Vector3i(13, 0, 12))
	f.ready_actor(actor)
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S9e")
	check(not r.committed.is_empty() and r.committed[0] != "move", "S9e: Easy does not reposition for a better shot (committed %s)" % str(r.committed))
	await f.dispose(self)

## Two legal shots: a nearly defeated enemy at the end of the range curve
## and a healthier enemy in the open. There is only AP for a single shot.
func _wound_priority_uses_shot_reliability() -> void:
	for tier in [AIDifficultyPolicy.Tier.NORMAL, AIDifficultyPolicy.Tier.HARD]:
		var f := Fixture.new()
		await f.setup(self, 1, 2, 0, null, tier)
		var actor: TacticalUnit = f.turns.player_units[0]
		var distant: TacticalUnit = f.turns.enemy_units[0]
		var clear: TacticalUnit = f.turns.enemy_units[1]
		f.place(actor, Vector3i(3, 0, 12))
		f.place(distant, Vector3i(13, 0, 12))
		f.place(clear, Vector3i(6, 0, 14))
		distant.stats.take_damage(99)
		clear.stats.take_damage(60)
		f.ready_actor(actor, 1)
		f.act_as(actor)
		var distant_shot := f.battle.query_attack(actor, distant)
		var clear_shot := f.battle.query_attack(actor, clear)
		check(distant_shot.is_legal() and clear_shot.is_legal() and clear_shot.hit_chance > distant_shot.hit_chance + 25,
			"Reliable fire setup: both shots legal, with a material reliability gap (%d vs %d)" % [clear_shot.hit_chance, distant_shot.hit_chance])
		var result := await f.activate(actor, self)
		hard_rules(f, actor, result, "Reliable fire")
		var attacks: Array = result.decisions.filter(func(row: Dictionary) -> bool: return row.action == "Attack")
		var expected := String(clear.name if tier == AIDifficultyPolicy.Tier.HARD else distant.name)
		var selected := String(attacks[0].subject) if not attacks.is_empty() else "none"
		check("attack" in result.committed and attacks.size() == 1 and selected == expected,
			"%s takes its intended one-shot tradeoff (%s)" % [AIDifficultyPolicy.get_label(tier), selected])
		await f.dispose(self)

## The nearer of two hostiles cannot escape on its next turn. The other
## can reach the exit, and the defender has a legal move toward its lane.
func _evacuation_intercept(runner_can_escape := true) -> void:
	var mission := MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.ENEMY_EVACUATION, 2)
	var f := Fixture.new()
	await f.setup(self, 1, 2, 0, mission)
	f.grid.map_data.surface_placement_enabled = true
	f.grid.map_data.surface_points_resolved = true
	f.rebuild_graph()
	f.battle.pathfinder.live_grid = f.grid
	var defender: TacticalUnit = f.turns.player_units[0]
	var nearer: TacticalUnit = f.turns.enemy_units[0]
	var runner: TacticalUnit = f.turns.enemy_units[1]
	var start := Vector3i(22, 0, 8)
	var exit := Vector3i(24, 0, 17)
	f.place(defender, start)
	f.place(nearer, Vector3i(14, 0, 8))
	f.place(runner, Vector3i(19, 0, 17))
	nearer.stats.speed = 2
	runner.stats.speed = 3 if runner_can_escape else 1
	f.grid.map_data.set_objective_zone(&"enemy_extract", [exit])
	f.ready_actor(defender, 1)
	defender.attack_range = 5
	f.act_as(defender)
	check(f.legal_attacks(defender).is_empty(), "Intercept setup: neither enemy is currently shootable")
	var result := await f.activate(defender, self)
	hard_rules(f, defender, result, "Intercept")
	var explains_intercept: bool = result.decisions.any(func(row: Dictionary) -> bool: return "Intercept" in String(row.position_scores))
	if runner_can_escape:
		check("move" in result.committed and result.end.z > start.z and result.end.distance_to(exit) < start.distance_to(exit),
			"Intercept: the defender advances toward the imminent runner's lane instead of chasing the nearer hostile")
		check(explains_intercept, "Intercept: the selected movement trace explains the mission priority")
	else:
		check("move" in result.committed and result.end.distance_to(nearer.grid_position) < start.distance_to(nearer.grid_position) and not explains_intercept,
			"Intercept control: a distant exit or slow runner does not displace the normal approach")
	await f.dispose(self)

func _mission_route_never_rolls_a_lapse() -> void:
	var mission := MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.EXTRACT, 1)
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, mission, AIDifficultyPolicy.Tier.EASY, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var start := Vector3i(5, 0, 28)
	var exit := Vector3i(14, 0, 28)
	f.grid.map_data.set_objective_zone(&"extract", [exit])
	f.place(actor, start)
	f.place(f.turns.enemy_units[0], Vector3i(28, 0, 20))
	f.ready_actor(actor, 1)
	var ai := f.ai_of(actor)
	var policy := ai._ensure_policy()
	policy.lapse_chance = 1.0
	var rng_before := ai._decision_rng.state
	var result := await f.activate(actor, self)
	hard_rules(f, actor, result, "Easy mission route")
	check("move" in result.committed and result.end.distance_to(exit) < start.distance_to(exit),
		"Easy mission route: the unit commits objective progress with one AP")
	check(ai._decision_rng.state == rng_before, "Easy mission route: even a forced lapse leaves the objective and decision RNG untouched")
	await f.dispose(self)

## S10 A unit with a Shield that cannot act on its turn (the corridor is blocked, the hostile out of its
## range) but can be shot at faces the threat: the stance prevents expected damage and costs nothing else.
func _stuck_shield_setup(enemy_range: int) -> Array:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 1, null, AIDifficultyPolicy.Tier.HARD, [], true)
	var actor: TacticalUnit = f.turns.player_units[0]
	var ally: TacticalUnit = f.turns.allied_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	f.wall_band(10, 14, 28)
	f.place(actor, Vector3i(3, 0, 28)); f.place(ally, Vector3i(12, 0, 28)); f.place(enemy, Vector3i(28, 0, 28))
	actor.shield_capability = load("res://units/capabilities/physical_shield.tres")
	f.ready_actor(actor)
	enemy.attack_range = enemy_range
	return [f, actor, enemy]

func _shield_when_stuck_under_fire() -> void:
	var setup: Array = await _stuck_shield_setup(30)
	var f = setup[0]
	var actor: TacticalUnit = setup[1]
	var enemy: TacticalUnit = setup[2]
	check(CombatRules.evaluate_attack(enemy, actor, f.grid, enemy.get_world_3d()).is_legal and not f.battle.query_attack(actor, enemy).is_legal(), "S10 setup: the hostile can shoot the unit, the unit cannot shoot back")
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S10")
	check("shield" in r.committed, "S10: with nothing else to do under fire, a worthwhile Shield is taken (committed %s)" % str(r.committed))
	var reasons := ""
	for decision in r.decisions: reasons += String(decision.reason) + " | "
	check(reasons.contains("prevents about"), "S10: the Shield says what it prevents (%s)" % reasons.substr(0, 220))
	check(actor.tactical_state.is_shielding, "S10: the stance is active")
	await f.dispose(self)

## S10b The same unit with no one able to shoot it has nothing to shield against.
func _no_shield_without_a_threat() -> void:
	var setup: Array = await _stuck_shield_setup(3)
	var f = setup[0]
	var actor: TacticalUnit = setup[1]
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S10b")
	check(not ("shield" in r.committed) and not actor.tactical_state.is_shielding, "S10b: with no shooter in range the unit does not Shield (committed %s)" % str(r.committed))
	await f.dispose(self)

func _bulwark_in_the_open(enemy_count: int, ap: int) -> Array:
	var f := Fixture.new()
	await f.setup(self, 1, enemy_count, 0, null, AIDifficultyPolicy.Tier.HARD)
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(10, 0, 12))
	var cells: Array[Vector3i] = [Vector3i(18, 0, 12), Vector3i(18, 0, 14), Vector3i(18, 0, 10)]
	for index in enemy_count:
		var enemy: TacticalUnit = f.turns.enemy_units[index]
		f.place(enemy, cells[index])
		enemy.attack_range = 10
	actor.shield_capability = load("res://units/capabilities/bulwark_shield.tres")
	f.ready_actor(actor, ap)
	return [f, actor]

## S10c The last AP: three attackers can shoot a Bulwark and the stance prevents more than one more shot
## would deal. It shoots with its earlier AP, then holds the stance with the last one ("attack, Shield").
func _shield_over_last_shot() -> void:
	var setup: Array = await _bulwark_in_the_open(3, 2)
	var f = setup[0]
	var actor: TacticalUnit = setup[1]
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S10c")
	check(r.committed == ["attack", "shield"], "S10c: shoots first, holds the stance with the last AP (committed %s)" % str(r.committed))
	var reasons := ""
	for decision in r.decisions: reasons += String(decision.reason) + " | "
	check(reasons.contains("last shot"), "S10c: the decision says it chose the stance over the last shot (%s)" % reasons.substr(0, 260))
	check(actor.tactical_state.is_shielding, "S10c: the stance is active")
	await f.dispose(self)

## S10d The same unit against one nearly dead target: the last shot is worth more than the stance, so it fires.
func _shot_over_shield_for_a_kill() -> void:
	var setup: Array = await _bulwark_in_the_open(1, 2)
	var f = setup[0]
	var actor: TacticalUnit = setup[1]
	f.turns.enemy_units[0].stats.current_hp = 10
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S10d")
	check(not ("shield" in r.committed) and "attack" in r.committed and not actor.tactical_state.is_shielding, "S10d: a finishing shot (aimed or not) is not given up for the stance (committed %s)" % str(r.committed))
	await f.dispose(self)

func _extract_fixture():
	var f := Fixture.new()
	await f.setup(self, 1, 1, 0, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.EXTRACT, 1), AIDifficultyPolicy.Tier.HARD, [], true)
	return f

## S7 extraction: standing in the exit zone with AP.
func _extraction_in_zone() -> void:
	var f = await _extract_fixture()
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	var exit := Vector3i(6, 0, 28)
	var zone: Array[Vector3i] = [exit]
	f.grid.map_data.set_objective_zone(&"extract", zone)
	f.place(actor, exit); f.place(enemy, Vector3i(28, 0, 20))
	f.ready_actor(actor)
	var r: Dictionary = await f.activate(actor, self)
	check(r.rejected.is_empty() and "extract" in r.committed, "S7: a unit in the extraction zone extracts")
	await f.dispose(self)

func _extraction_handoff_waits_for_settlement() -> void:
	var f := Fixture.new()
	var mission := MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.EXTRACT, 1)
	await f.setup(self, 2, 1, 0, mission, AIDifficultyPolicy.Tier.EASY, [], true)
	var outgoing := f.turns.player_units[0]
	var successor := f.turns.player_units[1]
	var successor_id := String(successor.tactical_id)
	var exit := Vector3i(14, 0, 28)
	f.grid.map_data.set_objective_zone(&"extract", [exit])
	f.place(outgoing, exit)
	f.place(successor, Vector3i(5, 0, 28))
	f.place(f.turns.enemy_units[0], Vector3i(28, 0, 20))
	f.ready_actor(outgoing)
	f.ready_actor(successor)
	check(f.turns.select_player_unit(outgoing), "Handoff fixture selects the extracting actor")
	var service := f.battle.action_service
	var present := service._present_mission
	service._present_mission = func(result, actor, target):
		await release_extraction
		await present.call(result, actor, target)
	f.battle.debug_player_ai = true
	f.level.objective_manager.try_extract(outgoing)
	check(service.is_busy and f.turns.active_unit == successor and not f.turns.player_units.has(outgoing),
		"Authoritative extraction removes the actor and selects the successor before presentation settles")
	var extract_transaction := service.last_transaction_id
	await create_timer(AIController.ACTIVATION_PRESENTATION_DELAY_SECONDS + 0.3).timeout
	check(service.is_busy and service.last_transaction_id == extract_transaction and f.decisions.is_empty(),
		"The activated successor publishes no decision and commits nothing while the extraction window is held")
	release_extraction.emit()
	var deadline := Time.get_ticks_msec() + 4000
	while not f.outcomes.any(func(row: Dictionary) -> bool: return row.actor_id == successor_id) and Time.get_ticks_msec() < deadline:
		await process_frame
	var successor_outcomes := f.outcomes.filter(func(row: Dictionary) -> bool: return row.actor_id == successor_id)
	check(not successor_outcomes.is_empty() and successor_outcomes[0].stage == "committed" and successor_outcomes[0].action == "move",
		"The successor resumes once the action settles and makes a legal advance instead of submitting a busy Wait")
	await f.dispose(self)

## S7b extraction en route: the zone is a few cells away, no hostile is in range.
## Reasonable: move closer, legally; do not wander away or wait while AP and a route exist.
func _extraction_en_route() -> void:
	var f = await _extract_fixture()
	var actor: TacticalUnit = f.turns.player_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	var exit := Vector3i(14, 0, 28)
	var zone: Array[Vector3i] = [exit]
	f.grid.map_data.set_objective_zone(&"extract", zone)
	f.place(actor, Vector3i(5, 0, 28)); f.place(enemy, Vector3i(28, 0, 20))
	f.ready_actor(actor)
	var before := Vector3(actor.grid_position).distance_to(Vector3(exit))
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S7b")
	check(Vector3(r.end).distance_to(Vector3(exit)) < before or "extract" in r.committed, "S7b: the unit makes progress toward extraction")
	await f.dispose(self)

## S8 rescue: the escort-carrier stands next to the casualty with AP and no hostile in range.
## Reasonable: pick the casualty up (a mission action), then stop chasing hostiles.
func _rescue_pickup() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 1, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1), AIDifficultyPolicy.Tier.HARD, [], true)
	var carrier: TacticalUnit = f.turns.allied_units[0]
	var enemy: TacticalUnit = f.turns.enemy_units[0]
	var casualty := f.level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var exit := Vector3i(4, 0, 28)
	var zone: Array[Vector3i] = [exit]
	f.grid.map_data.set_objective_zone(&"extract", zone)
	var carrier_cell: Vector3i = f.free_cell_near(carrier, Vector3i(8, 0, 28))
	f.place(carrier, carrier_cell)
	f.place(casualty, f.free_cell_near(casualty, carrier_cell + Vector3i(1, 0, 0), 2))
	f.place(enemy, Vector3i(28, 0, 10))
	f.ready_actor(carrier)
	var r: Dictionary = await f.activate(carrier, self)
	hard_rules(f, carrier, r, "S8")
	check("rescue" in r.committed and (not r.present or carrier.is_carrying_unit()), "S8: the carrier picks up the casualty")
	check(not ("attack" in r.committed), "S8: a carrier does not spend AP shooting")
	await f.dispose(self)

## An escort is already in the only evacuation lane when a player picks up the VIP.
## With a recess the escort can yield. With the recess closed it cannot leave the exit.
func _carrier_corridor_recovery(has_recess: bool, has_alternate := false, crowded := false) -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1, 2 if crowded else 1, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 1))
	var carrier: TacticalUnit = f.turns.player_units[0]
	var escort: TacticalUnit = f.turns.allied_units[0]
	var casualty := f.level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var start := Vector3i(8, 0, 10)
	var exit := Vector3i(12, 0, 10)
	var alternate := start + Vector3i.LEFT * 2
	var recess := exit + Vector3i.BACK
	var second_block := exit + Vector3i.LEFT * 2
	var second_recess := second_block + Vector3i.BACK
	# Use the same swept-occupancy planner as the current sites on a controlled floor.
	f.grid.map_data.surface_placement_enabled = true
	f.grid.map_data.surface_points_resolved = true
	f.place(carrier, start)
	f.place(casualty, start + Vector3i.LEFT)
	f.place(escort, exit)
	if crowded:
		f.place(f.turns.allied_units[1], second_block)
	f.place(f.turns.enemy_units[0], Vector3i(22, 0, 10))
	var wall: Array[Vector3i] = []
	for cell: Vector3i in f.grid.map_data.cells:
		if cell.x in range(8, 14) and (cell.y != 0 or cell.z != start.z) and (not has_recess or cell != recess):
			if crowded and cell == second_recess:
				continue
			wall.append(cell)
	# Close the far end of the corridor so the exit occupant cannot just walk through it.
	wall.append(exit + Vector3i.RIGHT)
	f.set_walls(wall)
	f.battle.pathfinder.live_grid = f.grid
	f.grid.map_data.set_objective_zone(&"extract", [exit])
	f.ready_actor(carrier, 1)
	f.ready_actor(escort, 1)
	escort.stats.speed = 1
	var pickup := await f.activate(carrier, self)
	check("rescue" in pickup.committed and carrier.is_carrying_unit(), "Corridor: carrier legally picks up the casualty")
	check(not f.grid.can_unit_occupy_cell(carrier, exit), "Corridor: the occupied exit is really blocked")
	if has_alternate:
		f.grid.map_data.set_objective_zone(&"extract", [exit, alternate])
		# The blocked exit remains a mission option, but coordination should use the open one.
		check(f.battle.pathfinder.calculate_3d_path(start, alternate).size() > 1, "Corridor: the alternate exit is reachable")
	f.act_as(escort)
	check((recess in f.legal_moves(escort)) == has_recess, "Corridor: the recess is a legal move exactly when open")
	var yielded := await f.activate(escort, self)
	hard_rules(f, escort, yielded, "Corridor escort")
	if has_alternate:
		check(not yielded.decisions.any(func(row: Dictionary) -> bool: return "Yielded" in String(row.reason)),
			"Corridor: an open alternate exit does not require yielding")
	elif has_recess:
		check("move" in yielded.committed and yielded.end == recess and "Support" in yielded.actions,
			"Corridor: the escort leaves the occupied exit for its legal recess")
	else:
		check(not ("move" in yielded.committed) and yielded.end == exit,
			"Corridor: without a recess the escort cannot fabricate a yielding move")
	if crowded:
		check(f.battle.pathfinder.calculate_3d_path(start, exit).is_empty(),
			"Corridor: clearing one occupant does not remove the second blockage")
		var second: TacticalUnit = f.turns.allied_units[1]
		f.ready_actor(second, 1)
		second.stats.speed = 1
		var second_yield := await f.activate(second, self)
		hard_rules(f, second, second_yield, "Crowded corridor second escort")
		check("move" in second_yield.committed and second_yield.end == second_recess,
			"Corridor: the second escort clears another choke point using its own recess")
	f.ready_actor(carrier, 3)
	var attempted_exit := await f.activate(carrier, self)
	hard_rules(f, carrier, attempted_exit, "Corridor carrier")
	if has_recess:
		check("extract" in attempted_exit.committed, "Corridor: the carrier extracts after the escort yields")
	else:
		check(attempted_exit.end == start and not ("extract" in attempted_exit.committed),
			"Corridor: the blocked carrier cannot move through the escort or extract")
		f.ready_actor(escort, 1)
		var repeated := await f.activate(escort, self)
		check(repeated.end == exit and not ("move" in repeated.committed),
			"Corridor: a repeated activation does not move the blockage back and forth")
	await f.dispose(self)

## Use the real defeat and rescue lifecycle, then let the AI find the reopened objective.
func _carrier_handoff_after_defeat() -> void:
	var f := Fixture.new()
	await f.setup(self, 2, 1, 1, MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.RESCUE, 2), AIDifficultyPolicy.Tier.HARD, [], true)
	var first: TacticalUnit = f.turns.player_units[0]
	var replacement: TacticalUnit = f.turns.allied_units[0]
	var casualty := f.level.get_node("Units/ObjectiveUnits/RescueTarget") as TacticalUnit
	var start := Vector3i(8, 0, 28)
	f.place(first, start)
	f.place(casualty, start + Vector3i.LEFT)
	f.place(replacement, start + Vector3i.RIGHT)
	f.place(f.turns.enemy_units[0], Vector3i(28, 0, 20))
	f.grid.map_data.set_objective_zone(&"extract", [Vector3i(13, 0, 28)])
	f.ready_actor(first, 1)
	var pickup := await f.activate(first, self)
	check("rescue" in pickup.committed and first.is_carrying_unit(), "Handoff: first carrier secured the casualty")
	first.stats.take_damage(9999)
	await process_frame
	check(f.turns.battle_result == TurnManager.BattleResult.ONGOING, "Handoff: the squad has surviving players and the mission continues")
	f.ready_actor(replacement, 1)
	check(f.ai_of(replacement)._get_ai_mission_intent().kind == MissionIntent.Kind.RESCUE,
		"Handoff: the surviving escort reads the reopened rescue intent")
	var handoff := await f.activate(replacement, self)
	hard_rules(f, replacement, handoff, "Carrier handoff")
	check("rescue" in handoff.committed and replacement.is_carrying_unit(), "Handoff: the escort legally replaces the defeated handler")
	await f.dispose(self)

## S1b flanking: one hostile behind low cover facing the shooter, open ground to either side.
## Records the shot the AI takes against the best shot it could reach by moving first. Today the
## AI shoots from where it stands (Move -> Attack comparison is milestone 05 step 6), so this
## asserts legality and prints the gap instead of asserting a flank.
func _flank_opportunity() -> void:
	var f = await _duel(1)
	var actor: TacticalUnit = f.turns.player_units[0]
	var target: TacticalUnit = f.turns.enemy_units[0]
	f.place(actor, Vector3i(5, 0, 10)); f.place(target, Vector3i(11, 0, 10))
	f.set_cover(Vector3i(10, 0, 10), MapCellData.CoverType.LOW, 0.9)
	f.ready_actor(actor)
	var here: int = f.battle.query_attack(actor, target).hit_chance
	var best := here
	var best_cell: Vector3i = f.grid.get_unit_grid(actor)
	for cell in f.legal_moves(actor):
		var evaluation := CombatRules.evaluate_attack_from_cell(actor, cell, target, f.grid, actor.get_world_3d())
		if evaluation.is_legal and evaluation.hit_chance > best:
			best = evaluation.hit_chance
			best_cell = cell
	check(best > here, "S1b setup: a reachable flank gives a better shot than the frontal one")
	var r: Dictionary = await f.activate(actor, self)
	hard_rules(f, actor, r, "S1b")
	check("attack" in r.committed, "S1b: the unit shoots rather than idling")
	print("[Scenario] S1b frontal chance %d%%, best reachable chance %d%% at %s, AI moved: %s" % [here, best, best_cell, "move" in r.committed])
	await f.dispose(self)
