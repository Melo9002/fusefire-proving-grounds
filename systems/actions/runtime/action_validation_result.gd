class_name ActionValidationResult
extends RefCounted

var accepted: bool
var code: StringName
var message: String
var current_revision: int

func _init(p_accepted := false, p_code: StringName = &"unknown", p_message := "", p_revision := 0) -> void:
	accepted = p_accepted
	code = p_code
	message = p_message
	current_revision = p_revision

static func allow(revision: int) -> ActionValidationResult:
	return ActionValidationResult.new(true, &"accepted", "", revision)

static func reject(code_value: StringName, message_value: String, revision: int) -> ActionValidationResult:
	return ActionValidationResult.new(false, code_value, message_value, revision)

