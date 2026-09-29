class_name MatchSetup
extends Control

@export var player_count: SpinBox
@export var enemy_count: SpinBox
@export var ally_count: SpinBox
@export var start_button: Button
@export var generated_map_toggle: CheckButton
@export var auto_seed_toggle: CheckButton
@export var seed_input: SpinBox
@export var map_size_option: OptionButton
@export var battle_scene: PackedScene
var vip_toggle: CheckButton
var vip_behavior: OptionButton
var objective_option: OptionButton
var difficulty_option: OptionButton
var deployment_summary: Label
var compatibility_toggle: CheckButton
var compatibility_status: Label
var _seed_rng := RandomNumberGenerator.new()

const DISPLAY_SETTINGS_PATH := "user://display_settings.cfg"
const COMPATIBILITY_SECTION := "rendering"
const COMPATIBILITY_KEY := "compatibility_mode"
const RESTART_MARKER := "--fusefire-renderer-restart"

func _ready() -> void:
	_build_vip_setup()
	_build_objective_setup()
	_build_compatibility_setup()
	_build_deployment_summary()
	_seed_rng.randomize()
	_prepare_new_seed()
	var size_names := ["Small", "Medium", "Large"]
	for index in FlatMapGenerator.MAP_SIZES.size():
		var dimensions := FlatMapGenerator.MAP_SIZES[index]
		map_size_option.add_item("%s — %d × %d tiles" % [size_names[index], dimensions.x, dimensions.y])
	map_size_option.add_item("Special — Refinery (40 × 30)")
	map_size_option.select(1)
	map_size_option.disabled = not generated_map_toggle.button_pressed
	start_button.pressed.connect(_start_battle)
	player_count.value_changed.connect(_update_summary)
	enemy_count.value_changed.connect(_update_summary)
	ally_count.value_changed.connect(_update_summary)
	generated_map_toggle.toggled.connect(_on_generation_toggled)
	map_size_option.item_selected.connect(func(_index: int): _update_summary(0.0))
	auto_seed_toggle.toggled.connect(_on_auto_seed_toggled)
	seed_input.value_changed.connect(_update_summary)
	_refresh_seed_controls()
	_update_summary(0.0)
	_apply_saved_renderer_preference()

func _build_compatibility_setup() -> void:
	var box := VBoxContainer.new()
	box.name = "CompatibilitySetup"
	compatibility_toggle = CheckButton.new()
	compatibility_toggle.name = "CompatibilityModeToggle"
	compatibility_toggle.text = "INTEL / COMPATIBILITY RENDERER"
	compatibility_toggle.tooltip_text = "Restarts FuseFire with Godot's OpenGL Compatibility renderer. Recommended for Intel integrated graphics or systems that freeze under D3D12."
	compatibility_status = Label.new()
	compatibility_status.name = "CompatibilityStatus"
	compatibility_status.modulate = Color(0.66, 0.76, 0.86)
	compatibility_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(compatibility_toggle)
	box.add_child(compatibility_status)
	var setup_box := $CenterContainer/Panel/Margin/VBox
	setup_box.add_child(box)
	setup_box.move_child(box, setup_box.get_child_count() - 2)
	compatibility_toggle.set_pressed_no_signal(_saved_compatibility_preference())
	compatibility_toggle.toggled.connect(_on_compatibility_toggled)
	_refresh_compatibility_status()

func _saved_compatibility_preference() -> bool:
	var settings := ConfigFile.new()
	if settings.load(DISPLAY_SETTINGS_PATH) != OK:
		return false
	return bool(settings.get_value(COMPATIBILITY_SECTION, COMPATIBILITY_KEY, false))

func _current_renderer() -> String:
	if RenderingServer.has_method("get_current_rendering_method"):
		return String(RenderingServer.call("get_current_rendering_method"))
	var arguments := OS.get_cmdline_args()
	var method_index := arguments.find("--rendering-method")
	if method_index >= 0 and method_index + 1 < arguments.size():
		return String(arguments[method_index + 1])
	return "forward_plus"

func _is_compatibility_renderer() -> bool:
	return _current_renderer() == "gl_compatibility"

func _refresh_compatibility_status(message := "") -> void:
	if not compatibility_status:
		return
	if not message.is_empty():
		compatibility_status.text = message
	elif _is_compatibility_renderer():
		compatibility_status.text = "ACTIVE — OpenGL Compatibility renderer. Safer for Intel integrated graphics."
	else:
		compatibility_status.text = "CURRENT — Forward+ / D3D12. Toggle to restart with the Intel-friendly renderer."

func _apply_saved_renderer_preference() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var wants_compatibility := _saved_compatibility_preference()
	if wants_compatibility == _is_compatibility_renderer():
		return
	# Do not loop forever if a driver or platform rejects the requested renderer.
	if RESTART_MARKER in OS.get_cmdline_user_args():
		_refresh_compatibility_status("Renderer restart did not apply. Start Godot manually with --rendering-method gl_compatibility.")
		return
	_restart_with_renderer(wants_compatibility)

func _on_compatibility_toggled(enabled: bool) -> void:
	var settings := ConfigFile.new()
	settings.load(DISPLAY_SETTINGS_PATH)
	settings.set_value(COMPATIBILITY_SECTION, COMPATIBILITY_KEY, enabled)
	if settings.save(DISPLAY_SETTINGS_PATH) != OK:
		compatibility_toggle.set_pressed_no_signal(not enabled)
		_refresh_compatibility_status("Could not save the renderer preference.")
		return
	_refresh_compatibility_status("Restarting with %s…" % ("Compatibility" if enabled else "Forward+"))
	_restart_with_renderer(enabled)

func _restart_with_renderer(use_compatibility: bool) -> void:
	var arguments: PackedStringArray = []
	if OS.has_feature("editor"):
		arguments.append_array(["--path", ProjectSettings.globalize_path("res://")])
	arguments.append_array(["--rendering-method", "gl_compatibility" if use_compatibility else "forward_plus"])
	arguments.append_array(["--", RESTART_MARKER])
	var process_id := OS.create_process(OS.get_executable_path(), arguments)
	if process_id < 0:
		_refresh_compatibility_status("Could not restart automatically. Close FuseFire and launch it again.")
		return
	get_tree().quit()

func _build_vip_setup() -> void:
	var box := VBoxContainer.new()
	box.name = "VIPSetup"
	vip_toggle = CheckButton.new()
	vip_toggle.text = "INCLUDE ADDITIONAL FRIENDLY VIP"
	vip_toggle.tooltip_text = "Adds one mission actor outside the combatant counters."
	vip_behavior = OptionButton.new()
	vip_behavior.tooltip_text = "Choose who controls the additional VIP."
	for label in ["Player Controlled", "Follow Escort", "Hold Position"]:
		vip_behavior.add_item(label)
	vip_behavior.disabled = true
	vip_toggle.toggled.connect(func(enabled: bool):
		vip_behavior.disabled = not enabled
		ally_count.max_value = 4.0 if enabled else 5.0
		ally_count.value = minf(ally_count.value, ally_count.max_value)
		_update_summary(0.0)
	)
	vip_behavior.item_selected.connect(func(_index: int):
		if vip_toggle.button_pressed and vip_behavior.selected != MissionActor.VIPBehavior.PLAYER_CONTROLLED and player_count.value < 2:
			player_count.value = 2
		_update_summary(0.0)
	)
	box.add_child(vip_toggle)
	box.add_child(vip_behavior)
	$CenterContainer/Panel/Margin/VBox.add_child(box)
	$CenterContainer/Panel/Margin/VBox.move_child(box, 3)

func _build_objective_setup() -> void:
	var box := HBoxContainer.new()
	box.name = "ObjectiveSetup"
	box.add_theme_constant_override("separation", 16)
	var objective_box := VBoxContainer.new()
	objective_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "MISSION OBJECTIVE"
	objective_option = OptionButton.new()
	objective_option.tooltip_text = "Choose the mission rules for this battle."
	for objective_name in MissionCatalog.get_preset_names():
		objective_option.add_item(objective_name)
	objective_option.item_selected.connect(_on_objective_selected)
	objective_box.add_child(label)
	objective_box.add_child(objective_option)
	box.add_child(objective_box)
	var difficulty_box := VBoxContainer.new()
	difficulty_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var difficulty_label := Label.new()
	difficulty_label.text = "AI DIFFICULTY"
	difficulty_option = OptionButton.new()
	difficulty_option.tooltip_text = "Changes AI decisions for both teams; combat rules and AP stay the same."
	for tier in AIDifficultyPolicy.Tier.size():
		difficulty_option.add_item(AIDifficultyPolicy.get_label(tier))
	difficulty_option.select(AIDifficultyPolicy.Tier.NORMAL)
	difficulty_box.add_child(difficulty_label)
	difficulty_box.add_child(difficulty_option)
	box.add_child(difficulty_box)
	$CenterContainer/Panel/Margin/VBox.add_child(box)
	$CenterContainer/Panel/Margin/VBox.move_child(box, 4)

func _build_deployment_summary() -> void:
	deployment_summary = Label.new()
	deployment_summary.name = "DeploymentSummary"
	deployment_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	deployment_summary.add_theme_color_override("font_color", Color(0.55, 0.86, 1.0))
	var box := $CenterContainer/Panel/Margin/VBox
	box.add_child(deployment_summary)
	box.move_child(deployment_summary, box.get_child_count() - 2)

func _on_objective_selected(index: int) -> void:
	var needs_vip := index == MissionObjectiveDefinition.Kind.PROTECT
	vip_toggle.disabled = needs_vip
	if needs_vip:
		vip_toggle.button_pressed = true
	_update_summary(0.0)

func _update_summary(_value: float) -> void:
	var map_label := "REFINERY" if generated_map_toggle.button_pressed and map_size_option.selected == 3 else ("GENERATED" if generated_map_toggle.button_pressed else "HANDMADE")
	var objective_label := MissionCatalog.get_preset_names()[objective_option.selected] if objective_option else "Eliminate"
	var has_vip := vip_toggle != null and vip_toggle.button_pressed
	var player_vip := 1 if has_vip and vip_behavior.selected == MissionActor.VIPBehavior.PLAYER_CONTROLLED else 0
	var ai_vip := 1 if has_vip and vip_behavior.selected != MissionActor.VIPBehavior.PLAYER_CONTROLLED else 0
	var player_controlled := int(player_count.value) + player_vip
	var ai_controlled := int(ally_count.value) + ai_vip
	var friendly_total := player_controlled + ai_controlled
	if deployment_summary:
		deployment_summary.text = "DEPLOYMENT — Player-controlled: %d | AI allies: %d | Enemies: %d\nTotal friendly actors: %d%s" % [player_controlled, ai_controlled, int(enemy_count.value), friendly_total, " (includes 1 additional VIP)" if has_vip else ""]
	start_button.text = "START %d FRIENDLY VS %d ENEMIES — %s — %s — SEED %d" % [friendly_total, int(enemy_count.value), map_label, objective_label.to_upper(), int(seed_input.value)]

func _on_generation_toggled(enabled: bool) -> void:
	map_size_option.disabled = not enabled
	_refresh_seed_controls()
	_update_summary(0.0)

func _on_auto_seed_toggled(enabled: bool) -> void:
	if enabled:
		_prepare_new_seed()
	_refresh_seed_controls()

func _prepare_new_seed() -> void:
	seed_input.value = _seed_rng.randi_range(1, int(seed_input.max_value))


func _refresh_seed_controls() -> void:
	auto_seed_toggle.disabled = false
	seed_input.editable = not auto_seed_toggle.button_pressed

func _start_battle() -> void:
	var battle = battle_scene.instantiate() as BattleLevel
	battle.configure(
		int(player_count.value),
		int(enemy_count.value),
		generated_map_toggle.button_pressed,
		int(seed_input.value),
		int(ally_count.value),
		Vector2i(40, 30) if map_size_option.selected == 3 else FlatMapGenerator.MAP_SIZES[map_size_option.selected],
		vip_toggle.button_pressed,
		vip_behavior.selected,
		MissionCatalog.create_mission(objective_option.selected, int(enemy_count.value), vip_toggle.button_pressed),
		difficulty_option.selected,
		map_size_option.selected == 3
	)
	get_tree().root.add_child(battle)
	get_tree().current_scene = battle
	queue_free()
