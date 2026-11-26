extends RefCounted
## Metadata selection shared by geometry consumers without loading map compilation.
const REVISION := 7

static func is_active_solid(node: Node, revision := REVISION) -> bool:
	return node.has_meta("solid_size") and int(node.get_meta("min_shape_revision", 1)) <= revision and int(node.get_meta("max_shape_revision", REVISION)) >= revision
