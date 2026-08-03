class_name CarVisual
extends Node3D

const BLUE_COLOR := Color8(0, 129, 255)
const ORANGE_COLOR := Color8(255, 111, 0)
const WHEEL_NAMES := [
	&"Dieci - FR (Octane)",
	&"Dieci - FL (Octane)",
	&"Dieci - BR (Octane)",
	&"Dieci - BL (Octane)"
]
const WHEEL_RADII := [0.1165, 0.1165, 0.1338, 0.1338]
const WHEEL_DIRECTIONS := [-1.0, 1.0, -1.0, 1.0]

var physics_state := InterpolatedPhysicsState.new()
var body_material: StandardMaterial3D
var wheels: Array[Node3D] = []
var wheel_base_bases: Array[Basis] = []
var wheel_angles := PackedFloat32Array()
var last_update_time := 0.0

@onready var model: Node3D = $Model

func _ready() -> void:
	var body_mesh := model.find_child("Octane_Octane Body_0", true, false) as MeshInstance3D
	body_material = body_mesh.get_active_material(0).duplicate() as StandardMaterial3D
	body_material.metallic = 0.0
	body_material.roughness = 0.7
	body_material.metallic_specular = 0.25
	body_mesh.material_override = body_material
	wheel_angles.resize(WHEEL_NAMES.size())
	for wheel_name in WHEEL_NAMES:
		var wheel := model.find_child(wheel_name, true, false) as Node3D
		wheels.append(wheel)
		wheel_base_bases.append(wheel.basis)

func push_state(data: Dictionary, received_at: float, receive_interval: float) -> void:
	physics_state.push(data, received_at, receive_interval)

func set_team(team: int) -> void:
	body_material.albedo_color = BLUE_COLOR if team == 0 else ORANGE_COLOR

func update_visual(current_time: float) -> void:
	if not physics_state.has_sample:
		return

	var frame_delta := 0.0 if last_update_time == 0.0 else minf(current_time - last_update_time, 0.05)
	last_update_time = current_time
	var ratio := physics_state.interpolation_ratio(current_time)
	position = RLCoordinates.position_to_godot(physics_state.sample_position(ratio))
	var forward_rl := physics_state.sample_forward(ratio)
	var forward := RLCoordinates.direction_to_godot(forward_rl).normalized()
	var up := RLCoordinates.direction_to_godot(physics_state.sample_up(ratio)).normalized()
	up = (up - forward * forward.dot(up)).normalized()
	var right := forward.cross(up).normalized()
	basis = Basis(forward, up, right).orthonormalized()
	_update_wheels(physics_state.sample_velocity(ratio).dot(forward_rl), frame_delta)

func _update_wheels(forward_speed_rl: float, delta: float) -> void:
	for index in wheels.size():
		var angular_speed: float = forward_speed_rl * RLCoordinates.UNIT_SCALE / float(WHEEL_RADII[index])
		wheel_angles[index] = fmod(wheel_angles[index] + angular_speed * delta * WHEEL_DIRECTIONS[index], TAU)
		wheels[index].basis = wheel_base_bases[index] * Basis(Vector3.UP, wheel_angles[index])
