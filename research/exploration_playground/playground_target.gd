class_name PlaygroundTarget
extends Node3D
## A mannequin to shoot at (sandbox): an unarmed MIRA standing still under the exploration host, with a health bar. A hit lowers the bar and plays the hit reaction; at zero it plays its takedown and, a few seconds
## later, is rebuilt standing with full health. Nothing here is gameplay: no AP, no turns, no damage rules beyond this number.

const HOST := preload("res://art/characters/mira_0/runtime/mira_0_exploration_visual.tscn")
const MAX_HEALTH := 100.0
const RESPAWN_SECONDS := 3.0

var health := MAX_HEALTH
var host: ExplorationCharacterHost
var bar: PlaygroundHealthBar
var facing_yaw := 0.0
var _generation := 0


func _ready() -> void:
	var collider_body := StaticBody3D.new()
	collider_body.name = "TargetBody"
	collider_body.set_meta(&"target", self)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.85, 0.0)
	collider_body.add_child(shape)
	add_child(collider_body)
	bar = PlaygroundHealthBar.new()
	bar.position = Vector3(0.0, 2.15, 0.0)
	add_child(bar)
	_stand()


func _stand() -> void:
	_generation += 1
	if is_instance_valid(host):
		remove_child(host)
		host.free()
	host = HOST.instantiate()
	host.rig.weapon_scene = null   # a mannequin: no rifle
	host.rig.rotation.y = facing_yaw
	add_child(host)
	health = MAX_HEALTH
	bar.set_fraction(1.0)


func is_down() -> bool:
	return health <= 0.0


## A hit for `damage`: the bar goes down and the reaction plays; at zero the takedown plays and the mannequin is rebuilt a few seconds later.
func take_hit(damage: float) -> void:
	if is_down():
		return
	health = maxf(health - damage, 0.0)
	bar.set_fraction(health / MAX_HEALTH)
	if health <= 0.0:
		host.defeat()
		var generation := _generation
		await get_tree().create_timer(RESPAWN_SECONDS).timeout
		if is_inside_tree() and generation == _generation:
			_stand()
	else:
		host.react_hit()
