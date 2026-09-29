class_name DebugTools
extends Control

const DebugMapInspectorData := preload("res://visualizers/debug_map_inspector.gd")
const DebugMissionControllerData := preload("res://systems/debug_mission_controller.gd")
const AIScoringOverlayData := preload("res://visualizers/ai_scoring_overlay.gd")

@export_group("Debug Availability")
@export var debug_tools_enabled: bool = true
@export var overlay_visible_at_start: bool = false

@export_group("Battle References")
@export var battle_controller: BattleController
@export var turn_manager: TurnManager
@export var grid_manager: GridManager

var panel_open: bool = false
var _paused_by_debug_tools: bool = false
var _panel: PanelContainer
var _overlay: Label
var _hint: Label
var _manual_enemy_toggle: CheckButton
var _overlay_toggle: CheckButton
var _auto_battle_toggle: CheckButton
var _shot_trajectory_toggle: CheckButton
var _ai_decision_toggle: CheckButton
var _ai_decision_label: Label
var _map_inspection_label: Label
var _map_inspector: Node3D
var _map_inspection_toggle: CheckButton
var _zone_toggle: CheckButton
var _traversal_toggle: CheckButton
var _mission_controller: RefCounted
var _objective_option: OptionButton
var _actor_option: OptionButton
var _mission_status: Label
var _ai_scoring_overlay: Node3D
var _ai_scoring_toggle: CheckButton
var _ai_scoring_label: Label
var _inspected_destination := Vector3i(-1, -1, -1)
var _show_ai_decisions: bool = true
var _latest_ai_decision: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	_build_map_inspector()
	_build_ai_scoring_overlay()
	_build_mission_controller()
	battle_controller.ai_decision_recorded.connect(_on_ai_decision_recorded)
	visible = debug_tools_enabled and not battle_controller.replay_mode
	_set_shot_trajectories_visible(debug_tools_enabled)
	if debug_tools_enabled:
		_set_overlay_visible(overlay_visible_at_start)

func _process(_delta: float) -> void:
	if debug_tools_enabled and _overlay.visible:
		_update_overlay()
	if debug_tools_enabled and _map_inspector and _map_inspector.inspection_enabled:
		_update_map_inspection()

func _unhandled_key_input(event: InputEvent) -> void:
	if not debug_tools_enabled or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F3:
		var pause_menu := get_tree().get_first_node_in_group("battle_pause_menu") as BattlePauseMenu
		if pause_menu and pause_menu.is_open:
			return
		set_panel_open(not panel_open)
		get_viewport().set_input_as_handled()

func set_panel_open(open: bool) -> void:
	if not debug_tools_enabled or panel_open == open:
		return
	panel_open = open
	_panel.visible = open
	if open:
		_capture_inspected_destination()
		_refresh_mission_controls()
		_paused_by_debug_tools = not get_tree().paused
		get_tree().paused = true
	elif _paused_by_debug_tools:
		get_tree().paused = false
		_paused_by_debug_tools = false

func set_manual_enemy_control(enabled: bool) -> void:
	if enabled and battle_controller and battle_controller.debug_player_ai:
		battle_controller.set_debug_player_ai(false)
		_auto_battle_toggle.set_pressed_no_signal(false)
	if battle_controller:
		battle_controller.set_debug_enemy_control(enabled)
	if _manual_enemy_toggle:
		_manual_enemy_toggle.button_pressed = enabled

func set_auto_battle(enabled: bool) -> void:
	if enabled:
		battle_controller.set_debug_enemy_control(false)
		_manual_enemy_toggle.set_pressed_no_signal(false)
	battle_controller.set_debug_player_ai(enabled)
	if _auto_battle_toggle:
		_auto_battle_toggle.button_pressed = enabled

func _build_interface() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hint = Label.new()
	_hint.name = "DebugHint"
	_hint.text = "DEBUG  [F3]"
	_hint.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_hint.position = Vector2(-145, 12)
	_hint.add_theme_color_override("font_color", Color(0.45, 1.0, 0.75))
	_hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hint.add_theme_constant_override("shadow_offset_x", 2)
	_hint.add_theme_constant_override("shadow_offset_y", 2)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hint)

	_overlay = Label.new()
	_overlay.name = "DebugOverlay"
	_overlay.position = Vector2(16, 120)
	_overlay.add_theme_color_override("font_color", Color(0.45, 1.0, 0.75))
	_overlay.add_theme_color_override("font_shadow_color", Color.BLACK)
	_overlay.add_theme_constant_override("shadow_offset_x", 2)
	_overlay.add_theme_constant_override("shadow_offset_y", 2)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)

	_ai_decision_label = Label.new()
	_ai_decision_label.name = "AIDecisionOverlay"
	_ai_decision_label.position = Vector2(16, 300)
	_ai_decision_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	_ai_decision_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_ai_decision_label.add_theme_constant_override("shadow_offset_x", 2)
	_ai_decision_label.add_theme_constant_override("shadow_offset_y", 2)
	_ai_decision_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_ai_decision_label)

	_map_inspection_label = Label.new()
	_map_inspection_label.name = "MapInspectionOverlay"
	_map_inspection_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_map_inspection_label.position = Vector2(-500, 105)
	_map_inspection_label.custom_minimum_size = Vector2(480, 0)
	_map_inspection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_map_inspection_label.add_theme_color_override("font_color", Color(0.55, 0.92, 1.0))
	_map_inspection_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_map_inspection_label.add_theme_constant_override("shadow_offset_x", 2)
	_map_inspection_label.add_theme_constant_override("shadow_offset_y", 2)
	_map_inspection_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_inspection_label.hide()
	add_child(_map_inspection_label)


	_ai_scoring_label = Label.new()
	_ai_scoring_label.name = "AIScoringDetails"
	_ai_scoring_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ai_scoring_label.position = Vector2(-540, 300)
	_ai_scoring_label.custom_minimum_size = Vector2(520, 0)
	_ai_scoring_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ai_scoring_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.48))
	_ai_scoring_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_ai_scoring_label.add_theme_constant_override("shadow_offset_x", 2)
	_ai_scoring_label.add_theme_constant_override("shadow_offset_y", 2)
	_ai_scoring_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ai_scoring_label.hide()
	add_child(_ai_scoring_label)

	_panel = PanelContainer.new()
	_panel.name = "DebugPanel"
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.065, 1.0)
	_panel.add_theme_stylebox_override("panel", panel_style)
	_panel.position = Vector2(350, 38)
	_panel.custom_minimum_size = Vector2(390, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = false
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 8)
	margin.add_child(content)

	var title := Label.new()
	title.text = "DEBUG TOOLS — BATTLE PAUSED"
	title.add_theme_color_override("font_color", Color(0.45, 1.0, 0.75))
	content.add_child(title)

	var help := Label.new()
	help.text = "F3 — toggle panel and pause"
	content.add_child(help)

	_overlay_toggle = CheckButton.new()
	_overlay_toggle.text = "Show battle-data overlay"
	_overlay_toggle.button_pressed = overlay_visible_at_start
	_overlay_toggle.toggled.connect(_set_overlay_visible)
	content.add_child(_overlay_toggle)

	_shot_trajectory_toggle = CheckButton.new()
	_shot_trajectory_toggle.text = "Show shot trajectories"
	_shot_trajectory_toggle.button_pressed = true
	_shot_trajectory_toggle.toggled.connect(_set_shot_trajectories_visible)
	content.add_child(_shot_trajectory_toggle)

	_ai_decision_toggle = CheckButton.new()
	_ai_decision_toggle.text = "Show AI decision explanations"
	_ai_decision_toggle.button_pressed = true
	_ai_decision_toggle.toggled.connect(_set_ai_decisions_visible)
	content.add_child(_ai_decision_toggle)

	_map_inspection_toggle = CheckButton.new()
	_map_inspection_toggle.text = "Inspect map cells and metadata"
	_map_inspection_toggle.toggled.connect(_set_map_inspection_visible)
	content.add_child(_map_inspection_toggle)

	_zone_toggle = CheckButton.new()
	_zone_toggle.text = "Show all map zones"
	_zone_toggle.button_pressed = true
	_zone_toggle.toggled.connect(_set_map_zones_visible)
	content.add_child(_zone_toggle)

	_traversal_toggle = CheckButton.new()
	_traversal_toggle.text = "Show traversal links"
	_traversal_toggle.button_pressed = true
	_traversal_toggle.toggled.connect(_set_traversal_links_visible)
	content.add_child(_traversal_toggle)


	_ai_scoring_toggle = CheckButton.new()
	_ai_scoring_toggle.text = "Show AI scoring overlay"
	_ai_scoring_toggle.tooltip_text = "Shows numeric movement scores, rejected cells, targets, and the chosen plan."
	_ai_scoring_toggle.toggled.connect(_set_ai_scoring_visible)
	content.add_child(_ai_scoring_toggle)

	_manual_enemy_toggle = CheckButton.new()
	_manual_enemy_toggle.text = "Manual enemy control"
	_manual_enemy_toggle.toggled.connect(set_manual_enemy_control)
	content.add_child(_manual_enemy_toggle)

	_auto_battle_toggle = CheckButton.new()
	_auto_battle_toggle.text = "AI controls both teams"
	_auto_battle_toggle.toggled.connect(set_auto_battle)
	content.add_child(_auto_battle_toggle)

	var mission_heading := Label.new()
	mission_heading.text = "MISSION CONTROLS"
	mission_heading.add_theme_color_override("font_color", Color(1.0, 0.55, 0.82))
	content.add_child(mission_heading)

	var advance_round := Button.new()
	advance_round.text = "Advance One Round"
	advance_round.pressed.connect(_debug_advance_round)
	content.add_child(advance_round)

	_objective_option = OptionButton.new()
	_objective_option.tooltip_text = "Active mission objective affected by Complete or Fail."
	content.add_child(_objective_option)
	var objective_buttons := HBoxContainer.new()
	var complete_objective := Button.new()
	complete_objective.text = "Complete Objective"
	complete_objective.pressed.connect(_debug_complete_objective)
	objective_buttons.add_child(complete_objective)
	var fail_objective := Button.new()
	fail_objective.text = "Fail Objective"
	fail_objective.pressed.connect(_debug_fail_objective)
	objective_buttons.add_child(fail_objective)
	content.add_child(objective_buttons)

	_actor_option = OptionButton.new()
	_actor_option.tooltip_text = "Actor affected by Teleport or Force Extraction."
	content.add_child(_actor_option)
	var actor_buttons := HBoxContainer.new()
	var teleport_actor := Button.new()
	teleport_actor.text = "Teleport to Inspected Cell"
	teleport_actor.pressed.connect(_debug_teleport_actor)
	actor_buttons.add_child(teleport_actor)
	var force_extract := Button.new()
	force_extract.text = "Force Extraction"
	force_extract.pressed.connect(_debug_force_extract)
	actor_buttons.add_child(force_extract)
	content.add_child(actor_buttons)

	_mission_status = Label.new()
	_mission_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_status.custom_minimum_size = Vector2(350, 36)
	_mission_status.text = "Hover a destination before opening F3."
	_mission_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.88))
	content.add_child(_mission_status)

	var explanation := Label.new()
	explanation.text = "Manual control pauses enemy decisions.\nUse the normal action bar, then End Turn.\nAI control runs complete rounds for testing."
	content.add_child(explanation)

	var resume := Button.new()
	resume.text = "Resume Battle"
	resume.pressed.connect(set_panel_open.bind(false))
	content.add_child(resume)

func _set_overlay_visible(enabled: bool) -> void:
	if _overlay:
		_overlay.visible = enabled

func _set_shot_trajectories_visible(enabled: bool) -> void:
	if battle_controller and battle_controller.shot_trajectory_visualizer:
		battle_controller.shot_trajectory_visualizer.set_debug_enabled(enabled)

func _set_ai_decisions_visible(enabled: bool) -> void:
	_show_ai_decisions = enabled
	if _ai_decision_label:
		_ai_decision_label.visible = enabled

func _build_map_inspector() -> void:
	if not battle_controller or not grid_manager:
		return
	_map_inspector = DebugMapInspectorData.new()
	_map_inspector.name = "DebugMapInspector"
	_map_inspector.grid_manager = grid_manager
	_map_inspector.mouse_raycaster = battle_controller.mouse_raycaster
	battle_controller.get_parent().get_parent().get_node("Visualizers").add_child.call_deferred(_map_inspector)

func _build_ai_scoring_overlay() -> void:
	_ai_scoring_overlay = AIScoringOverlayData.new()
	_ai_scoring_overlay.name = "AIScoringOverlay"
	_ai_scoring_overlay.grid_manager = grid_manager
	battle_controller.get_parent().get_parent().get_node("Visualizers").add_child.call_deferred(_ai_scoring_overlay)

func _set_ai_scoring_visible(enabled: bool) -> void:
	if _ai_scoring_overlay:
		_ai_scoring_overlay.set_overlay_enabled(enabled)
	if _ai_scoring_label:
		_ai_scoring_label.visible = enabled
	if enabled and not _latest_ai_decision.is_empty():
		_update_ai_scoring_details(_latest_ai_decision)

func _update_ai_scoring_details(record: Dictionary) -> void:
	if not _ai_scoring_label:
		return
	var positions: Array = record.get("position_candidates", [])
	var targets: Array = record.get("target_candidates", [])
	var legal_positions: Array = positions.filter(func(candidate: Dictionary): return candidate.get("status", "") != "rejected")
	legal_positions.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("score", -INF)) > float(b.get("score", -INF)))
	var rejected_positions: Array = positions.filter(func(candidate: Dictionary): return candidate.get("status", "") == "rejected")
	var lines: Array[String] = [
		"AI SCORING — %s [%s]" % [record.get("actor", "Unknown"), record.get("difficulty", "Normal")],
		"CHOSEN — %s %s" % [record.get("action", "Unknown"), record.get("subject", "")],
		"Movement: %d scored | %d rejected" % [legal_positions.size(), rejected_positions.size()],
	]
	for candidate in legal_positions.slice(0, 8):
		lines.append("%s %+.1f%s — %s" % [candidate.cell, float(candidate.score), "  CHOSEN" if candidate.get("chosen", false) else "", candidate.get("summary", "")])
	for candidate in rejected_positions.slice(0, 4):
		lines.append("%s REJECTED — %s" % [candidate.get("cell", "?"), candidate.get("reason", "No score")])
	if not targets.is_empty():
		lines.append("Targets:")
		for candidate in targets.slice(0, 6):
			if candidate.get("status", "") == "rejected":
				lines.append("%s REJECTED — %s" % [candidate.get("target", "?"), candidate.get("reason", "Illegal attack")])
			else:
				lines.append("%s %+.1f%s — %s" % [candidate.get("target", "?"), float(candidate.get("score", 0.0)), "  CHOSEN" if candidate.get("chosen", false) else "", candidate.get("summary", "")])
	_ai_scoring_label.text = "\n".join(lines)

func _build_mission_controller() -> void:
	_mission_controller = DebugMissionControllerData.new()
	var objectives := get_tree().get_first_node_in_group("objective_manager") as ObjectiveManager
	_mission_controller.configure(battle_controller, turn_manager, objectives, grid_manager)
	_mission_controller.command_executed.connect(_on_debug_mission_command)

func _capture_inspected_destination() -> void:
	if _map_inspector and _map_inspector.hovered_cell:
		_inspected_destination = _map_inspector.hovered_cell.grid_position
		return
	if battle_controller and battle_controller.mouse_raycaster:
		var hit := battle_controller.mouse_raycaster.get_floor_raycast_result()
		if not hit.is_empty():
			_inspected_destination = hit.grid_position

func _refresh_mission_controls() -> void:
	if not _mission_controller or not _objective_option or not _actor_option:
		return
	_objective_option.clear()
	for state in _mission_controller.get_active_objectives():
		_objective_option.add_item("%s — %d/%d" % [state.definition.title, state.progress, state.definition.target_amount])
		_objective_option.set_item_metadata(_objective_option.item_count - 1, state.definition.objective_id)
	if _objective_option.item_count == 0:
		_objective_option.add_item("No active objectives")
		_objective_option.disabled = true
	else:
		_objective_option.disabled = false
	_actor_option.clear()
	for actor in _mission_controller.get_actors():
		_actor_option.add_item("%s — %s" % [actor.name, TacticalUnit.Faction.keys()[actor.faction]])
		_actor_option.set_item_metadata(_actor_option.item_count - 1, actor.get_instance_id())
	if _actor_option.item_count == 0:
		_actor_option.add_item("No available actors")
		_actor_option.disabled = true
	else:
		_actor_option.disabled = false
	if _mission_status and _inspected_destination.x >= 0:
		_mission_status.text = "Inspected destination: %s" % _inspected_destination

func _selected_objective_id() -> StringName:
	if not _objective_option or _objective_option.disabled or _objective_option.selected < 0:
		return &""
	return StringName(_objective_option.get_item_metadata(_objective_option.selected))

func _selected_actor() -> TacticalUnit:
	if not _actor_option or _actor_option.disabled or _actor_option.selected < 0:
		return null
	return instance_from_id(int(_actor_option.get_item_metadata(_actor_option.selected))) as TacticalUnit

func _debug_advance_round() -> void:
	_mission_controller.advance_round()
	_refresh_mission_controls()

func _debug_complete_objective() -> void:
	_mission_controller.complete_objective(_selected_objective_id())
	_refresh_mission_controls()

func _debug_fail_objective() -> void:
	_mission_controller.fail_objective(_selected_objective_id())
	_refresh_mission_controls()

func _debug_teleport_actor() -> void:
	if _inspected_destination.x < 0:
		_on_debug_mission_command("Teleport rejected: hover a destination before opening F3.")
		return
	_mission_controller.teleport_actor(_selected_actor(), _inspected_destination)
	_refresh_mission_controls()

func _debug_force_extract() -> void:
	_mission_controller.force_extract(_selected_actor())
	_refresh_mission_controls()

func _on_debug_mission_command(message: String) -> void:
	if _mission_status:
		_mission_status.text = message

func _set_map_inspection_visible(enabled: bool) -> void:
	if _map_inspector:
		_map_inspector.set_inspection_enabled(enabled)
	if _map_inspection_label:
		_map_inspection_label.visible = enabled

func _set_map_zones_visible(enabled: bool) -> void:
	if _map_inspector:
		_map_inspector.set_zones_visible(enabled)

func _set_traversal_links_visible(enabled: bool) -> void:
	if _map_inspector:
		_map_inspector.set_traversal_links_visible(enabled)

func _update_map_inspection() -> void:
	if not _map_inspection_label:
		return
	var lines: Array[String] = _map_inspector.get_map_summary()
	lines.append("")
	lines.append_array(_map_inspector.get_hover_summary())
	_map_inspection_label.text = "\n".join(lines)

func _on_ai_decision_recorded(record: Dictionary) -> void:
	_latest_ai_decision = record
	if _ai_scoring_overlay:
		_ai_scoring_overlay.display(record)
	if _ai_scoring_toggle and _ai_scoring_toggle.button_pressed:
		_update_ai_scoring_details(record)
	if not _ai_decision_label:
		return
	_ai_decision_label.text = "AI DECISION — %s\n%s → %s  %s\nMission goal: %s\nPosition: %s\nTarget: %s\nSquad: %s\nReason: %s\nAlternatives: %s" % [
		record.get("difficulty", "Normal"),
		record.get("actor", "Unknown"),
		record.get("action", "Unknown"),
		record.get("subject", ""),
		record.get("mission_goal", "None"),
		record.get("position_scores", "None"),
		record.get("target_scores", "None"),
		record.get("squad_adjustments", "None"),
		record.get("reason", ""),
		record.get("alternatives", ""),
	]
	_ai_decision_label.visible = _show_ai_decisions

func _update_overlay() -> void:
	if not turn_manager or not grid_manager:
		_overlay.text = "DEBUG: missing battle references"
		return
	var phase_name: String = TurnManager.TurnPhase.keys()[turn_manager.current_phase]
	var lines: Array[String] = [
		"DEBUG  [F3]",
		"Round %d  |  %s" % [turn_manager.current_round, phase_name],
		"Map cells: %d  |  Occupied: %d" % [grid_manager.map_data.cells.size(), grid_manager.occupancy_map.size()],
	]
	var active := turn_manager.active_unit
	if is_instance_valid(active) and active.stats:
		lines.append("Active: %s  |  %s" % [active.name, TacticalUnit.Faction.keys()[active.faction]])
		lines.append("Mission: %s  |  %s%s" % [
			active.get_mission_id(),
			MissionActor.Kind.keys()[active.get_mission_actor_kind()],
			"  |  EXTRACTOR" if active.can_extract_others() else "",
		])
		lines.append("Cell: %s  |  HP: %d/%d  |  AP: %d/%d" % [grid_manager.get_unit_grid(active), active.stats.current_hp, active.stats.max_hp, active.stats.current_ap, active.stats.max_ap])
		lines.append("Move: %d  |  Range: %d" % [active.stats.speed, active.attack_range])
	if battle_controller and battle_controller.debug_enemy_control:
		lines.append("Enemy control: MANUAL")
	if battle_controller and battle_controller.debug_player_ai:
		lines.append("Battle control: AI vs AI")
	if battle_controller and battle_controller.shot_trajectory_visualizer:
		var blocker := battle_controller.shot_trajectory_visualizer.last_blocking_cell
		if blocker:
			lines.append("LOS blocker: %s  |  %s  |  %.1fm" % [blocker.grid_position, MapCellData.CoverType.keys()[blocker.cover_type], blocker.cover_height])
	_overlay.text = "\n".join(lines)
