class_name WorkbenchPanel
extends PanelContainer
## The workbench's control panel: four tabs for the four questions a developer asks, docked to the right edge and full height so it never covers the character (the workbench shifts its 3D view by the panel's width).
##   Character    what character and rig am I inspecting?      identity, roles, capabilities, compatibility, switching
##   Scenario     what am I asking this character to do?       scenario presets with pause/step/reset, then the manual controls
##   Diagnostics  what is the animation system actually doing? live state and history, pose stages, contact and trail overlays
##   Evidence     how do I reproduce, measure and communicate?  screenshot, JSON report, recording, repro command
## Each tab is its own script (ui/*_tab.gd). F1 hides or shows the panel. It only calls the workbench's public controls and the read-only diagnostics.

const MAX_WIDTH := 460.0
const MIN_WIDTH := 300.0
const WINDOW_FRACTION := 0.40

var bench: Node3D
var tabs: TabContainer
var tab_nodes: Array[Control] = []
var _refresh_left := 0.0

func setup(workbench: Node3D) -> void:
	bench = workbench
	name = "WorkbenchPanel"
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_top = 8.0
	offset_bottom = -8.0
	offset_right = -8.0
	var background := StyleBoxFlat.new()   # nearly opaque: the 3D scene must not show through the text
	background.bg_color = Color(0.06, 0.08, 0.11, 0.95)
	background.set_content_margin_all(4)
	add_theme_stylebox_override("panel", background)
	tabs = TabContainer.new()
	tabs.name = "Tabs"
	add_child(tabs)
	for entry in [["Character", CharacterTab.new()], ["Scenario", ScenarioTab.new()], ["Diagnostics", DiagnosticsTab.new()], ["Evidence", EvidenceTab.new()]]:
		var body := WorkbenchUI.scroll_body()
		body[1].add_child(entry[1])
		entry[1].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		body[0].name = entry[0]
		tabs.add_child(body[0])
		tab_nodes.append(entry[1])
		entry[1].setup(bench)
	if WorkbenchSession.start_tab >= 0 and WorkbenchSession.start_tab < tabs.get_tab_count():
		tabs.current_tab = WorkbenchSession.start_tab
	_fit()

## The width the panel occupies on screen (0 when hidden): the 3D view is centred in what is left.
func occupied_width() -> float:
	return size.x + 8.0 if visible else 0.0

func _fit() -> void:
	var window := get_viewport().get_visible_rect().size
	var width := clampf(window.x * WINDOW_FRACTION, MIN_WIDTH, MAX_WIDTH)
	offset_left = -width - 8.0

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		visible = not visible
		get_viewport().set_input_as_handled()

## Every control that mirrors a workbench setting re-reads it (a scenario may have switched a diagnostic on).
func sync_toggles() -> void:
	for tab in tab_nodes:
		if tab.has_method("sync"):
			tab.sync()

func _process(delta: float) -> void:
	_fit()
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = 0.1   # ten readouts a second are plenty to read, and cost little
	var current := tab_nodes[tabs.current_tab]
	if current.has_method("refresh"):
		current.refresh()
