extends SceneTree
## Milestone 05 step 4: typed decision records and the planning snapshot.
## The records must publish exactly the trace keys F3, the simulator and tests already read.
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")
const ActivationProfile := preload("res://systems/ai/ai_activation_profile.gd")

var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func keys_of(record: Dictionary) -> Array:
	var keys := record.keys()
	keys.sort()
	return keys

func _run() -> void:
	_position_candidates()
	_target_candidates()
	_decision_record()
	_activation_timing()
	_activation_handoff()
	await _planning_snapshot()
	print("AI decision records: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

func _position_candidates() -> void:
	var considered := AIPositionCandidate.considered(Vector3i(3, 0, 4), 12.5, "progress +12", {"progress": 12.0, "cover": 0.0})
	check(keys_of(considered.to_dictionary()) == ["cell", "cover", "progress", "score", "status", "summary"], "Considered position keeps cell/score/status/summary plus components, and no chosen key before selection")
	considered.mark_chosen(true)
	check(considered.to_dictionary().chosen == true, "Chosen is published once the selection is made")
	considered.mark_chosen(false)
	check(considered.to_dictionary().has("chosen") and considered.to_dictionary().chosen == false, "An unchosen candidate still reports chosen = false")
	considered.reject("Below threshold")
	var rejected := considered.to_dictionary()
	check(rejected.status == "rejected" and rejected.reason == "Below threshold" and rejected.has("score") and rejected.has("progress"), "A scored candidate rejected afterward keeps its score and components")
	var early := AIPositionCandidate.rejected_before_scoring(Vector3i(1, 0, 1), "Outside useful route")
	check(keys_of(early.to_dictionary()) == ["cell", "reason", "status"] and early.is_rejected(), "A candidate rejected before scoring has no score or summary")
	var snapshot := considered.to_dictionary()
	considered.score = 99.0
	check(snapshot.score == 12.5, "A published dictionary is a snapshot, not a live view of the record")

func _target_candidates() -> void:
	var components := {"vulnerability": 1.0, "focus": 0.0, "vip": 0.0, "threat": 2.0, "mission": 0.0, "focus_count": 0, "damage_value": 12.5, "damage_on_hit": 25}
	var considered := AITargetCandidate.considered("EnemyUnit1", Vector3i(9, 0, 4), 33.0, "damage +12.5", 50, 12.5, components)
	check(keys_of(considered.to_dictionary()) == ["cell", "damage_on_hit", "damage_value", "expected_damage", "focus", "focus_count", "hit_chance", "mission", "score", "status", "summary", "target", "threat", "vip", "vulnerability"], "Considered target keeps every established key")
	considered.mark_chosen(true)
	check(considered.to_dictionary().chosen == true and considered.to_dictionary().target == "EnemyUnit1", "Chosen target is published")
	var rejected := AITargetCandidate.rejected("EnemyUnit2", Vector3i(2, 0, 2), "Out of range", "out_of_range")
	check(keys_of(rejected.to_dictionary()) == ["cell", "code", "reason", "status", "target"] and rejected.is_rejected(), "Rejected target carries its reason and validation code only")

func _decision_record() -> void:
	var record := AIDecisionRecord.new()
	record.action = "Move"
	record.subject = "(5, 0, 5)"
	record.position_candidates = [AIPositionCandidate.considered(Vector3i(5, 0, 5), 4.0, "x")]
	record.target_candidates = [AITargetCandidate.rejected("EnemyUnit1", Vector3i(9, 0, 9), "Blocked", "blocked")]
	var base := keys_of(record.to_dictionary())
	check("commander_policy" not in base, "Commander fields are absent until the battle supplies them")
	record.has_commander = true
	record.commander_policy = "Default"
	record.commander_policy_id = "default"
	record.strategic_intent = "Balanced engagement"
	var full := record.to_dictionary()
	for key in ["actor", "decision_id", "state_revision", "stage", "action", "subject", "reason", "alternatives", "mission_goal", "squad_adjustments", "movement_profile", "position_scores", "target_scores", "position_candidates", "target_candidates", "difficulty", "commander_policy", "commander_policy_id", "strategic_intent"]:
		check(full.has(key), "Decision record publishes %s" % key)
	for key in ["commander_composition", "attack_plan", "grid_position", "remaining_ap", "recent_move_origins", "consecutive_low_value_actions", "hold_score", "move_acceptance_threshold", "urgency_bonus", "route_corridor"]:
		check(full.has(key), "Decision context publishes %s" % key)
	check(full.stage == "explanation" and not record.is_selected_move(), "Records default to the explanation stage")
	record.stage = AIDecisionRecord.STAGE_SELECTED
	check(record.is_selected_move() and record.to_dictionary().stage == "selected", "A selected Move is recognized and published as such")
	record.action = "Attack"
	check(not record.is_selected_move(), "Only a selected Move is an early movement preview")
	check(full.position_candidates[0] is Dictionary and full.target_candidates[0] is Dictionary, "Candidates are published as plain dictionaries")

func _activation_timing() -> void:
	var profile := ActivationProfile.new(&"timed_actor", 1000)
	profile.suspend(1000)
	profile.resume("presentation", 1100)
	profile.note("move_inventory", 50, 12)
	profile.suspend(1150)
	profile.resume("yield", 1300)
	profile.note("position_scoring", 50, 4)
	profile.begin_action(1350)
	profile.note_commit(&"move", 17, 25, 10)
	profile.end_action(2100)
	var activation := profile.finish(2200)
	var decision: Dictionary = activation.decisions[0]
	check(decision.work_us == 100 and decision.max_slice_us == 50 and decision.wall_us == 250,
		"Planning work, wall latency and the longest work slice are measured independently")
	check(decision.yields == 1 and decision.yield_us == 150 and activation.delay_us == 100,
		"Planning yield and activation presentation delay are separate")
	check(decision.transaction == 17 and decision.core_us == 25 and decision.observers_us == 10 and decision.action_window_us == 750,
		"The planning sample carries the committed action's transaction and separate execution window")
	check(decision.counts.move_inventory == 12 and decision.counts.position_scoring == 4 and activation.tail.work_us == 100,
		"Candidate counts and activation tail are retained outside the action window")
	check(activation.activation_us == decision.wall_us + activation.tail.wall_us + activation.delay_us + activation.action_windows_us,
		"The sampled activation accounts for the measured intervals")

func _activation_handoff() -> void:
	var service := TacticalActionService.new()
	var outgoing := ActivationProfile.new(&"extracting")
	var incoming := ActivationProfile.new(&"next")
	service.ai_activation_profile = outgoing
	service._set_busy(true, &"extracting")
	service.ai_activation_profile = incoming
	service._set_busy(false)
	check(outgoing.decisions.size() == 1 and incoming.decisions.is_empty(),
		"An action window settles on its original activation after a successor starts")
	service._set_busy(true, &"unrelated")
	service._set_busy(false)
	check(incoming.decisions.is_empty(), "An unrelated action is not charged to the active planner")
	service.free()

func _planning_snapshot() -> void:
	var f := Fixture.new()
	await f.setup(self, 1, 1)
	var actor: TacticalUnit = f.turns.player_units[0]
	f.place(actor, Vector3i(5, 0, 10))
	var snapshot := AIPlanningSnapshot.capture(f.battle)
	check(not snapshot.is_stale(f.battle), "A fresh snapshot is not stale")
	f.place(actor, Vector3i(6, 0, 10))
	check(snapshot.is_stale(f.battle), "Moving a unit makes the snapshot stale")
	snapshot = AIPlanningSnapshot.capture(f.battle)
	check(not snapshot.is_stale(f.battle), "A new snapshot matches the new layout")
	f.battle.action_service.advance_external_revision()
	check(snapshot.is_stale(f.battle), "A committed state revision makes the snapshot stale")
	# A controller used outside the scene tree (an adapter) still records while its battle lives.
	var ai := f.ai_of(actor)
	var adapter := AIController.new()
	adapter.unit = actor
	adapter.turn_manager = f.turns
	adapter.battle_controller = f.battle
	adapter.current_mission_intent = ai._get_ai_mission_intent()
	var published: Array[Dictionary] = []  # lambdas capture by value, so collect through an array
	f.battle.ai_decision_recorded.connect(func(record: Dictionary): published.append(record))
	adapter._record_ai_decision("Wait", "x", "adapter", "None")
	check(published.size() == 1, "A controller outside the scene tree still records while its battle is alive")
	# Work resumed after the battle is gone must be discarded: nothing recorded, no turn ended, no error.
	f.level.queue_free()
	await process_frame
	await process_frame
	adapter._record_ai_decision("Wait", "x", "after the battle went away", "None")
	adapter._publish_movement_preview(Vector3i(1, 0, 1), "stale preview")
	var ended: bool = await adapter._wait_for_next_turn("stale wait", "None")
	check(published.size() == 1 and not ended, "After the battle is freed a controller records and ends nothing")
	adapter.free()
