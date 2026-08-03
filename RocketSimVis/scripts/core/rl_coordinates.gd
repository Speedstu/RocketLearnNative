class_name RLCoordinates
extends RefCounted

const UNIT_SCALE := 0.01

static func position_to_godot(position: Vector3) -> Vector3:
	return Vector3(position.x, position.z, -position.y) * UNIT_SCALE

static func direction_to_godot(direction: Vector3) -> Vector3:
	return Vector3(direction.x, direction.z, -direction.y)

