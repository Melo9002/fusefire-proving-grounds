extends "res://tests/generation_2_replay_edited_map_test.gd"
class Editor extends "res://tools/map_editor.gd":
	func _ready(): pass
var fixture := preload("res://tests/fixtures/plot_test_library.gd").new()
func operation() -> EnvironmentResolutionContext: return fixture.operation()
func plot(name: String, mission := "eliminate") -> EnvironmentPlotSource:
	var source: EnvironmentPlotSource = EnvironmentPlotSource.load_file("res://content/plots/"+name+".json").source
	for street in source.data.fixed_streets: street.revision = fixture.revisions[street.chunk_id]
	source.data.active_mission = mission
	return source
func configuration(document: BattlefieldLayoutDocument, terminal := false) -> BattleConfiguration:
	var config := _configuration()
	config.battlefield_preset = BattleConfiguration.BattlefieldPreset.AUTHORED_PLOT
	config.map_size = document.map_size()
	config.battle_seed = int(document.provenance.generation_seed)
	config.mission = MissionCatalog.create_mission(MissionObjectiveDefinition.Kind.INTERACT_TERMINAL if terminal else MissionObjectiveDefinition.Kind.ELIMINATE,config.enemy_count,false)
	return config
func _run() -> void:
	var previous := Engine.time_scale
	Engine.time_scale = 24.0
	if not fixture.create("res://artifacts/t11-fixture-"+str(Time.get_ticks_usec())): check(false,"fixture registration"); _finish(previous); return
	GenerationJsonStore.write("res://artifacts/t11-fixture-location.json",JSON.stringify({"directory":fixture.directory,"revisions":fixture.revisions}))
	var result := AuthoredPlotComposer.compose(plot("through_street_industrial"),17,operation())
	check(result.ok,"plot composes for gameplay")
	if not result.ok: print(result); _finish(previous); return
	var config := configuration(result.document)
	check(BattlefieldRuntimePreparation.compile_document(result.document,config,1.0,operation()).ok,"common document preparation")
	check(not BattlefieldRuntimePreparation.compile_document(result.document,configuration(result.document,true),1.0,operation()).ok,"wrong active mission rejects")
	check(not BattlefieldRuntimePreparation.compile_document(null,config,1.0,operation()).ok,"missing plot never falls back to industrial generation")
	var path := fixture.directory.path_join("edited.layout.json")
	check(MapEditorLayoutStore.save(result.document,path,operation()).is_empty(),"save accepted plot")
	var loaded := MapEditorLayoutStore.load({},path,&"",operation())
	check(loaded.ok and ChunkPublicationCompiler.canonical(loaded.document.to_dictionary()) == ChunkPublicationCompiler.canonical(result.document.to_dictionary()),"exact saved choices round trip")
	if loaded.ok:
		var edited := await boundary_checks(config,loaded.document,path)
		await exercise(config,edited)
	var terminal := AuthoredPlotComposer.compose(plot("yard_service_access","terminal"),42,operation())
	check(terminal.ok,"Terminal plot composes")
	if terminal.ok: await exercise(configuration(terminal.document,true),terminal.document,true)
	print("T11 runtime failures: ",failures)
	_finish(previous)
func exercise(config: BattleConfiguration, document: BattlefieldLayoutDocument, terminal := false) -> void:
	ReplaySession.last_recording = null
	var original := await _start_document_battle(config,document)
	if original == null: return
	original.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	if terminal:
		await drive_terminal(original)
	else:
		original.battle_controller.set_debug_player_ai(true)
		await _wait_for_battle(original,120.0)
	check(original.turn_manager.battle_result == TurnManager.BattleResult.VICTORY,"natural mission completes successfully; Terminal=%s" % terminal)
	var recording: BattleReplayRecording = ReplaySession.last_recording
	check(recording != null and not recording.actions.is_empty(),"plot battle records actions")
	original.queue_free(); await process_frame; await process_frame
	if recording == null: return
	var persisted := BattleReplayRecording.from_dictionary(recording.to_dictionary(),operation())
	check(persisted.is_playable(operation()),"plot replay validates exact content")
	var replay := await _start_replay(persisted)
	if replay == null: return
	var player := replay.get_node("BattleReplayPlayer") as BattleReplayPlayer
	player.action_delay = 0.001; player.continuous_actor_delay = 0.001; player.set_playback_speed(4.0)
	await _wait_for_replay(player,120.0)
	check(player.playback_succeeded and player.verified_actions == persisted.actions.size(),"plot replay verifies every action: %d/%d" % [player.verified_actions,persisted.actions.size()])
	replay.queue_free(); await process_frame
func _start_document_battle(config: BattleConfiguration, document: BattlefieldLayoutDocument) -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.preparation_context = operation()
	level.configure_layout_document(config, document)
	var completed: Array = []
	level.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors.duplicate(true)}), CONNECT_ONE_SHOT)
	root.add_child(level)
	await _wait_for_initialization(completed)
	var ok: bool = not completed.is_empty() and bool(completed[0].success)
	check(ok, "saved edited document initializes a normal battle: %s" % str(completed[0].errors if not completed.is_empty() else "timeout"))
	if ok: return level
	level.queue_free()
	await process_frame
	return null

func _start_replay(recording: BattleReplayRecording) -> BattleLevel:
	var level := BATTLE_SCENE.instantiate() as BattleLevel
	level.preparation_context = operation()
	level.configure_replay(recording)
	var completed: Array = []
	level.battle_initialization_finished.connect(func(success: bool, errors: Array): completed.append({"success": success, "errors": errors.duplicate(true)}), CONNECT_ONE_SHOT)
	root.add_child(level)
	await _wait_for_initialization(completed)
	var ok: bool = not completed.is_empty() and bool(completed[0].success)
	check(ok, "replay initializes through document validation and tactical compilation: %s" % str(completed[0].errors if not completed.is_empty() else "timeout"))
	if ok: return level
	level.queue_free()
	await process_frame
	return null


func drive_terminal(level: BattleLevel) -> void:
	# Uses public action queries and submissions. No teleports, AP/HP edits or skipped enemy turns.
	var controller := level.battle_controller
	var manager := level.turn_manager
	var target := level.objective_manager.get_terminal_state(&"main_terminal").definition.grid_position
	var deadline := Time.get_ticks_msec()+120000
	while manager.battle_result == TurnManager.BattleResult.ONGOING and Time.get_ticks_msec() < deadline:
		await process_frame
		if manager.current_phase != TurnManager.TurnPhase.PLAYER_TURN or controller.action_service.is_busy: continue
		var actor := manager.active_unit
		if not is_instance_valid(actor): manager.end_current_turn(); continue
		if controller.query_terminal(actor,&"main_terminal").is_legal():
			await controller.try_terminal(actor,&"main_terminal"); continue
		var query := controller.query_move(actor)
		var start := controller.grid_manager.get_unit_grid(actor)
		var best := Vector3i(-1,-1,-1)
		var shortest := INF
		for direction in [Vector3i.LEFT,Vector3i.RIGHT,Vector3i.FORWARD,Vector3i.BACK]:
			var destination: Vector3i = target+direction
			var path := controller.pathfinder.calculate_3d_path(start,destination)
			if path.is_empty() or path.size() >= shortest: continue
			var candidate := Vector3i(-1,-1,-1)
			for point in path:
				var cell := controller.world_to_grid(point)
				if cell != start and query.legal_destination_cells.has(cell): candidate = cell
			if candidate != Vector3i(-1,-1,-1): shortest = path.size(); best = candidate
		if best != Vector3i(-1,-1,-1) and query.is_legal():
			await controller.try_move(actor,best)
		else: manager.end_current_turn()

func boundary_checks(config: BattleConfiguration, document: BattlefieldLayoutDocument, path: String) -> BattlefieldLayoutDocument:
	var played := document
	var rejected := BATTLE_SCENE.instantiate() as BattleLevel
	rejected.preparation_context = operation()
	rejected.configure_layout_document(configuration(document,true),document)
	root.add_child(rejected)
	await process_frame
	check(not rejected.battle_initialization_succeeded and rejected.active_generated_map == null and rejected.get_node_or_null("GeneratedTerrain") == null and rejected.turn_manager.player_units.is_empty(),"mission rejection leaves no partially activated battlefield")
	rejected.queue_free(); await process_frame
	var editor := Editor.new(); editor.layout_preset = &"plot_authoring"; root.add_child(editor); editor._build_ui()
	var ui: PlotAuthoringController = editor.plot_authoring
	ui.load_composed(path,operation())
	check(ui.composed.get("ok",false),"editor opens exact accepted battlefield")
	var before := ui.signature()
	var accepted: BattlefieldLayoutDocument = ui.composed.get("document")
	GenerationJsonStore.write(fixture.directory.path_join("broken.json"),"{}")
	ui.load_composed(fixture.directory.path_join("broken.json"),operation())
	check(ui.signature() == before and ui.composed.get("document") == accepted,"rejected saved-map load preserves source and preview")
	ui.changed()
	ui.selected_group = "slots"; ui.selected_id = ui.source.data.slots[0].id; ui.build_form()
	ui.fields.Width.value += 1
	ui.apply_fields()
	check(ui.signature() != before,"owner can edit reopened plot slot through normal editor controls")
	var edited := AuthoredPlotComposer.compose(ui.source,config.battle_seed,operation())
	check(edited.ok,"edited slot composes without stretching chunk content")
	if edited.ok:
		var before_choices: Array = document.provenance.composition.choices.duplicate(true)
		var after_choices: Array = edited.document.provenance.composition.choices.duplicate(true)
		before_choices.sort_custom(func(a,b): return a.id < b.id)
		after_choices.sort_custom(func(a,b): return a.id < b.id)
		check(ChunkPublicationCompiler.canonical(before_choices) == ChunkPublicationCompiler.canonical(after_choices),"enlarging a slot retains exact chunk revisions/transforms independent of search ordering")
		var edited_path := fixture.directory.path_join("owner-edited.json")
		check(MapEditorLayoutStore.save(edited.document,edited_path,operation()).is_empty(),"owner-edited composition saves")
		var reopened := MapEditorLayoutStore.load({},edited_path,&"",operation())
		check(reopened.ok,"owner-edited composition reopens for gameplay")
		if reopened.ok: played = reopened.document
	ui.undo(); check(ui.signature() == before,"undo restores reopened source")
	# Authored plans legitimately omit some diagnostic groups; no empty surfaces.
	if edited.ok: editor._add_spatial_plan_overlay(editor.content,edited.data)
	check(editor.content.get_node_or_null("SpatialPlan") != null,"sparse plot diagnostic overlay renders")
	editor.free()
	return played
