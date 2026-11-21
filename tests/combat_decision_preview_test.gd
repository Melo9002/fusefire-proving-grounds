extends SceneTree
## UI-only consequences: pure destination facts, safe modal actions and preferences.
const BattleScene := preload("res://levels/prototype_map/prototype_map.tscn")
var checks := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _capture(name: String, level: BattleLevel) -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] != "capture" or DisplayServer.get_name() == "headless": return
	root.size = Vector2i(1440, 900)
	var rig := level.get_node("CameraRig") as TacticalCamera
	rig.set_process(false)
	rig._cancel_selection_focus()
	var actor := level.turn_manager.player_units[0]
	var focus := actor.global_position + Vector3(0, 0, 4)
	rig.camera.global_position = focus + Vector3(12, 14, 7)
	rig.camera.look_at(focus)
	await process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(args[1])
	check(root.get_texture().get_image().save_png(args[1].path_join(name + ".png")) == OK, "Captured decision UI: " + name)

func _run() -> void:
	root.gui_embed_subwindows = true
	var old_preferences := [BattleUXSettings.storage_path, BattleUXSettings.loaded, BattleUXSettings.confirm_actions, BattleUXSettings.confirm_movement]
	BattleUXSettings.storage_path = "res://.godot/decision-preview-%d.cfg" % OS.get_process_id()
	BattleUXSettings.loaded = true
	BattleUXSettings.confirm_actions = true
	BattleUXSettings.confirm_movement = false
	for sample in [[100, "Guaranteed"], [99, "Favorable, can miss"], [95, "Favorable, can miss"], [70, "Favorable, can miss"], [69, "Risky"], [40, "Risky"], [39, "Poor"], [0, "Poor"]]:
		check(TacticalFeedbackText.chance_label(sample[0]) == sample[1], "Chance band %s is honest: %s" % [sample[0], sample[1]])
	check(TacticalFeedbackText.chance_label(100, false) == "Unavailable" and TacticalFeedbackText.chance_color(100, false) != TacticalFeedbackText.chance_color(100), "Illegal actions never look guaranteed")
	var config := BattleConfiguration.new()
	config.generated_map = true
	config.select_battlefield(BattlefieldCatalog.TACTICAL_TEST_RANGE)
	config.player_count = 1
	config.enemy_count = 1
	config.player_archetypes = [&"shieldbearer"]
	config.content_manifest = {"population_enabled": false}
	var level := BattleScene.instantiate() as BattleLevel
	level.configure_battle(config)
	root.add_child(level)
	check(level.battle_initialization_succeeded, "Real range initializes")
	if not level.battle_initialization_succeeded:
		level.free()
		quit(1)
		return
	level.action_camera_director.frequency = ActionCameraDirector.Frequency.OFF
	var battle := level.battle_controller
	battle.set_process(false)
	var grid := battle.grid_manager
	var actor := level.turn_manager.player_units[0]
	var enemy := level.turn_manager.enemy_units[0]
	for pair in [[actor, Vector3i(1, 0, 16)], [enemy, Vector3i(1, 0, 26)]]:
		var unit: TacticalUnit = pair[0]
		grid.update_unit_position(unit, unit.grid_position, pair[1])
		unit.global_position = grid.grid_to_world(pair[1]) + Vector3.UP * unit.standing_height
	actor.attack_range = 10
	enemy.attack_range = 10
	var service := battle.action_service
	var hud := level.get_node("Visualizers/BattleUI/ActionHUDController") as ActionHUDController
	var pause_menu := level.get_node("Visualizers/BattleUI/BattlePauseMenu") as BattlePauseMenu
	var camera := level.get_node("CameraRig") as TacticalCamera
	var rng_before := service.get_combat_rng_state()
	var revision_before := service.state_revision
	await battle.confirm_player_action(&"aim", actor)
	check(paused and battle.action_confirmation.visible and actor.stats.current_ap == 3, "Aim confirmation pauses before spending AP")
	check(not camera.can_process() and battle.action_confirmation.get_cancel_button().custom_minimum_size.x >= 170, "Modal freezes camera and exposes a large Cancel button (camera=%s, cancel=%s)" % [camera.can_process(), battle.action_confirmation.get_cancel_button().custom_minimum_size])
	await _capture("aim-confirmation", level)
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	pause_menu._unhandled_key_input(escape)
	check(not pause_menu.is_open and paused, "Pause menu does not stack over an active confirmation")
	battle.action_confirmation.canceled.emit()
	check(not paused and actor.stats.current_ap == 3 and not actor.tactical_state.is_aiming and rng_before == service.get_combat_rng_state(), "Cancel resumes planning with no AP, stance or RNG changes")
	await battle.confirm_player_action(&"aim", actor)
	battle.action_confirmation.confirmed.emit()
	battle.action_confirmation.confirmed.emit()
	for _frame in 90:
		if not service.is_busy: break
		await process_frame
	check(actor.stats.current_ap == 2 and actor.tactical_state.is_aiming and service.state_revision == revision_before + 1, "Confirmation commits exactly once, even if Confirm is emitted twice")
	await battle.confirm_player_action(&"attack", actor, enemy)
	check(paused and battle.action_confirmation.dialog_text.contains("65% hit") and battle.action_confirmation.dialog_text.contains("Damage on hit: 25"), "Attack confirmation includes the same chance and fixed damage breakdown")
	battle.action_confirmation.canceled.emit()
	var shot := battle.query_attack(actor, enemy)
	battle._set_tactical_preview(TacticalFeedbackText.shot(shot), TacticalFeedbackText.chance_color(shot.hit_chance))
	check(hud._preview_label.get_theme_color("font_color") == TacticalFeedbackText.chance_color(65), "HUD chance tint uses the same band as the firing line")
	await _capture("shot-risky", level)
	var spent_before := actor.stats.spent_ap
	actor.stats.spent_ap = actor.stats.activation_capacity_ap
	var unavailable := battle.query_attack(actor, enemy)
	battle.shot_trajectory_visualizer.draw_trajectory(CombatRules.get_shot_origin(actor, grid), unavailable.aim_point, unavailable.evaluation, true, unavailable.is_legal())
	var neutral := TacticalFeedbackText.chance_color(100, false)
	neutral.a = 0.75
	check(not unavailable.is_legal() and battle.shot_trajectory_visualizer.mesh_instance.material_override.albedo_color.is_equal_approx(neutral), "A geometric firing lane with no AP is neutral, never colored as an available shot (legal=%s, actual=%s, expected=%s)" % [unavailable.is_legal(), battle.shot_trajectory_visualizer.mesh_instance.material_override.albedo_color, neutral])
	actor.stats.spent_ap = spent_before
	await battle.confirm_player_action(&"shield", actor, enemy)
	check(paused and battle.action_confirmation.dialog_text.contains("Fixed 120°"), "Shield confirmation explains its fixed direction and cost")
	battle.action_confirmation.canceled.emit()
	await battle.confirm_player_action(&"wait", actor)
	service.advance_external_revision()
	battle.action_confirmation.confirmed.emit()
	check(actor.stats.current_ap == 2 and battle._last_tactical_preview.contains("state changed"), "A stale confirmation cannot execute an action against changed state")
	await battle.confirm_player_end_turn()
	check(paused and battle.action_confirmation.dialog_text.contains("2 AP"), "Ending a phase with unused AP asks for confirmation")
	battle.action_confirmation.canceled.emit()
	check(level.turn_manager.current_phase == TurnManager.TurnPhase.PLAYER_TURN, "Canceling End Turn keeps the phase")
	var destination := Vector3i(1, 0, 18)
	var move := battle.query_move(actor, destination)
	check(move.is_legal() and move.actor_ap_after == 1, "Real proposed move preserves an AP to shoot")
	var fingerprint := BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager)
	var options := TacticalFeedbackText.movement_options(move, actor, [enemy], grid)
	check(options.size() == 1 and options[0].outgoing.hit_chance == 83 and options[0].damage == 25 and options[0].incoming.hit_chance == 83, "Both directions use real destination geometry; outgoing Aim is canceled")
	enemy.tactical_state.establish_aim()
	check(TacticalFeedbackText.movement_options(move, actor, [enemy], grid)[0].incoming.hit_chance == 100, "Incoming current-state preview includes the enemy's active Aim")
	enemy.tactical_state.clear_aim()
	enemy.shield_capability = preload("res://units/capabilities/physical_shield.tres")
	enemy.tactical_state.establish_shield(Vector2.RIGHT)
	check(TacticalFeedbackText.movement_options(move, actor, [enemy], grid)[0].incoming_unavailable == "Shield prevents Attack", "Incoming preview distinguishes current Shield action restrictions from geometry")
	enemy.tactical_state.clear_shield()
	enemy.shield_capability = null
	battle.is_move_mode_active = true
	battle.current_movement_zone.assign([destination])
	battle._update_movement_preview({"position": grid.grid_to_world(destination)})
	check(battle.movement_ghost != null and battle.movement_ghost.destination.is_equal_approx(grid.grid_to_world(destination)), "Ghost uses the exact supported destination")
	check(not battle.movement_ghost.model.find_children("*", "MeshInstance3D", true, false).is_empty() and battle.movement_ghost.model.find_children("*", "CollisionObject3D", true, false).is_empty(), "Ghost contains visible geometry without gameplay collision")
	var elevated := grid.grid_to_world(Vector3i(11, 1, 14))
	battle.movement_ghost.show_destination(actor, Vector3i(11, 1, 14), grid)
	check((battle.movement_ghost.model.global_position - actor.visual_adapter.rig.global_position).is_equal_approx(elevated - (actor.global_position - Vector3.UP * actor.standing_height)), "The ghost preserves its rig offset at an actual elevated ramp support")
	var live_pose := actor.visual_adapter.get_presentation_state()
	for cover_case in [[Vector3i(23, 0, 17), &"cover_low"], [Vector3i(27, 0, 17), &"cover_high"]]:
		battle.movement_ghost.show_destination(actor, cover_case[0], grid)
		check(battle.movement_ghost.model.get_presentation_state() == cover_case[1], "Hologram previews the shared destination cover animation: %s" % cover_case[1])
	var animation_time: float = battle.movement_ghost.model.rig.animation_controller.playback.get_current_play_position()
	for _frame in 3: await process_frame
	check(battle.movement_ghost.model.rig.animation_controller.animation_tree.active and battle.movement_ghost.model.rig.animation_controller.playback.get_current_play_position() != animation_time, "Hologram plays the shared animation rather than displaying a frozen pose")
	check(actor.visual_adapter.get_presentation_state() == live_pose, "Animating the hologram does not change the live unit's animation state")
	battle.movement_ghost.show_destination(actor, destination, grid)
	check(battle.movement_ghost.model is UnitVisualAdapter and battle.movement_ghost.model.tactical_unit == null and battle.movement_ghost.model.rig.clip_library == actor.visual_adapter.rig.clip_library, "Ghost uses the same animation rig/assets without a gameplay actor")
	check(battle.shot_trajectory_visualizer.destination_lines.size() == 1 and battle.shot_trajectory_visualizer.destination_lines[0].last_origin.is_equal_approx(grid.grid_to_world(destination) + Vector3.UP * actor.standing_height), "Outgoing line starts at the same proposed firing point")
	check(fingerprint == BattleStateFingerprint.capture(level.turn_manager, grid, level.objective_manager) and rng_before == service.get_combat_rng_state(), "Ghost, text and lines change no authoritative state or RNG")
	await _capture("destination-ghost", level)
	check(hud.cancel_move_button.visible and hud.cancel_move_button.custom_minimum_size.y >= 48, "Planning exposes a prominent Cancel Move button")
	hud.cancel_move_button.pressed.emit()
	check(not battle.is_move_mode_active and battle.movement_ghost.model == null and battle.shot_trajectory_visualizer.destination_lines.is_empty() and actor.stats.current_ap == 2, "Cancel Move clears ghost and lines without spending AP")
	battle.is_move_mode_active = true
	battle.current_movement_zone.assign([destination])
	battle._update_movement_preview({"position": grid.grid_to_world(destination)})
	check(battle.movement_ghost.model != null, "Returning to the same destination after Cancel rebuilds the preview immediately")
	var line_id := battle.shot_trajectory_visualizer.destination_lines[0].get_instance_id()
	battle._update_movement_preview({"position": grid.grid_to_world(destination)})
	check(battle.shot_trajectory_visualizer.destination_lines[0].get_instance_id() == line_id, "Unchanged hover reuses its ghost/line analysis instead of rebuilding every frame")
	var arrival_pose := battle.movement_ghost.model.get_presentation_state()
	hud.cancel_move_button.pressed.emit()
	var ap_after := move.actor_ap_after
	move.actor_ap_after = 0
	check(TacticalFeedbackText.movement_options(move, actor, [enemy], grid)[0].unavailable == "No AP after moving", "A geometrically possible outgoing shot does not promise unavailable AP")
	move.actor_ap_after = ap_after
	actor.stats.current_supply_points = 0
	check(TacticalFeedbackText.movement_options(move, actor, [enemy], grid)[0].unavailable == "No SP", "Outgoing preview distinguishes missing ammunition")
	actor.stats.current_supply_points = 4
	pause_menu.set_open(true)
	pause_menu.confirmations_option.button_pressed = false
	pause_menu.movement_confirmation_option.button_pressed = true
	BattleUXSettings.loaded = false
	BattleUXSettings.load_preferences()
	check(not BattleUXSettings.confirm_actions and BattleUXSettings.confirm_movement, "Pause preferences persist independently to the local configuration")
	await _capture("pause-confirmation-settings", level)
	pause_menu.set_open(false)
	var bypassed := [0]
	await battle._confirmation_dialog().request("Disabled confirmations", "No modal", func(): bypassed[0] += 1)
	check(bypassed[0] == 1 and not paused, "Disabling action confirmations bypasses the modal")
	battle.is_move_mode_active = true
	battle.current_movement_zone.assign([destination])
	await battle.confirm_player_action(&"move", actor, null, destination)
	check(battle.movement_ghost.destination.is_equal_approx(grid.grid_to_world(destination)), "Confirming a chosen cell refreshes the frozen ghost before the next hover frame")
	check(paused and actor.grid_position != destination, "Optional movement confirmation selects without committing")
	await _capture("move-confirmation", level)
	battle.action_confirmation.canceled.emit()
	check(battle.is_move_mode_active and actor.stats.current_ap == 2, "Canceling selected movement returns to planning")
	BattleUXSettings.confirm_movement = false
	await battle.confirm_player_action(&"move", actor, null, destination)
	check(not paused and actor.grid_position == destination and actor.stats.current_ap == 1 and not actor.tactical_state.is_aiming, "One-click movement stays fast when its separate confirmation option is off")
	var actual := battle.query_attack(actor, enemy)
	check(actor.visual_adapter.get_presentation_state() == arrival_pose, "Committed unit arrival uses the same animation state as the hologram preview")
	check(actual.is_legal() and actual.hit_chance == options[0].outgoing.hit_chance and actual.damage_on_hit == options[0].damage, "Actual Move then authoritative Attack matches the proposed outgoing shot")
	BattleUXSettings.confirm_actions = true
	await battle.confirm_player_action(&"attack", actor, enemy)
	enemy.queue_free()
	await process_frame
	battle.action_confirmation.confirmed.emit()
	check(not paused and actor.stats.current_ap == 1 and battle._last_tactical_preview.contains("no longer available"), "A removed target cannot be used by a pending confirmation")
	await battle.confirm_player_action(&"wait", actor)
	check(paused, "Exit-lifetime check begins with a live modal")
	level.queue_free()
	await process_frame
	await process_frame
	check(not paused, "Removing a battle with an open confirmation restores the SceneTree")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BattleUXSettings.storage_path))
	BattleUXSettings.storage_path = old_preferences[0]
	BattleUXSettings.loaded = old_preferences[1]
	BattleUXSettings.confirm_actions = old_preferences[2]
	BattleUXSettings.confirm_movement = old_preferences[3]
	print("Combat decision preview: %d checks, %d failure(s)" % [checks, failures])
	quit(1 if failures else 0)
