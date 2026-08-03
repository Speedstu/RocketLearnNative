class_name InterpolatedPhysicsState
extends RefCounted

const TELEPORT_DISTANCE_RL := 900.0

var previous_position_rl := Vector3.ZERO
var next_position_rl := Vector3.ZERO
var previous_forward_rl := Vector3.RIGHT
var next_forward_rl := Vector3.RIGHT
var previous_up_rl := Vector3.UP
var next_up_rl := Vector3.UP
var previous_velocity_rl := Vector3.ZERO
var next_velocity_rl := Vector3.ZERO
var angular_velocity_rl := Vector3.ZERO
var received_at := 0.0
var receive_interval := 1.0 / 120.0
var has_sample := false
var has_rotation := false

func push(data: Dictionary, packet_time: float, packet_interval: float) -> void:
	var position := _read_vector(data.get("pos", []), next_position_rl)
	var forward := _read_vector(data.get("forward", []), next_forward_rl)
	var up := _read_vector(data.get("up", []), next_up_rl)
	var velocity := _read_vector(data.get("vel", []), next_velocity_rl)
	angular_velocity_rl = _read_vector(data.get("ang_vel", []), Vector3.ZERO)
	has_rotation = data.has("forward") and data.has("up")

	if not has_sample:
		previous_position_rl = position
		next_position_rl = position
		previous_forward_rl = forward
		next_forward_rl = forward
		previous_up_rl = up
		next_up_rl = up
		previous_velocity_rl = velocity
		next_velocity_rl = velocity
		has_sample = true
	else:
		previous_position_rl = next_position_rl
		next_position_rl = position
		previous_forward_rl = next_forward_rl
		next_forward_rl = forward
		previous_up_rl = next_up_rl
		next_up_rl = up
		previous_velocity_rl = next_velocity_rl
		next_velocity_rl = velocity

	received_at = packet_time
	receive_interval = max(packet_interval, 0.000001)

func interpolation_ratio(current_time: float) -> float:
	return clampf((current_time - received_at) / receive_interval, 0.0, 1.0)

func sample_position(ratio: float) -> Vector3:
	if _is_teleporting():
		return previous_position_rl
	return previous_position_rl.lerp(next_position_rl, ratio)

func sample_forward(ratio: float) -> Vector3:
	return _sample_direction(previous_forward_rl, next_forward_rl, ratio, Vector3.RIGHT)

func sample_up(ratio: float) -> Vector3:
	return _sample_direction(previous_up_rl, next_up_rl, ratio, Vector3.UP)

func sample_velocity(ratio: float) -> Vector3:
	return previous_velocity_rl.lerp(next_velocity_rl, ratio)

func _is_teleporting() -> bool:
	return previous_position_rl.distance_squared_to(next_position_rl) >= TELEPORT_DISTANCE_RL * TELEPORT_DISTANCE_RL

func _sample_direction(previous: Vector3, next: Vector3, ratio: float, fallback: Vector3) -> Vector3:
	var direction := previous if _is_teleporting() else previous.lerp(next, ratio)
	return fallback if direction.is_zero_approx() else direction.normalized()

func _read_vector(value: Variant, fallback: Vector3) -> Vector3:
	if value is Array and value.size() >= 3:
		return Vector3(float(value[0]), float(value[1]), float(value[2]))
	return fallback
