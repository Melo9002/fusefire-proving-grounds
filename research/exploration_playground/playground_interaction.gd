class_name PlaygroundInteraction
extends RefCounted
## What E does right now, as one value (sandbox package): the prompt the player reads and the action E runs come from the same decision, so one cannot advertise what the other does not do. `kind` is the action
## (`pick_up`, `put_down`, `inspect`) or `info`/`none` (text only: nothing happens on E).

var kind: StringName = &"none"
var prompt := ""
var target: Variant


static func none() -> PlaygroundInteraction:
	return PlaygroundInteraction.new()


static func info(text: String) -> PlaygroundInteraction:
	var result := PlaygroundInteraction.new()
	result.kind = &"info"
	result.prompt = text
	return result


static func action(action_kind: StringName, text: String, action_target: Variant = null) -> PlaygroundInteraction:
	var result := PlaygroundInteraction.new()
	result.kind = action_kind
	result.prompt = text
	result.target = action_target
	return result


func is_action() -> bool:
	return kind != &"none" and kind != &"info"
