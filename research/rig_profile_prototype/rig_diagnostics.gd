extends RefCounted
## Structured result of validating a rig profile against a skeleton: errors stop a capability, warnings degrade it, infos report what was derived. Codes are stable strings so tests and tools
## can match them; messages say what to fix. (Task 05 prototype.)

enum Severity { INFO, WARNING, ERROR }

class Entry extends RefCounted:
	var severity: Severity
	var code: StringName
	var role: StringName
	var message: String
	var hint: String

var entries: Array[Entry] = []

func add(severity: Severity, code: StringName, role: StringName, message: String, hint := "") -> void:
	var entry := Entry.new()
	entry.severity = severity
	entry.code = code
	entry.role = role
	entry.message = message
	entry.hint = hint
	entries.append(entry)

func error(code: StringName, role: StringName, message: String, hint := "") -> void:
	add(Severity.ERROR, code, role, message, hint)

func warn(code: StringName, role: StringName, message: String, hint := "") -> void:
	add(Severity.WARNING, code, role, message, hint)

func info(code: StringName, role: StringName, message: String, hint := "") -> void:
	add(Severity.INFO, code, role, message, hint)

func has_errors() -> bool:
	return not with_severity(Severity.ERROR).is_empty()

func with_severity(severity: Severity) -> Array[Entry]:
	var found: Array[Entry] = []
	for entry in entries:
		if entry.severity == severity:
			found.append(entry)
	return found

func has_code(code: StringName) -> bool:
	for entry in entries:
		if entry.code == code:
			return true
	return false

func codes() -> Array[StringName]:
	var list: Array[StringName] = []
	for entry in entries:
		if entry.code not in list:
			list.append(entry.code)
	return list

func format() -> String:
	var lines: PackedStringArray = []
	for entry in entries:
		var label := "ERROR" if entry.severity == Severity.ERROR else ("warn " if entry.severity == Severity.WARNING else "info ")
		var subject := "" if entry.role == &"" else " [%s]" % entry.role
		lines.append("%s %s%s: %s%s" % [label, entry.code, subject, entry.message, (" (hint: %s)" % entry.hint) if entry.hint != "" else ""])
	return "\n".join(lines)
