class_name EnvironmentAssetPlacement
extends RefCounted

enum Anchor { FLOOR_CENTER, SOURCE_ORIGIN, TOP_CENTER }

## Fixed uniform scale for connected pieces. SOURCE_ORIGIN preserves authored
## seams; TOP_CENTER places thin road/floor surfaces at the requested height.
## None of these visual anchors imply tactical occupancy.
static func instantiate_calibrated(parent: Node3D, asset_path: String,
		anchor_position: Vector3, factor: float, yaw := 0.0,
		anchor := Anchor.FLOOR_CENTER) -> TacticalVisualOccluder:
	if not is_finite(factor) or factor <= 0.0:
		push_warning("Asset scale must be finite and positive")
		return null
	var packed := load(asset_path) as PackedScene
	if not packed:
		return null
	var instance := packed.instantiate()
	if not instance is Node3D:
		instance.free()
		return null
	var native_bounds := mesh_bounds(instance)
	if native_bounds.size.x <= 0.0 or native_bounds.size.y <= 0.0 or native_bounds.size.z <= 0.0:
		instance.free()
		push_warning("Environment asset has no measurable mesh bounds: %s" % asset_path)
		return null
	var rotation_basis := Basis(Vector3.UP, yaw)
	var rotated := Transform3D(rotation_basis, Vector3.ZERO) * native_bounds
	var offset := Vector3.ZERO
	if anchor != Anchor.SOURCE_ORIGIN:
		offset = Vector3(rotated.get_center().x, rotated.position.y, rotated.get_center().z)
		if anchor == Anchor.TOP_CENTER:
			offset.y = rotated.end.y
	var wrapper := TacticalVisualOccluder.new()
	wrapper.name = asset_path.get_file().get_basename()
	wrapper.basis = rotation_basis.scaled(Vector3.ONE * factor)
	wrapper.position = anchor_position - offset * factor
	wrapper.occlusion_bounds = native_bounds
	wrapper.set_meta("asset_path", asset_path)
	wrapper.add_child(instance)
	parent.add_child(wrapper)
	return wrapper

## Presentation-only placement for imported environment scenes. Tactical
## footprint, cover, LOS and traversal remain owned by MapData.
static func instantiate_fitted(
	parent: Node3D,
	asset_path: String,
	floor_center: Vector3,
	limits: Vector3,
	yaw := 0.0
) -> TacticalVisualOccluder:
	var packed := load(asset_path) as PackedScene
	if not packed:
		push_warning("Environment asset could not be loaded: %s" % asset_path)
		return null
	var instance := packed.instantiate() as Node3D
	if not instance:
		push_warning("Environment asset root is not Node3D: %s" % asset_path)
		return null
	var rotation_basis := Basis(Vector3.UP, yaw)
	var bounds := Transform3D(rotation_basis, Vector3.ZERO) * mesh_bounds(instance)
	if bounds.size.x <= 0.0 or bounds.size.y <= 0.0 or bounds.size.z <= 0.0:
		instance.free()
		push_warning("Environment asset has no measurable mesh bounds: %s" % asset_path)
		return null
	var factor := minf(limits.x / bounds.size.x, minf(limits.y / bounds.size.y, limits.z / bounds.size.z))
	var wrapper := TacticalVisualOccluder.new()
	wrapper.name = asset_path.get_file().get_basename()
	wrapper.basis = rotation_basis.scaled(Vector3.ONE * factor)
	wrapper.position = floor_center - Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	wrapper.set_meta("asset_path", asset_path)
	wrapper.set_meta("placement_limits", limits)
	wrapper.set_meta("floor_center", floor_center)
	wrapper.add_child(instance)
	wrapper.occlusion_bounds = mesh_bounds(instance)
	parent.add_child(wrapper)
	return wrapper

## Includes every ancestor transform beneath node, including imported roots.
static func mesh_bounds(node: Node3D, accumulated := Transform3D.IDENTITY) -> AABB:
	var boxes: Array[AABB] = []
	_collect_bounds(node, accumulated, boxes)
	var bounds := AABB()
	for index in boxes.size():
		bounds = boxes[index] if index == 0 else bounds.merge(boxes[index])
	return bounds

static func _collect_bounds(node: Node, accumulated: Transform3D, boxes: Array[AABB]) -> void:
	var transform := accumulated
	if node is Node3D:
		transform = accumulated * node.transform
	if node is MeshInstance3D:
		boxes.append(transform * node.get_aabb())
	for child in node.get_children():
		_collect_bounds(child, transform, boxes)
