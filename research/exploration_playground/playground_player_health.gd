class_name PlaygroundPlayerHealth
extends Node
## The player's health, defeat and respawn screen (sandbox package). The red plate on the floor hurts her while she stands on it (so there is something to lose health to); each hit plays the hit reaction; at zero the
## defeat plays and, after a moment, a respawn screen appears (Respawn button or R). Respawning rebuilds her at the spawn point with full health. No gameplay rules: it is only a number and a screen.

const MAX_HEALTH := 100.0
const HAZARD_DAMAGE := 12.0
const HAZARD_INTERVAL := 0.45
const SCREEN_DELAY := 1.8

signal defeated
signal respawned

var ctx: Node
var health := MAX_HEALTH
var bar: ProgressBar
var screen: PanelContainer
var _hazard_clock := 0.0
var _generation := 0


func setup(controller: Node, ui_layer: CanvasLayer) -> void:
	ctx = controller
	bar = ProgressBar.new()
	bar.max_value = MAX_HEALTH
	bar.value = MAX_HEALTH
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(220.0, 16.0)
	bar.position = Vector2(16.0, 92.0)
	ui_layer.add_child(bar)
	screen = PanelContainer.new()
	screen.visible = false
	screen.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var box := VBoxContainer.new()
	var title := Label.new()
	title.text = "You were defeated"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var button := Button.new()
	button.name = "RespawnButton"
	button.text = "Respawn (R)"
	button.pressed.connect(respawn)
	box.add_child(button)
	screen.add_child(box)
	ui_layer.add_child(screen)


func is_dead() -> bool:
	return health <= 0.0


func process(delta: float) -> void:
	if is_dead():
		return
	for plate in ctx.get_tree().get_nodes_in_group(PlaygroundProps.HAZARD_GROUP):
		if (plate as Area3D).overlaps_body(ctx.body):
			_hazard_clock -= delta
			if _hazard_clock <= 0.0:
				_hazard_clock = HAZARD_INTERVAL
				damage(HAZARD_DAMAGE)
			return
	_hazard_clock = 0.0


func damage(amount: float) -> void:
	if is_dead():
		return
	health = maxf(health - amount, 0.0)
	bar.value = health
	if health > 0.0:
		ctx.visual.react_hit()
		return
	ctx.on_player_down()
	defeated.emit()
	var generation := _generation
	await ctx.get_tree().create_timer(SCREEN_DELAY).timeout
	if generation == _generation and is_dead():
		screen.visible = true
		ctx.show_cursor()


func respawn() -> void:
	if not is_dead():
		return
	_generation += 1
	health = MAX_HEALTH
	bar.value = MAX_HEALTH
	screen.visible = false
	ctx.respawn_player()
	respawned.emit()
