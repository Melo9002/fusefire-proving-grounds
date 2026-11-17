extends SceneTree
## Explicit-only runner probe: an unhandled error must fail even with exit zero.
func _initialize() -> void:
	_fail.call_deferred()
	_finish.call_deferred()

func _fail() -> void:
	var missing: Variant = null
	missing.intentionally_missing_method()

func _finish() -> void:
	quit(0)
