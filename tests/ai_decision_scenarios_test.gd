extends SceneTree
## Milestone 05 step 3: controlled AI decision scenarios.
## Each scenario fixes a setup, lists the legal options from the shared queries, and
## states what a reasonable decision looks like. Hard rules (legality, resources,
## explanation) are asserted for every scenario. Preferences are asserted as properties
## ("the chosen target is no worse than the best legal one"), never as one exact tile.
## Behavior the AI does not have yet is documented in docs/claude/ai-scenarios-2026-11-18.md
## instead of being asserted here.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

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
	await _flat_map_approach()
	await _reposition_for_a_better_shot()
	await _good_shot_is_kept()
	await _reposition_needs_ap_to_fire()
	await _reposition_is_deterministic()
	await _easy_does_not_reposition()
	await _shield_when_stuck_under_fire()
	await _no_shield_without_a_threat()
	await _shield_over_last_shot()
	await _shot_over_shield_for_a_kill()
	await _extraction_in_zone()
	await _extraction_en_route()
	await _rescue_pickup()
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
