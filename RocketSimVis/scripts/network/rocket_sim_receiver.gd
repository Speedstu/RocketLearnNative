class_name RocketSimReceiver
extends Node

signal packet_received(data: Dictionary, received_at: float, receive_interval: float)
signal connection_changed(is_connected: bool)

@export_range(1, 65535) var port := 9273
@export var disconnect_timeout := 1.0

var _peer := PacketPeerUDP.new()
var _last_packet_time := 0.0
var _last_receive_interval := 1.0 / 120.0
var _is_connected := false

func _ready() -> void:
	var error := _peer.bind(port, "127.0.0.1")
	if error != OK:
		push_error("Could not bind RocketSim receiver to UDP port %d: %s" % [port, error_string(error)])
		set_process(false)
		return
	print("Listening for GigaLearnBot on UDP %d" % port)

func _process(_delta: float) -> void:
	while _peer.get_available_packet_count() > 0:
		_receive_packet(_peer.get_packet())

	if _is_connected and _time_now() - _last_packet_time > disconnect_timeout:
		_is_connected = false
		connection_changed.emit(false)

func _receive_packet(packet: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(packet.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var received_at := _time_now()
	if _last_packet_time > 0.0:
		_last_receive_interval = received_at - _last_packet_time
	_last_packet_time = received_at

	if not _is_connected:
		_is_connected = true
		connection_changed.emit(true)
		print("Receiving live GigaLearnBot state")

	packet_received.emit(parsed, received_at, _last_receive_interval)

func _time_now() -> float:
	return Time.get_ticks_usec() / 1000000.0
