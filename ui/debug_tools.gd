class_name DebugTools
extends Control

const DebugMapInspectorData := preload("res://presentation/overlays/debug_map_inspector.gd")
const DebugMissionControllerData := preload("res://systems/debug_mission_controller.gd")
const DebugInspection := preload("res://ui/debug_inspection_snapshot.gd")
const AIScoringOverlayData := preload("res://presentation/overlays/ai_scoring_overlay.gd")
const AIReservationOverlayData := preload("res://presentation/overlays/ai_reservation_overlay.gd")
const DECISION_HISTORY_LIMIT := 80

@export_group("Debug Availability")
@export var debug_tools_enabled: bool = true
@export var overlay_visible_at_start: bool = false

@export_group("Battle References")
@export var battle_controller: BattleController
@export var turn_manager: TurnManager
@export var grid_manager: GridManager
@export var objective_manager: ObjectiveManager
## Battle-local parent for developer overlays; independent of scene hierarchy.
@export var presentation_root: Node3D

var panel_open: bool = false
var _paused_by_debug_tools: bool = false
var _panel: PanelContainer
var _seed_label: Label
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
var _show_ai_decisions: bool = false
var _latest_ai_decision: Dictionary = {}
var _latest_ai_outcome: Dictionary = {}
var _ai_reservation_overlay: Node3D
var _ai_reservation_toggle: CheckButton
## Recent decisions, oldest first, and their authoritative outcomes by decision id.
var _decision_history: Array[Dictionary] = []
var _decision_outcomes: Dictionary = {}
var _timeline_list: ItemList
var _timeline_details: RichTextLabel
var _inspection_snapshot: Dictionary = {}
var _inspection_labels: Dictionary = {}
var _inspection_status: Label
var _target_picker: OptionButton
var _manifest_toggle: CheckButton
var _tabs: TabContainer
var _monitor_elapsed := 0.0
var _inspection_invalidated := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Unit world bars are added to the same CanvasLayer after battle startup.
	# Keep modal developer UI above those dynamically-created controls.
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	_build_map_inspector()
	_build_ai_scoring_overlay()
	_build_ai_reservation_overlay()
	_build_mission_controller()
	battle_controller.ai_decision_recorded.connect(_on_ai_decision_recorded)
	battle_controller.ai_action_outcome_recorded.connect(_on_ai_action_outcome)
	visible = debug_tools_enabled and not battle_controller.replay_mode
	_set_shot_trajectories_visible(false)
	if debug_tools_enabled:
		_set_overlay_visible(overlay_visible_at_start)

func _process(_delta: float) -> void:
	if panel_open:
		_monitor_elapsed += _delta
		if _monitor_elapsed >= 0.5:
			_monitor_elapsed = 0.0
			_update_inspection_status()
			_inspection_labels["Runtime"].text = DebugInspection.runtime_summary()
	if debug_tools_enabled and _overlay.visible:
		_update_overlay()
	if debug_tools_enabled and _map_inspector and _map_inspector.inspection_enabled:
		_update_map_inspection()

func _unhandled_key_input(event: InputEvent) -> void:
	if not debug_tools_enabled or battle_controller.replay_mode or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F3:
		var pause_menu := get_tree().get_first_node_in_group("battle_pause_menu") as BattlePauseMenu
		if (pause_menu and pause_menu.is_open) or (is_instance_valid(battle_controller.action_confirmation) and battle_controller.action_confirmation.visible):
			return
		set_panel_open(not panel_open)
		get_viewport().set_input_as_handled()

func set_panel_open(open: bool) -> void:
	if not debug_tools_enabled or battle_controller.replay_mode or panel_open == open:
		return
	panel_open = open
	_panel.visible = open
	if open:
		_update_seed_display()
		_capture_inspected_destination()
		_refresh_mission_controls()
		_capture_inspection()
		_layout_panel()
		_paused_by_debug_tools = not get_tree().paused
		get_tree().paused = true
	elif _paused_by_debug_tools:
		get_tree().paused = false
		_paused_by_debug_tools = false

func set_manual_enemy_control(enabled: bool) -> void:
	if battle_controller.replay_mode: return
	if enabled and battle_controller and battle_controller.debug_player_ai:
		battle_controller.set_debug_player_ai(false)
		_auto_battle_toggle.set_pressed_no_signal(false)
	if battle_controller:
		battle_controller.set_debug_enemy_control(enabled)
	if _manual_enemy_toggle:
		_manual_enemy_toggle.button_pressed = enabled

func set_auto_battle(enabled: bool) -> void:
	if battle_controller.replay_mode: return
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
	_ai_scoring_label.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_ai_scoring_label.offset_left = -560
	_ai_scoring_label.offset_top = 260
	_ai_scoring_label.offset_right = -20
	_ai_scoring_label.offset_bottom = -24
	_ai_scoring_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ai_scoring_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_ai_scoring_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_ai_scoring_label.clip_text = true
	_ai_scoring_label.add_theme_font_size_override("font_size", 13)
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
	_panel.position = Vector2(300, 38)
	_panel.custom_minimum_size = Vector2(500, 0)
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

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 12)
	content.add_child(seed_row)
	_seed_label = Label.new()
	_seed_label.name = "SeedSummary"
	_seed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_label.add_theme_color_override("font_color", Color(0.75, 0.88, 1.0))
	seed_row.add_child(_seed_label)
	var copy_seed := Button.new()
	copy_seed.text = "Copy Seed"
	copy_seed.tooltip_text = "Copy the match seed for an exact reproduction."
	copy_seed.pressed.connect(_copy_battle_seed)
	seed_row.add_child(copy_seed)
	_update_seed_display()

	_inspection_status = Label.new()
	_inspection_status.custom_minimum_size.x = 400
	_inspection_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_inspection_status)
	var tabs := TabContainer.new()
	_tabs = tabs
	tabs.name = "DebugSections"
	tabs.custom_minimum_size = Vector2(0, 0)
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.use_hidden_tabs_for_min_size = false
	for section in ["Unit", "Tactical", "AI", "Timeline", "Map", "Runtime"]:
		_build_inspection_section(tabs, section)
	content.add_child(tabs)
	var diagnostics_scroll := ScrollContainer.new()
	diagnostics_scroll.name = "Diagnostics"
	diagnostics_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(diagnostics_scroll)
	var diagnostics := VBoxContainer.new()
	diagnostics.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagnostics.add_theme_constant_override("separation", 6)
	diagnostics_scroll.add_child(diagnostics)
	var control_scroll := ScrollContainer.new()
	control_scroll.name = "Control"
	control_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(control_scroll)
	var control := VBoxContainer.new()
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.add_theme_constant_override("separation", 8)
	control_scroll.add_child(control)
	var mission_scroll := ScrollContainer.new()
	mission_scroll.name = "Mission"
	mission_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(mission_scroll)
	var mission := VBoxContainer.new()
	mission.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mission.add_theme_constant_override("separation", 8)
	mission_scroll.add_child(mission)

	_overlay_toggle = CheckButton.new()
	_overlay_toggle.text = "Show battle-data overlay"
	_overlay_toggle.button_pressed = overlay_visible_at_start
	_overlay_toggle.toggled.connect(_set_overlay_visible)
	diagnostics.add_child(_overlay_toggle)

	_shot_trajectory_toggle = CheckButton.new()
	_shot_trajectory_toggle.text = "Show shot trajectories"
	_shot_trajectory_toggle.button_pressed = false
	_shot_trajectory_toggle.toggled.connect(_set_shot_trajectories_visible)
	diagnostics.add_child(_shot_trajectory_toggle)

	_ai_decision_toggle = CheckButton.new()
	_ai_decision_toggle.text = "Show AI decision explanations"
	_ai_decision_toggle.button_pressed = false
	_ai_decision_toggle.toggled.connect(_set_ai_decisions_visible)
	diagnostics.add_child(_ai_decision_toggle)

	_map_inspection_toggle = CheckButton.new()
	_map_inspection_toggle.text = "Inspect map cells and metadata"
	_map_inspection_toggle.toggled.connect(_set_map_inspection_visible)
	diagnostics.add_child(_map_inspection_toggle)

	_zone_toggle = CheckButton.new()
	_zone_toggle.text = "Show all map zones"
	_zone_toggle.button_pressed = false
	_zone_toggle.toggled.connect(_set_map_zones_visible)
	diagnostics.add_child(_zone_toggle)

	_traversal_toggle = CheckButton.new()
	_traversal_toggle.text = "Show traversal links"
	_traversal_toggle.button_pressed = false
	_traversal_toggle.toggled.connect(_set_traversal_links_visible)
	diagnostics.add_child(_traversal_toggle)


	_ai_scoring_toggle = CheckButton.new()
	_ai_scoring_toggle.text = "Show AI scoring overlay"
	_ai_scoring_toggle.tooltip_text = "Shows a movement-score heatmap, considered targets, and the chosen plan. Rejected reasons remain in the details panel."
	_ai_scoring_toggle.toggled.connect(_set_ai_scoring_visible)
	diagnostics.add_child(_ai_scoring_toggle)

	_ai_reservation_toggle = CheckButton.new()
	_ai_reservation_toggle.text = "Show squad reservations"
	_ai_reservation_toggle.tooltip_text = "Cyan: reserved destinations (with owner). Green: the carrier's reserved corridor. Magenta: targets squads have committed to."
	_ai_reservation_toggle.toggled.connect(_set_ai_reservations_visible)
	diagnostics.add_child(_ai_reservation_toggle)

	_manual_enemy_toggle = CheckButton.new()
	_manual_enemy_toggle.text = "Manual enemy control"
	_manual_enemy_toggle.toggled.connect(set_manual_enemy_control)
	control.add_child(_manual_enemy_toggle)

	_auto_battle_toggle = CheckButton.new()
	_auto_battle_toggle.text = "AI controls both teams"
	_auto_battle_toggle.toggled.connect(set_auto_battle)
	control.add_child(_auto_battle_toggle)

	var mission_heading := Label.new()
	mission_heading.text = "MISSION CONTROLS"
	mission_heading.add_theme_color_override("font_color", Color(1.0, 0.55, 0.82))
	mission.add_child(mission_heading)

	var advance_round := Button.new()
	advance_round.text = "Advance One Round"
	advance_round.pressed.connect(_debug_advance_round)
	mission.add_child(advance_round)

	_objective_option = OptionButton.new()
	_objective_option.tooltip_text = "Active mission objective affected by Complete or Fail."
	mission.add_child(_objective_option)
	var objective_buttons := HBoxContainer.new()
	var complete_objective := Button.new()
	complete_objective.text = "Complete Objective"
	complete_objective.pressed.connect(_debug_complete_objective)
	objective_buttons.add_child(complete_objective)
	var fail_objective := Button.new()
	fail_objective.text = "Fail Objective"
	fail_objective.pressed.connect(_debug_fail_objective)
	objective_buttons.add_child(fail_objective)
	mission.add_child(objective_buttons)

	_actor_option = OptionButton.new()
	_actor_option.tooltip_text = "Actor affected by Teleport or Force Extraction."
	mission.add_child(_actor_option)
	var actor_buttons := HBoxContainer.new()
	var teleport_actor := Button.new()
	teleport_actor.text = "Teleport to Inspected Cell"
	teleport_actor.pressed.connect(_debug_teleport_actor)
	actor_buttons.add_child(teleport_actor)
	var force_extract := Button.new()
	force_extract.text = "Force Extraction"
	force_extract.pressed.connect(_debug_force_extract)
	actor_buttons.add_child(force_extract)
	mission.add_child(actor_buttons)

	_mission_status = Label.new()
	_mission_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mission_status.custom_minimum_size = Vector2(350, 36)
	_mission_status.text = "Hover a destination before opening F3."
	_mission_status.add_theme_color_override("font_color", Color(1.0, 0.72, 0.88))
	mission.add_child(_mission_status)

	var explanation := Label.new()
	explanation.text = "Manual control pauses enemy decisions.\nUse the normal action bar, then End Turn.\nAI control runs complete rounds for testing."
	control.add_child(explanation)

	var resume := Button.new()
	resume.text = "Resume Battle"
	resume.pressed.connect(set_panel_open.bind(false))
	content.add_child(resume)
	get_viewport().size_changed.connect(_layout_panel)
	_layout_panel()

func _update_seed_display() -> void:
	if not _seed_label or not battle_controller or not grid_manager:
		return
	var source := grid_manager.map_data.source_kind.to_upper()
	var map_seed := grid_manager.map_data.generation_seed
	_seed_label.text = "MATCH SEED: %d   |   MAP: %s%s" % [
		battle_controller.battle_seed,
		source,
		" (%d)" % map_seed if source.begins_with("GENERATED") or not grid_manager.map_data.content_manifest.is_empty() else "",
	]

func _copy_battle_seed() -> void:
	if not battle_controller:
		return
	DisplayServer.clipboard_set(str(battle_controller.battle_seed))
	if _mission_status:
		_mission_status.text = "Copied match seed %d." % battle_controller.battle_seed

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
	if not battle_controller or not grid_manager or not presentation_root:
		return
	_map_inspector = DebugMapInspectorData.new()
	_map_inspector.name = "DebugMapInspector"
	_map_inspector.grid_manager = grid_manager
	_map_inspector.mouse_raycaster = battle_controller.mouse_raycaster
	presentation_root.add_child.call_deferred(_map_inspector)

func _build_ai_scoring_overlay() -> void:
	if not presentation_root:
		return
	_ai_scoring_overlay = AIScoringOverlayData.new()
	_ai_scoring_overlay.name = "AIScoringOverlay"
	_ai_scoring_overlay.grid_manager = grid_manager
	presentation_root.add_child.call_deferred(_ai_scoring_overlay)

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
	# An attack chooses no tile; its record still carries the last movement plan, which would mislead here.
	var positions: Array = record.get("position_candidates", []) if String(record.get("action", "")) != "Attack" else []
	var targets: Array = record.get("target_candidates", [])
	var legal_positions: Array = positions.filter(func(candidate: Dictionary): return candidate.get("status", "") != "rejected")
	legal_positions.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.get("score", -INF)) > float(b.get("score", -INF)))
	var rejected_positions: Array = positions.filter(func(candidate: Dictionary): return candidate.get("status", "") == "rejected")
	var lines: Array[String] = [
		"AI SCORING — %s [%s]" % [record.get("actor", "Unknown"), record.get("difficulty", "Normal")],
		"HEATMAP — violet: lower | amber: higher | yellow: chosen",
		"CHOSEN — %s %s" % [record.get("action", "Unknown"), record.get("subject", "")],
		"Cell %s | AP %s | Hold %s | Move threshold %s | Urgency %+.1f | Wait streak %s" % [record.get("grid_position", "?"), record.get("remaining_ap", "?"), _format_optional_score(record.get("hold_score")), _format_optional_score(record.get("move_acceptance_threshold")), float(record.get("urgency_bonus", 0.0)), record.get("consecutive_low_value_actions", 0)],
		"Route corridor: %.1f" % float(record.get("route_corridor", 2.0)),
		"Recent move origins: %s" % str(record.get("recent_move_origins", [])),
		"Movement: %d scored | %d rejected" % [legal_positions.size(), rejected_positions.size()],
	]
	for candidate in legal_positions.slice(0, 5):
		lines.append("%s %+.1f%s — %s" % [candidate.cell, float(candidate.score), "  CHOSEN" if candidate.get("chosen", false) else "", candidate.get("summary", "")])
	for candidate in rejected_positions.slice(0, 2):
		lines.append("%s REJECTED — %s" % [candidate.get("cell", "?"), candidate.get("reason", "No score")])
	if not targets.is_empty():
		lines.append("Targets:")
		for candidate in targets.slice(0, 4):
			if candidate.get("status", "") == "rejected":
				lines.append("%s REJECTED — %s" % [candidate.get("target", "?"), candidate.get("reason", "Illegal attack")])
			else:
				lines.append("%s %+.1f%s — %s" % [candidate.get("target", "?"), float(candidate.get("score", 0.0)), "  CHOSEN" if candidate.get("chosen", false) else "", candidate.get("summary", "")])
	_ai_scoring_label.text = "\n".join(lines)

func _format_optional_score(value: Variant) -> String:
	return "n/a" if value == null else "%+.1f" % float(value)

func _build_mission_controller() -> void:
	_mission_controller = DebugMissionControllerData.new()
	_mission_controller.configure(battle_controller, turn_manager, objective_manager, grid_manager)
	_mission_controller.command_executed.connect(_on_debug_mission_command)

func _capture_inspected_destination() -> void:
	_inspected_destination = Vector3i(-1, -1, -1)
	if _map_inspector and _map_inspector.hovered_cell:
		_inspected_destination = _map_inspector.hovered_cell.grid_position
		return
	if battle_controller and battle_controller.mouse_raycaster:
		var hit := battle_controller.mouse_raycaster.get_floor_raycast_result()
		if not hit.is_empty():
			_inspected_destination = hit.grid_position

func _refresh_mission_controls() -> void:
	if not _mission_controller:
		_build_mission_controller()
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
	if battle_controller.replay_mode: return
	_mission_controller.advance_round()
	_refresh_mission_controls()

func _debug_complete_objective() -> void:
	if battle_controller.replay_mode: return
	_mission_controller.complete_objective(_selected_objective_id())
	_refresh_mission_controls()

func _debug_fail_objective() -> void:
	if battle_controller.replay_mode: return
	_mission_controller.fail_objective(_selected_objective_id())
	_refresh_mission_controls()

func _debug_teleport_actor() -> void:
	if battle_controller.replay_mode: return
	if _inspected_destination.x < 0:
		_on_debug_mission_command("Teleport rejected: hover a destination before opening F3.")
		return
	_mission_controller.teleport_actor(_selected_actor(), _inspected_destination)
	_refresh_mission_controls()

func _debug_force_extract() -> void:
	if battle_controller.replay_mode: return
	_mission_controller.force_extract(_selected_actor())
	_refresh_mission_controls()

func _on_debug_mission_command(message: String) -> void:
	_inspection_invalidated = true
	_update_inspection_status()
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
	_decision_history.append(record)
	if _decision_history.size() > DECISION_HISTORY_LIMIT:
		_decision_outcomes.erase(_decision_history.pop_front().get("decision_id", 0))
	_refresh_timeline()
	_refresh_reservations()
	if _ai_scoring_overlay:
		_ai_scoring_overlay.display(record)
	if _ai_scoring_toggle and _ai_scoring_toggle.button_pressed:
		_update_ai_scoring_details(record)
	if not _ai_decision_label:
		return
	_ai_decision_label.text = "AI DECISION — %s\nCommander: %s  |  Intent: %s\nDoctrine: %s\n%s → %s  %s\nMission goal: %s\nPosition: %s\nTarget: %s\nSquad: %s\nReason: %s\nAlternatives: %s" % [
		record.get("difficulty", "Normal"),
		record.get("commander_policy", "Default"),
		record.get("strategic_intent", "Balanced engagement"),
		_commander_composition_summary(record.get("commander_composition", {})),
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
	_ai_decision_label.text += "\nTrace stage: %s · decision %s · revision %s" % [record.get("stage", "explanation"), record.get("decision_id", "?"), record.get("state_revision", "?")]
	_ai_decision_label.visible = _show_ai_decisions

func _commander_composition_summary(composition: Dictionary) -> String:
	if composition.is_empty():
		return "neutral"
	var summaries: Array[String] = []
	for field in ["position_cover_weight", "position_exposure_weight", "position_danger_weight", "movement_progress_weight"]:
		var values: Dictionary = composition.get(field, {})
		if values.is_empty(): continue
		summaries.append("%s %.2f×%.2f=%.2f" % [field.trim_suffix("_weight"), values.get("base", 1.0), values.get("multiplier", 1.0), values.get("final", 1.0)])
	var advance: Dictionary = composition.get("safe_advance_exposure_tolerance", {})
	if not advance.is_empty():
		summaries.append("safe advance %.2f%+.2f=%.2f" % [advance.get("base", 0.0), advance.get("delta", 0.0), advance.get("final", 0.0)])
	return "; ".join(summaries)

func _update_overlay() -> void:
	if not turn_manager or not grid_manager:
		_overlay.text = "DEBUG: missing battle references"
		return
	var phase_name: String = TurnManager.TurnPhase.keys()[turn_manager.current_phase]
	var lines: Array[String] = [
		"DEBUG  [F3]",
		"Seed %d  |  %s%s" % [battle_controller.battle_seed, grid_manager.map_data.source_kind.to_upper(), " %d" % grid_manager.map_data.generation_seed if grid_manager.map_data.source_kind.begins_with("generated") else ""],
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

func _build_inspection_section(tabs: TabContainer, section: String) -> void:
	var column := VBoxContainer.new()
	column.name = section
	tabs.add_child(column)
	if section == "Tactical":
		_target_picker = OptionButton.new()
		_target_picker.item_selected.connect(_show_target_snapshot)
		column.add_child(_target_picker)
	if section == "Map":
		_manifest_toggle = CheckButton.new()
		_manifest_toggle.text = "Show technical manifest (recorded parcel/population choices)"
		_manifest_toggle.toggled.connect(func(_enabled: bool): _show_map_snapshot())
		column.add_child(_manifest_toggle)
	if section == "Timeline":
		var hint := Label.new()
		hint.text = "Recent AI decisions, newest first. Select one to redraw its heatmap, route arrow and target lines."
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(hint)
		_timeline_list = ItemList.new()
		_timeline_list.name = "DecisionTimeline"
		_timeline_list.custom_minimum_size = Vector2(0, 130)
		_timeline_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_timeline_list.item_selected.connect(_select_timeline_entry)
		column.add_child(_timeline_list)
	var details := RichTextLabel.new()
	details.name = "InspectionText"
	details.selection_enabled = true
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.custom_minimum_size = Vector2(0, 220)
	details.bbcode_enabled = false
	if section == "Timeline":
		details.custom_minimum_size = Vector2(0, 150)
		var mono := SystemFont.new()
		mono.font_names = PackedStringArray(["Consolas", "Courier New", "monospace"])
		details.add_theme_font_override("normal_font", mono)
		details.add_theme_font_size_override("normal_font_size", 13)
		_timeline_details = details
	column.add_child(details)
	_inspection_labels[section] = details

func _layout_panel() -> void:
	if not is_instance_valid(_panel): return
	var viewport_size := get_viewport_rect().size
	_panel.custom_minimum_size = Vector2.ZERO
	_panel.size = Vector2(minf(940, viewport_size.x - 32), minf(650, viewport_size.y - 32))
	_panel.position = (viewport_size - _panel.size) * 0.5

func _capture_inspection() -> void:
	_inspection_invalidated = false
	_inspection_snapshot = DebugInspection.capture(battle_controller, _inspected_destination, not get_tree().paused and not battle_controller.replay_mode)
	_inspection_labels["Unit"].text = _inspection_snapshot.unit
	_target_picker.clear()
	for target in _inspection_snapshot.targets: _target_picker.add_item(target.id)
	_target_picker.disabled = _target_picker.item_count == 0
	if _target_picker.item_count == 0: _target_picker.add_item("No live hostile action query available")
	_show_target_snapshot(0)
	_show_map_snapshot()
	if not _latest_ai_decision.is_empty(): _update_ai_scoring_details(_latest_ai_decision)
	_inspection_labels["AI"].text = ("Latest recorded decision (historical):\n" + _ai_decision_label.text + "\n\n" + _ai_scoring_label.text if not _latest_ai_decision.is_empty() else "No AI decision recorded in this battle yet.") + "\n\n" + _inspection_snapshot.squad
	_inspection_labels["AI"].text = "Latest authoritative AI outcome:\n" + _format_ai_outcome() + "\n\n" + _inspection_labels["AI"].text
	_inspection_labels["Runtime"].text = DebugInspection.runtime_summary()
	_update_inspection_status()

func _show_target_snapshot(index: int) -> void:
	var text := "SHOT · pre-pause query\n"
	var targets: Array = _inspection_snapshot.get("targets", [])
	text += targets[index].text if index >= 0 and index < targets.size() else "No target snapshot. Replay/already-paused inspection does not invent live action legality."
	_inspection_labels["Tactical"].text = text + "\n\nMOVEMENT · hovered destination\n" + _inspection_snapshot.get("movement", "Hover a destination, then open F3.")

func _show_map_snapshot() -> void:
	_inspection_labels["Map"].text = _inspection_snapshot.get("map", "Open F3 to capture map details.") + ("\n\nRecorded technical manifest:\n" + _inspection_snapshot.get("manifest", "") if _manifest_toggle.button_pressed else "\n\nEnable technical manifest for parcel IDs, revisions and population choices.")

func _update_inspection_status() -> void:
	var stale := _inspection_invalidated or not _inspection_snapshot.is_empty() and int(_inspection_snapshot.revision) != battle_controller.action_service.state_revision
	_inspection_status.text = "STALE SNAPSHOT · state changed; close/reopen F3 to refresh." if stale else "Read-only snapshot at F3 open · revision %s · build %.2f ms. Hover a destination before opening. Live monitors are separate." % [_inspection_snapshot.get("revision", "?"), _inspection_snapshot.get("elapsed_ms", 0.0)]

func _exit_tree() -> void:
	if _paused_by_debug_tools and is_inside_tree():
		get_tree().paused = false
	_paused_by_debug_tools = false

func _on_ai_action_outcome(record: Dictionary) -> void:
	_latest_ai_outcome = record.duplicate(true)
	if int(record.get("decision_id", 0)) > 0:
		_decision_outcomes[int(record.decision_id)] = _latest_ai_outcome
		_refresh_timeline()
	if int(record.get("decision_id", 0)) > 0 and record.get("decision_id") == _latest_ai_decision.get("decision_id"):
		_ai_decision_label.text += "\nOutcome: " + _format_ai_outcome()

func _format_ai_outcome() -> String:
	if _latest_ai_outcome.is_empty(): return "None recorded yet"
	var record := _latest_ai_outcome
	var text := "%s · %s · %s\nDecision %s" % [record.actor_id, record.action, String(record.stage).to_upper(), record.get("decision_id", 0)]
	if record.stage == "committed":
		text += " · transaction %s · revision %s → %s" % [record.transaction_id, record.base_revision, record.committed_revision]
	else:
		text += "\n" + String(record.get("reason", "Rejected"))
	return text

# ---- Decision timeline, squad reservations and score bars (read-only visualization) ----

func _build_ai_reservation_overlay() -> void:
	if not presentation_root:
		return
	_ai_reservation_overlay = AIReservationOverlayData.new()
	_ai_reservation_overlay.name = "AIReservationOverlay"
	_ai_reservation_overlay.grid_manager = grid_manager
	presentation_root.add_child.call_deferred(_ai_reservation_overlay)

func _set_ai_reservations_visible(enabled: bool) -> void:
	if _ai_reservation_overlay:
		_ai_reservation_overlay.set_overlay_enabled(enabled)
	_refresh_reservations()

## Both teams' current claims, read from existing contexts. Never creates or resets one.
func _collect_reservations() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not battle_controller or not turn_manager:
		return entries
	for roster in [turn_manager.player_units, turn_manager.enemy_units]:
		var representative: TacticalUnit = null
		for candidate in roster:
			if is_instance_valid(candidate):
				representative = candidate
				break
		var context: SquadContext = battle_controller.peek_squad_context(representative) if representative else null
		if context == null:
			continue
		for cell in context.reserved_destinations:
			entries.append({"cell": cell, "kind": "destination", "owner": String(context.reserved_destinations[cell])})
		for cell in context.reserved_corridor:
			entries.append({"cell": cell, "kind": "corridor", "owner": String(context.corridor_owner)})
		for target_id in context.intended_targets:
			if int(context.intended_targets[target_id]) <= 0:
				continue
			var target := battle_controller.action_service.actor_registry.resolve(target_id)
			if is_instance_valid(target):
				entries.append({"cell": target.grid_position, "kind": "target", "owner": String(target_id)})
	return entries

func _refresh_reservations() -> void:
	if _ai_reservation_overlay and _ai_reservation_overlay.overlay_enabled:
		_ai_reservation_overlay.show_entries(_collect_reservations())

func _timeline_entry_text(record: Dictionary) -> String:
	var outcome: Dictionary = _decision_outcomes.get(int(record.get("decision_id", 0)), {})
	var tag := ""
	if not outcome.is_empty():
		tag = "  [%s]" % String(outcome.get("stage", ""))
	return "#%s  %s · %s %s%s" % [record.get("decision_id", "?"), record.get("actor", "?"), record.get("action", "?"), record.get("subject", ""), tag]

func _refresh_timeline() -> void:
	if _timeline_list == null:
		return
	_timeline_list.clear()
	for index in range(_decision_history.size() - 1, -1, -1):
		var record := _decision_history[index]
		var item := _timeline_list.add_item(_timeline_entry_text(record))
		_timeline_list.set_item_metadata(item, index)
		if record.get("stage", "") == "selected":
			_timeline_list.set_item_custom_fg_color(item, Color(1.0, 0.82, 0.35))

func _select_timeline_entry(item: int) -> void:
	var index: int = _timeline_list.get_item_metadata(item)
	if index < 0 or index >= _decision_history.size():
		return
	var record := _decision_history[index]
	if _ai_scoring_toggle and not _ai_scoring_toggle.button_pressed:
		_ai_scoring_toggle.button_pressed = true
	if _ai_scoring_overlay:
		_ai_scoring_overlay.display(record)
	_update_ai_scoring_details(record)
	_timeline_details.text = _format_decision_detail(record)

## "#####." style bars: filled cells scale with the component's size, "-" marks a penalty.
static func score_bar(value: float, scale_value: float, width := 8) -> String:
	var filled := clampi(roundi(absf(value) / maxf(scale_value, 0.001) * float(width)), 0, width)
	if filled == 0 and absf(value) >= 0.5:
		filled = 1
	return "[" + ((("#" if value >= 0.0 else "-").repeat(filled)).rpad(width, ".")) + "]"

func _format_decision_detail(record: Dictionary) -> String:
	var lines: Array[String] = [
		"%s  #%s  %s %s  (%s, revision %s)" % [record.get("actor", "?"), record.get("decision_id", "?"), record.get("action", "?"), record.get("subject", ""), record.get("stage", "explanation"), record.get("state_revision", "?")],
		"Goal: %s | Commander: %s | %s" % [record.get("mission_goal", "None"), record.get("commander_policy", "-"), record.get("difficulty", "-")],
		"Reason: %s" % record.get("reason", ""),
		"Alternatives: %s" % record.get("alternatives", ""),
	]
	var outcome: Dictionary = _decision_outcomes.get(int(record.get("decision_id", 0)), {})
	if not outcome.is_empty():
		lines.append("Outcome: %s" % ("committed (transaction %s)" % outcome.get("transaction_id", "?") if outcome.get("stage") == "committed" else "REJECTED — %s" % outcome.get("reason", "")))
	var positions: Array = record.get("position_candidates", [])
	var scored: Array = positions.filter(func(c: Dictionary) -> bool: return c.get("status", "") != "rejected" and c.has("score"))
	scored.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.score) > float(b.score))
	if not scored.is_empty():
		var scale_value := 1.0
		for candidate in scored.slice(0, 6):
			for key in ["progress", "cover", "exposure", "firing", "danger", "squad"]:
				scale_value = maxf(scale_value, absf(float(candidate.get(key, 0.0))))
		lines.append("")
		lines.append("MOVES  (bars share one scale; # helps, - hurts)" if String(record.get("action", "")) != "Attack" else "LAST MOVEMENT PLAN  (from earlier this activation; an attack chooses no tile)")
		for candidate in scored.slice(0, 6):
			lines.append("%s %+.1f%s" % [candidate.cell, float(candidate.score), "  <- CHOSEN" if candidate.get("chosen", false) else ""])
			var parts: Array[String] = []
			for key in ["progress", "cover", "exposure", "firing", "danger", "squad"]:
				if candidate.has(key):
					parts.append("%s %+.0f %s" % [key, float(candidate[key]), score_bar(float(candidate[key]), scale_value, 6)])
			if not parts.is_empty(): lines.append("   " + "   ".join(parts))
	var reasons := {}
	for candidate in positions:
		if candidate.get("status", "") == "rejected":
			var why := String(candidate.get("reason", "No score"))
			if why.length() > 60: why = why.substr(0, 60) + "…"
			reasons[why] = int(reasons.get(why, 0)) + 1
	if not reasons.is_empty():
		lines.append("")
		lines.append("REJECTED MOVES")
		for why in reasons:
			lines.append("%4d × %s" % [reasons[why], why])
	var targets: Array = record.get("target_candidates", [])
	if not targets.is_empty():
		lines.append("")
		lines.append("TARGETS")
		for candidate in targets:
			if candidate.get("status", "") == "rejected":
				lines.append("%s REJECTED — %s" % [candidate.get("target", "?"), candidate.get("reason", "")])
			else:
				lines.append("%s %+.1f%s | %s%% x %s dmg = %.1f | %s" % [candidate.get("target", "?"), float(candidate.score), "  <- CHOSEN" if candidate.get("chosen", false) else "", candidate.get("hit_chance", "?"), candidate.get("damage_on_hit", "?"), float(candidate.get("expected_damage", 0.0)), candidate.get("summary", "")])
	lines.append("")
	lines.append("Squad: %s" % record.get("squad_adjustments", "None"))
	return "\n".join(lines)
