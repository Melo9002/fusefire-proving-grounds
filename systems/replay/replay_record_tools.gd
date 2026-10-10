class_name ReplayRecordTools
extends RefCounted

## Small, explicit helpers shared by replay serializers, tests, and playback.
## Keeping this dictionary-shaped makes saved records easy to inspect by hand.

static func compare_fields(expected: Dictionary, actual: Dictionary, path := "") -> String:
	var keys: Array = expected.keys()
	keys.sort_custom(func(a, b): return String(a) < String(b))
	for key in keys:
		var field_path := "%s.%s" % [path, key] if not path.is_empty() else String(key)
		if not actual.has(key):
			return "%s is missing (expected %s)" % [field_path, expected[key]]
		var expected_value = expected[key]
		var actual_value = actual[key]
		if expected_value is Dictionary and actual_value is Dictionary:
			var nested := compare_fields(expected_value, actual_value, field_path)
			if not nested.is_empty(): return nested
		elif expected_value != actual_value:
			return "%s differs: expected %s, got %s" % [field_path, expected_value, actual_value]
	return ""

static func validate_action_record(record: Dictionary, envelope_version: int) -> String:
	for field in ["kind", "actor", "expected_state"]:
		if not record.has(field): return "missing required field '%s'" % field
	if envelope_version >= 3:
		for field in ["record_index", "schema_version", "transaction_id", "base_revision", "committed_revision"]:
			if not record.has(field): return "missing required field '%s'" % field
		if record.get("kind", "") not in ["end_turn", "depart"]:
			if not record.has("request") or not record.has("resolved"):
				return "tactical action is missing request or resolved result"
			var payload_version := int(record.get("schema_version", -1))
			var kind := String(record.get("kind", ""))
			if kind == "attack" and payload_version not in [2, 3, 4]:
				return "unsupported Attack payload schema %s (expected 2, 3, or 4)" % payload_version
			if kind == "reload" and payload_version != 3:
				return "unsupported Reload payload schema %s (expected 3)" % payload_version
			if kind == "aim" and payload_version != 4:
				return "unsupported Aim payload schema %s (expected 4)" % payload_version
			if kind not in ["attack", "reload", "aim"] and payload_version != 2:
				return "unsupported action payload schema %s (expected 2)" % payload_version
			if int(record.get("request", {}).get("schema_version", -1)) != TacticalActionRequest.SCHEMA_VERSION:
				return "unsupported request payload schema %s (expected %d)" % [record.get("request", {}).get("schema_version"), TacticalActionRequest.SCHEMA_VERSION]
		elif int(record.get("schema_version", -1)) != 1:
			return "unsupported command payload schema %s (expected 1)" % record.get("schema_version")
	return ""

static func context(index: int, record: Dictionary) -> String:
	return "record %d kind=%s tx=%s revision=%s->%s actor=%s target=%s" % [
		index,
		record.get("kind", "unknown"),
		record.get("transaction_id", "?"),
		record.get("base_revision", "?"),
		record.get("committed_revision", "?"),
		record.get("actor", ""),
		record.get("target", ""),
	]
