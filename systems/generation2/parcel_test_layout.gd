class_name ParcelTestLayout
extends RefCounted
## A single authored parcel exercised through the same plot resolver/compiler.
## This is a local test layout, not another generator or published-map catalog.
const Definition = preload("res://systems/generation2/authored_parcel_definition.gd")
const Resolver = preload("res://systems/generation2/authored_plot_resolver.gd")
const Layout = preload("res://systems/generation2/authored_battlefield_layout.gd")
const Content = preload("res://systems/generation2/local_parcel_content.gd")
const SOURCE := "authored_parcel_test"
const PLOT := &"parcel_editor_test"
var parcel: AuthoredParcelDefinition

class Plot:
	var parcel: AuthoredParcelDefinition
	func _init(value): parcel = value
	func choose(_seed: int) -> Dictionary: return get_definition(PLOT)
	func get_definition(id: StringName) -> Dictionary:
		if id != PLOT: return {}
		var connection := parcel.connection()
		return {"plot_id": PLOT, "revision": 1, "map_size": parcel.size, "scene": null, "slots": [{
			"slot_id": &"parcel", "role": parcel.role, "size": parcel.size, "origin": Vector3i.ZERO, "rotation": 0,
			"preferred_parcel_id": parcel.parcel_id, "required_interface": {"kind": connection.kind, "cell": connection.cell, "outward": connection.outward, "width": connection.width, "external": true},
		}]}

func _init(value): parcel = value
func get_definition(id: StringName): return parcel if id == parcel.parcel_id else null

func resolve(map_seed: int, requested: Dictionary = {}) -> Dictionary:
	return Resolver.resolve(Plot.new(parcel), map_seed, bool(requested.get("population_enabled", true)), requested, self)

static func from_content(content: Dictionary) -> Dictionary:
	var loaded := Content.open_scene(content)
	if loaded.has("error"): return loaded
	var node: Node = loaded.scene.instantiate()
	if not node is Node3D:
		node.free()
		return {"error": "INVALID_LOCAL_PARCEL_ROOT"}
	var root := node as Node3D
	var definition := Definition.new(root.get_meta("parcel_id", &""), "Local parcel test", root.get_meta("parcel_role", &""), int(root.get_meta("revision", 0)), root.get_meta("parcel_size", Vector2i.ZERO), loaded.scene)
	root.free()
	var failures := definition.validate()
	if not failures.is_empty(): return {"error": "INVALID_LOCAL_PARCEL: " + "; ".join(failures)}
	return {"layout": ParcelTestLayout.new(definition)}

static func generate(map_seed: int, unit: float, requested: Dictionary) -> MapData:
	var loaded := from_content(requested.get("local_content", {}))
	if loaded.has("error"):
		var failed := MapData.new()
		failed.generation_errors.append({"code": "LOCAL_PARCEL_CONTENT", "detail": loaded.error})
		return failed
	var layout = loaded.layout
	var resolved: Dictionary = layout.resolve(map_seed, requested)
	resolved.local_content = requested.local_content.duplicate(true)
	return Layout.compile_resolved(resolved, map_seed, unit, SOURCE, 0, layout)

static func present(data: MapData, parent: Node3D, unit: float, environment: WorldEnvironment) -> bool:
	var loaded := from_content(data.content_manifest.get("local_content", {}))
	if loaded.has("error"): return false
	var resolved: Dictionary = loaded.layout.resolve(data.generation_seed, data.content_manifest)
	if not Resolver.is_valid(resolved) or resolved.placements != data.content_manifest.placements: return false
	return Layout.present_resolved(data, parent, unit, null, environment, loaded.layout)
