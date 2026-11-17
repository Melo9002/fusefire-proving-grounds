class_name MovementGhost
extends Node3D
## Same presentation rig/clips and destination cover rules; no TacticalUnit or actions.
const FallbackVisual := preload("res://art/characters/mira_0/runtime/mira_0_unit_visual.tscn")
var model: UnitVisualAdapter
var source_id := 0
var destination := Vector3.ZERO

func show_destination(actor: TacticalUnit, cell: Vector3i, grid: GridManager) -> void:
	if not is_instance_valid(actor.visual_adapter):
		clear()
		return
	var source := actor.visual_adapter
	if source_id != actor.get_instance_id() or not is_instance_valid(model) or model.preview_carrying != actor.is_carrying_unit():
		clear()
		source_id = actor.get_instance_id()
		var scene: PackedScene = load(source.scene_file_path) if not source.scene_file_path.is_empty() else FallbackVisual
		model = scene.instantiate() as UnitVisualAdapter
		# Share authored assets/calibration; never clone the live unit or its stats.
		for property in source.get_property_list():
			if property.usage & PROPERTY_USAGE_STORAGE and property.usage & PROPERTY_USAGE_EDITOR and property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
				model.set(property.name, source.get(property.name))
		model.presentation_grid = grid
		model.preview_cell = cell
		model.preview_carrying = actor.is_carrying_unit()
		add_child(model)
		if model.preview_carrying: model.present_pickup()
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.25, 0.85, 1.0, 0.3)
		_tint(model, material)
	destination = grid.grid_to_world(cell)
	model.preview_cell = cell
	model.global_transform = source.global_transform
	model.global_position += destination - (actor.global_position - Vector3.UP * actor.standing_height)
	# This is the same arrival/idle selection used by the real unit, including cover.
	model.present_idle()
	show()

func _tint(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
		node.material_overlay = null
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		if child is CollisionObject3D or child is Control:
			child.free()
		else: _tint(child, material)

func clear() -> void:
	if is_instance_valid(model): model.free()
	model = null
	source_id = 0
	hide()
