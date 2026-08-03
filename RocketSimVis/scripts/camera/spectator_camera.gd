class_name SpectatorCamera
extends Camera3D

@export var target: Node3D
@export var car_target: Node3D
@export_category("Bird Camera")
@export var bird_position_rl := Vector3(-4000.0, 0.0, 1000.0)
@export_range(20.0, 120.0) var bird_fov := 60.0
@export_category("Player Camera")
@export_range(100.0, 500.0) var player_distance_rl := 300.0
@export_range(0.0, 300.0) var player_height_rl := 120.0
@export_range(20.0, 120.0) var player_fov := 90.0
@export_range(0.0, 1.0) var lean_height_scale := 1.0
@export_range(0.0, 1.0) var lean_distance_scale := 0.1
@export_range(0.0, 500.0) var lean_min_height_rl := 300.0

func _ready() -> void:
	near = 0.001
	far = 500.0
	_update_view()

func _process(_delta: float) -> void:
	_update_view()

func _update_view() -> void:
	if not is_instance_valid(target):
		return
	if is_instance_valid(car_target):
		_update_player_view()
	else:
		position = RLCoordinates.position_to_godot(bird_position_rl)
		fov = bird_fov
		look_at(target.global_position, Vector3.UP)

func _update_player_view() -> void:
	var car_position := car_target.global_position
	var ball_delta := target.global_position - car_position
	var ball_direction := ball_delta.normalized() if not ball_delta.is_zero_approx() else Vector3.FORWARD
	var horizontal_direction := Vector3(ball_direction.x, 0.0, ball_direction.z)
	if horizontal_direction.is_zero_approx():
		horizontal_direction = Vector3.FORWARD
	else:
		horizontal_direction = horizontal_direction.normalized()

	var height := player_height_rl * RLCoordinates.UNIT_SCALE
	var distance := player_distance_rl * RLCoordinates.UNIT_SCALE
	var lean_scale := ball_direction.y
	if lean_scale > 0.0:
		var minimum_height := maxf(lean_min_height_rl * RLCoordinates.UNIT_SCALE, 0.000001)
		var height_clamp := absf(ball_delta.y) / minimum_height
		height *= 1.0 - minf(lean_scale * lean_height_scale, height_clamp)
		distance *= 1.0 - lean_scale * lean_distance_scale

	var offset := -horizontal_direction * distance
	offset.y += height
	position = car_position + offset.normalized() * distance
	fov = player_fov
	look_at(target.global_position, Vector3.UP)
