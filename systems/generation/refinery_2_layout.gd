class_name Refinery2Layout
extends RefCounted

const SceneMapCompiler = preload("res://systems/generation/authored_scene_map_compiler.gd")

## One authored environment. Scene transforms and explicit tactical volumes are
## the source of truth; no asset calibration, recipe search or random scattering.
const SCENE := preload("res://art/environments/authored/refinery_2.tscn")
const SOURCE_KIND := "authored_refinery_2"

static func generate(map_seed: int, cell_size: float = 1.0) -> MapData:
	var scene := SCENE.instantiate() as Node3D
	var dimensions: Vector2i = scene.get_meta("map_size")
	var data := FlatMapGenerator.generate(dimensions.x, dimensions.y, cell_size, map_seed)
	data.source_kind = SOURCE_KIND
	data.zones.clear()
	SceneMapCompiler.compile(scene, data, cell_size)
	scene.free()
	return data

static func present(parent: Node3D, unit: float) -> void:
	var scene := SCENE.instantiate() as Node3D
	scene.scale = Vector3.ONE * unit
	# Reuse camera occlusion for tall imported scenery, without changing gameplay.
	for child in scene.get_children():
		var volume := child.get_node_or_null("TacticalVolume") as Node3D
		if volume == null:
			continue
		child.set_script(preload("res://presentation/overlays/tactical_visual_occluder.gd"))
		var size: Vector3 = volume.get_meta("solid_size")
		child.set("occlusion_bounds", AABB(volume.position - size * 0.5, size))
	parent.add_child(scene)
