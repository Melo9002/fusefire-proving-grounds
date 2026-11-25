extends SceneTree
## F3 decision visualization (milestone 05): timeline, route arrow and target lines,
## squad reservations and score bars. Everything here is read-only: browsing must not
## change the committed state or create squad contexts.
## Rendered review (needs a display): -- capture <directory>
const Fixture := preload("res://tests/support/ai_scenario_fixture.gd")

var failures := 0
var checks := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _surface_vertices(mesh: Mesh) -> int:
	if mesh == null or mesh.get_surface_count() == 0: return 0
	return (mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()

func _run() -> void:
	Engine.time_scale = 12.0
	root.size = Vector2i(1280, 720)
	var f := Fixture.new()
	# The Tactical Test Range has surface placement, so the AI plans real movement here.
	await f.setup(self, 1, 2, 0, null, AIDifficultyPolicy.Tier.HARD, [], true)
	# Only this test's activations should act; enemies stay put between them.
	f.battle.set_debug_enemy_control(true)
	var tools := f.level.get_node("Visualizers/BattleUI/DebugTools") as DebugTools
	var actor: TacticalUnit = f.turns.player_units[0]
	var near: TacticalUnit = f.turns.enemy_units[0]
	var far: TacticalUnit = f.turns.enemy_units[1]

	# Phase 1: nothing in range, so the AI plans a move toward the far hostile (its own movement planning,
	# without ending the turn, so later decisions in this battle are not raced by turn transitions).
	f.place(actor, f.free_cell_near(actor, Vector3i(3, 0, 28)))
	f.place(near, f.free_cell_near(near, Vector3i(28, 0, 26)))
	f.place(far, f.free_cell_near(far, Vector3i(28, 0, 30)))
	f.ready_actor(actor)
	var move_run: Dictionary = await f.plan_move_toward(actor, far, self)
	check(move_run.moved and "move" in move_run.committed, "Setup: the AI plans and commits a move toward the far hostile")
	check(tools._timeline_list.item_count == 0, "The closed panel does not build hidden timeline items")
	tools.set_panel_open(true)
	check(not tools._decision_history.is_empty() and tools._timeline_list.item_count == tools._decision_history.size(), "The timeline lists every recorded decision")
	var selected_index := -1
	for index in tools._decision_history.size():
		if tools._decision_history[index].stage == "selected" and tools._decision_history[index].action == "Move": selected_index = index
	check(selected_index >= 0, "A selected-move decision was recorded")
	var committed_tags := 0
	for item in tools._timeline_list.item_count:
		if tools._timeline_list.get_item_text(item).contains("[committed]"): committed_tags += 1
	check(committed_tags > 0, "Timeline entries show their authoritative outcome")

	var revision: int = f.battle.action_service.state_revision
	var contexts: int = f.battle._squad_contexts.size()
	var rng = f.battle.action_service.get_combat_rng_state()
	var decision_rng := f.ai_of(actor)._decision_rng.state
	var ap := actor.stats.current_ap
	var sp := actor.stats.current_supply_points
	# The newest entry is at the top; map the history index back to its list item.
	var list_item := -1
	for item in tools._timeline_list.item_count:
		if int(tools._timeline_list.get_item_metadata(item)) == selected_index: list_item = item
	tools._select_timeline_entry(list_item)
	check(f.battle.action_service.state_revision == revision and f.battle._squad_contexts.size() == contexts and f.battle.action_service.get_combat_rng_state() == rng, "Browsing a decision changes no revision, RNG or squad context")
	check(f.ai_of(actor)._decision_rng.state == decision_rng and actor.stats.current_ap == ap and actor.stats.current_supply_points == sp,
		"Browsing changes no decision RNG, AP or SP")
	check(tools._ai_scoring_toggle.button_pressed, "Selecting a decision turns the scoring overlay on so its effect is visible")
	var overlay := tools._ai_scoring_overlay as AIScoringOverlay
	check(_surface_vertices(overlay._line_mesh.mesh) >= 9, "A move decision draws a route arrow (ribbon plus arrowhead)")
	check(_surface_vertices(overlay._position_mesh.mesh) > 0, "Selecting a decision redraws its movement heatmap")
	var detail: String = tools._timeline_details.text
	check(detail.contains("MOVES") and detail.contains("<- CHOSEN") and detail.contains("[#"), "Details show the chosen tile with component bars")
	check(detail.contains("Outcome: committed"), "Details show the committed outcome")
	check(detail.contains("Resources at commit: AP") and detail.contains(String(actor.tactical_id)), "The historical action displays the actor ID and committed resource changes")
	var stored_move: Dictionary = tools._decision_history[selected_index]
	var squad_before: Dictionary = stored_move.squad_at_decision.duplicate(true)
	f.battle.peek_squad_context(actor).reserve_destination(actor, actor.grid_position)
	check(stored_move.squad_at_decision == squad_before, "The historical squad snapshot stays independent of live reservations")
	tools.set_panel_open(false)
	await _shoot(f, tools, actor, "1-move-arrow-and-heatmap", false)

	# Phase 2: hostiles in range, so the AI shoots and lists the targets it considered.
	f.place(actor, f.free_cell_near(actor, Vector3i(5, 0, 28)))
	f.place(near, f.free_cell_near(near, Vector3i(10, 0, 26)))
	f.place(far, f.free_cell_near(far, Vector3i(10, 0, 30)))
	f.ready_actor(actor)
	var attack_run: Dictionary = await f.activate(actor, self)
	check("attack" in attack_run.committed, "Setup: the second activation shoots (did %s)" % str(attack_run.actions))
	tools.set_panel_open(true)
	var attack_index := -1
	for index in tools._decision_history.size():
		if tools._decision_history[index].action == "Attack": attack_index = index
	check(attack_index >= 0, "An attack decision was recorded")
	for item in tools._timeline_list.item_count:
		if int(tools._timeline_list.get_item_metadata(item)) == attack_index: list_item = item
	tools._select_timeline_entry(list_item)
	check(_surface_vertices(overlay._line_mesh.mesh) >= 6, "An attack decision draws lines to the targets it considered")
	check(tools._timeline_details.text.contains("TARGETS") and tools._timeline_details.text.contains("<- CHOSEN"), "Details list the targets with the chosen one marked")
	check(not tools._timeline_details.text.contains("LAST MOVEMENT EVALUATION"), "A shot details its own candidates without an old movement evaluation")
	var attack_record: Dictionary = tools._decision_history[attack_index]
	var receipt: Dictionary = tools._decision_outcome(attack_record)
	check(receipt.get("committed_revision") == attack_record.state_revision and receipt.get("actor_id") == attack_record.actor_id and receipt.get("action") == "attack",
		"The attack explanation links to the actual authoritatively committed attack")
	check(tools._latest_ai_outcome.get("decision_id") == attack_record.decision_id, "The AI tab can link its latest outcome to the same historical decision")
	tools.set_panel_open(false)
	await _shoot(f, tools, actor, "2-target-lines", false)
	await _shoot(f, tools, actor, "3-timeline-details", true)
	tools.set_panel_open(true)
	check(tools._timeline_list.is_selected(list_item) and tools._timeline_details.text.contains("TARGETS"),
		"Reopening F3 keeps the historical row and its details together")
	tools.set_panel_open(false)
	print("F3 serialized history: %d bytes across %d real decisions" % [var_to_bytes(tools._decision_history).size(), tools._decision_history.size()])

	# Squad reservations: draw what the squad context holds, without creating one.
	var context := f.battle.get_squad_context(actor)
	contexts = f.battle._squad_contexts.size()
	var reserved := f.free_cell_near(actor, Vector3i(7, 0, 27))
	context.reserve_destination(actor, reserved)
	context.reserve_corridor(actor, {reserved + Vector3i.RIGHT: true})
	context.reserve_target(actor, near)
	tools._set_ai_reservations_visible(true)
	var reservations := tools._ai_reservation_overlay as AIReservationOverlay
	check(reservations.entry_count("destination") == 1 and reservations.entry_count("corridor") == 1 and reservations.entry_count("target") == 1, "Reservations show the destination, corridor and focus target")
	check(_surface_vertices(reservations._mesh.mesh) > 0, "Reservations are drawn")
	await _shoot(f, tools, actor, "4-reservations", false)
	tools._set_ai_reservations_visible(false)
	check(reservations._mesh.mesh == null, "Hiding reservations clears the overlay")
	check(f.battle._squad_contexts.size() == contexts, "Drawing reservations creates no squad context")

	# The timeline is bounded.
	for index in 100:
		tools._on_ai_decision_recorded({"decision_id": 1000 + index, "actor": "Probe", "action": "Wait", "subject": "", "stage": "explanation"})
	var oversized: Array[Dictionary] = []
	for index in 160:
		oversized.append({"cell": Vector3i(index, 0, 0), "score": float(index), "chosen": index == 0})
	tools._on_ai_decision_recorded({"decision_id": 1100, "actor": "Probe", "action": "Move", "position_candidates": oversized})
	check(tools._latest_ai_decision.position_candidates.size() == tools.HISTORY_MOVE_LIMIT and tools._latest_ai_decision.position_candidates[0].chosen and oversized.size() == 160,
		"F3 keeps the chosen cell within its budget and leaves the published candidates intact")
	tools._on_ai_action_outcome({"decision_id": 1000, "actor_id": "Probe", "action": "wait", "stage": "rejected"})
	check(not tools._decision_outcomes.has(1000), "Late outcomes for evicted decisions do not accumulate")
	tools.set_panel_open(true)
	check(tools._decision_history.size() == tools.DECISION_HISTORY_LIMIT and tools._timeline_list.item_count == tools.DECISION_HISTORY_LIMIT, "The timeline keeps a bounded history")

	# Bars are deterministic and shared-scale.
	check(DebugTools.score_bar(10.0, 10.0, 6) == "[######]" and DebugTools.score_bar(-5.0, 10.0, 6) == "[---...]" and DebugTools.score_bar(0.0, 10.0, 6) == "[......]", "Score bars scale and mark penalties")

	# The panel still fits a 720p window with the new tab, and browsing is read-only.
	tools.set_panel_open(true)
	for child in tools._tabs.get_children():
		if child.name == "Timeline": tools._tabs.current_tab = child.get_index()
	await process_frame
	await process_frame
	check(Rect2(Vector2.ZERO, tools.get_viewport_rect().size).encloses(tools._panel.get_rect()), "The Timeline tab fits 1280x720")
	tools.set_panel_open(false)
	await f.dispose(self)
	Engine.time_scale = 1.0
	print("AI decision visualization: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)

## Rendered review only (needs a display): a camera framed on the acting unit, with or without the panel.
func _shoot(f, tools: DebugTools, actor: TacticalUnit, name: String, with_panel: bool) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless":
		return
	var camera := Camera3D.new()
	f.level.add_child(camera)
	var focus: Vector3 = actor.global_position + Vector3(3.0, 0.0, 0.0)
	camera.position = focus + Vector3(5.0, 8.5, 6.5)
	camera.look_at(focus)
	camera.make_current()
	tools.set_panel_open(with_panel)
	if with_panel:
		for child in tools._tabs.get_children():
			if child.name == "Timeline": tools._tabs.current_tab = child.get_index()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(args[1])
	check(root.get_texture().get_image().save_png(args[1].path_join(name + ".png")) == OK, "Capture " + name)
	tools.set_panel_open(false)
	camera.queue_free()
