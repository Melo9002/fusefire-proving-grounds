extends Node3D
var tag := ""
var sink: Array = []
func _physics_process(_d: float) -> void:
	sink.append("physics:" + tag)
func _process(_d: float) -> void:
	sink.append("process:" + tag)
