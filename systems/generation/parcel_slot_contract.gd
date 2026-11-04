class_name ParcelSlotContract
extends RefCounted
## Shared exact compatibility check between one authored plot slot and one
## registered parcel. Selection policy remains owned by each bounded family.

static func validate(slot: Dictionary, parcel) -> String:
	if parcel == null or parcel.role != slot.role or parcel.size != slot.size:
		return "INCOMPATIBLE_PARCEL_ROLE_OR_SIZE"
	if not parcel.allowed_rotations().has(int(slot.rotation)):
		return "UNSUPPORTED_PARCEL_ROTATION"
	var offered = parcel.connection()
	var required: Dictionary = slot.required_interface
	if offered == null or offered.kind != StringName(required.kind) or offered.width != int(required.width):
		return "INCOMPATIBLE_PARCEL_INTERFACE"
	if offered.world_cell(parcel.size, slot.origin, slot.rotation) != required.cell:
		return "MISALIGNED_PARCEL_INTERFACE"
	if offered.world_outward(slot.rotation) != required.outward:
		return "MISORIENTED_PARCEL_INTERFACE"
	return ""
