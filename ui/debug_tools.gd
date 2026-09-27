class_name DebugTools
extends Control

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
var _show_ai_decisions: bool = true
var _latest_ai_decision: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	battle_controller.ai_decision_recorded.connect(_on_ai_decision_recorded)
	visible = debug_tools_enabled and not battle_controller.replay_mode
	_set_shot_trajectories_visible(debug_tools_enabled)
	if debug_tools_enabled:
		_set_overlay_visible(overlay_visible_at_start)

func _process(_delta: float) -> void:
	if debug_tools_enabled and _overlay.visible:
		_update_overlay()

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

	_panel = PanelContainer.new()
	_panel.name = "DebugPanel"
	_panel.position = Vector2(380, 110)
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

	_manual_enemy_toggle = CheckButton.new()
	_manual_enemy_toggle.text = "Manual enemy control"
	_manual_enemy_toggle.toggled.connect(set_manual_enemy_control)
	content.add_child(_manual_enemy_toggle)

	_auto_battle_toggle = CheckButton.new()
	_auto_battle_toggle.text = "AI controls both teams"
	_auto_battle_toggle.toggled.connect(set_auto_battle)
	content.add_child(_auto_battle_toggle)

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

func _on_ai_decision_recorded(record: Dictionary) -> void:
	_latest_ai_decision = record
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
