extends Node3D

const CAR_SCENE := preload("res://scenes/entities/car.tscn")

var ball_state := InterpolatedPhysicsState.new()
var car_visuals: Array[CarVisual] = []

@onready var receiver: RocketSimReceiver = $RocketSimReceiver
@onready var ball: Node3D = $Ball
@onready var cars: Node3D = $Cars
@onready var camera: SpectatorCamera = $SpectatorCamera
@onready var boost_pads: BoostPadLayout = $BoostPads

func _ready() -> void:
	receiver.packet_received.connect(_on_packet_received)

func _process(delta: float) -> void:
	var current_time := Time.get_ticks_usec() / 1000000.0
	if ball_state.has_sample:
		var ratio := ball_state.interpolation_ratio(current_time)
		ball.position = RLCoordinates.position_to_godot(ball_state.sample_position(ratio))
		_update_ball_rotation(delta)

	for car_visual in car_visuals:
		if car_visual != null:
			car_visual.update_visual(current_time)

func _on_packet_received(data: Dictionary, received_at: float, receive_interval: float) -> void:
	var ball_data: Variant = data.get("ball_phys")
	var car_data: Variant = data.get("cars", [])
	var boost_pad_data: Variant = data.get("boost_pad_states", data.get("boost_pads", []))
	if ball_data is Dictionary:
		ball_state.push(ball_data, received_at, receive_interval)
	if car_data is Array:
		_sync_cars(car_data, received_at, receive_interval)
	if boost_pad_data is Array:
		boost_pads.set_states(boost_pad_data)

func _sync_cars(states: Array, received_at: float, receive_interval: float) -> void:
	while car_visuals.size() < states.size():
		var instance := CAR_SCENE.instantiate()
		if instance is not CarVisual:
			instance.queue_free()
			return
		var car_visual := instance as CarVisual
		cars.add_child(car_visual)
		car_visuals.append(car_visual)

	while car_visuals.size() > states.size():
		var car_visual: CarVisual = car_visuals.pop_back()
		car_visual.queue_free()

	for index in states.size():
		var state: Variant = states[index]
		if state is not Dictionary:
			continue
		var car_visual := car_visuals[index]
		if car_visual == null:
			continue
		car_visual.set_team(int(state.get("team_num", 0)))
		car_visual.visible = not bool(state.get("is_demoed", false))
		var physics: Variant = state.get("phys")
		if physics is Dictionary:
			car_visual.push_state(physics, received_at, receive_interval)

	camera.car_target = car_visuals[0] if not car_visuals.is_empty() else null

func _update_ball_rotation(delta: float) -> void:
	if ball_state.has_rotation:
		var ratio := ball_state.interpolation_ratio(Time.get_ticks_usec() / 1000000.0)
		var forward := RLCoordinates.direction_to_godot(ball_state.sample_forward(ratio)).normalized()
		var up := RLCoordinates.direction_to_godot(ball_state.sample_up(ratio)).normalized()
		up = (up - forward * forward.dot(up)).normalized()
		ball.basis = Basis(forward.cross(up).normalized(), up, -forward).orthonormalized()
		return

	var angular_velocity := RLCoordinates.direction_to_godot(ball_state.angular_velocity_rl)
	var angle := angular_velocity.length() * delta
	if angle > 0.000001:
		ball.quaternion = (Quaternion(angular_velocity.normalized(), angle) * ball.quaternion).normalized()
