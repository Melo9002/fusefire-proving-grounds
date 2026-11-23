class_name WorkbenchSession
extends RefCounted
## What the next workbench launch should look like. A scene reload is the workbench's one reliable "full reset" (it also switches the character, whose rig builds itself once), so the choice made in the panel is kept
## here, in static variables that outlive the reload, and read by the workbench before its rig builds. Command-line user arguments (`--character=<key>`, `--unarmed`, `--scenario=<id>`) set the same things.

## The product name. AniLab is the animation framework; ADDA (AniLab Diagnostic & Debugging Assistant) is its diagnostic and debugging suite; this scene is ADDA's Workbench. Paths, scene names and command lines
## keep their old names (pose_workbench.tscn) on purpose: only what a person reads says ADDA.
const PRODUCT := "ADDA — Workbench"
const PRODUCT_LONG := "ADDA — AniLab Diagnostic & Debugging Assistant: Workbench"

static var character: StringName = &""
static var armed := true
static var autostart_scenario: StringName = &""
static var start_tab := -1

## Reads the command line (after `--`). Call once, before the rig builds.
static func read_arguments() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--character="):
			character = StringName(argument.trim_prefix("--character="))
		elif argument == "--unarmed":
			armed = false
		elif argument.begins_with("--scenario="):
			autostart_scenario = StringName(argument.trim_prefix("--scenario="))
		elif argument.begins_with("--tab="):
			start_tab = int(argument.trim_prefix("--tab="))

## The command line that reproduces the current configuration (for the Evidence tab).
static func repro_command(scenario: StringName = &"") -> String:
	var parts: Array[String] = ["godot --path . res://tools/animation_workbench/pose_workbench.tscn --"]
	if character != &"":
		parts.append("--character=%s" % character)
	if not armed:
		parts.append("--unarmed")
	if scenario != &"":
		parts.append("--scenario=%s" % scenario)
	return " ".join(parts)
