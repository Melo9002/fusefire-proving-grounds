class_name FuseFireDebugDraw3D
extends RefCounted
## Project-owned boundary around the vendored Debug Draw 3D GDExtension.
## Gameplay and generation code must not depend on the vendor singleton.

const ADDON_NAME := "Debug Draw 3D"
const ADDON_VERSION := "1.7.3"
const ADDON_PATH := "res://addons/debug_draw_3d/debug_draw_3d.gdextension"

static func is_available() -> bool:
	return ClassDB.class_exists("DebugDraw3D") and Engine.has_singleton("DebugDraw3D")

static func begin_scope(viewport: Viewport = null, no_depth_test := true, thickness := 0.025) -> Object:
	var draw := _singleton()
	if draw == null:
		return null
	var scope: Object = draw.call("new_scoped_config")
	if scope == null:
		return null
	if viewport != null:
		scope.call("set_viewport", viewport)
	scope.call("set_no_depth_test", no_depth_test)
	scope.call("set_thickness", thickness)
	return scope

static func draw_aabb(bounds: AABB, color: Color, duration := 0.0) -> bool:
	var draw := _singleton()
	if draw == null or bounds.size == Vector3.ZERO:
		return false
	draw.call("draw_box", bounds.get_center(), Quaternion.IDENTITY, bounds.size, color, true, duration)
	return true

static func draw_arrow(start: Vector3, finish: Vector3, color: Color, duration := 0.0) -> bool:
	var draw := _singleton()
	if draw == null or start.is_equal_approx(finish):
		return false
	draw.call("draw_arrow", start, finish, color, 0.28, true, duration)
	return true

static func clear_all() -> bool:
	var draw := _singleton()
	if draw == null:
		return false
	draw.call("clear_all")
	return true

static func dependency_record() -> Dictionary:
	return {
		"name": ADDON_NAME,
		"version": ADDON_VERSION,
		"path": ADDON_PATH,
		"license": "MIT",
		"available": is_available(),
	}

static func _singleton() -> Object:
	if not is_available():
		return null
	return Engine.get_singleton("DebugDraw3D")
