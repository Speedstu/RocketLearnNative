class_name BoostPadLayout
extends Node3D

const LARGE_MODEL := preload("res://assets/models/BoostPad_Large.fbx")
const SMALL_MODEL := preload("res://assets/models/BoostPad_Small.fbx")
const SURFACE_SHADER := preload("res://shaders/boost_pad_surface.gdshader")
const ORB_SHADER := preload("res://shaders/boost_orb.gdshader")
const HALO_SHADER := preload("res://shaders/boost_halo.gdshader")
const DISC_SHADER := preload("res://shaders/boost_disc.gdshader")
const MODEL_SCALE := 1.1

const LARGE_LOCATIONS := [
	Vector3(-3072, -4096, 0),
	Vector3(3072, -4096, 0),
	Vector3(-3584, 0, 0),
	Vector3(3584, 0, 0),
	Vector3(-3072, 4096, 0),
	Vector3(3072, 4096, 0)
]

const LARGE_STATE_INDICES := [3, 4, 15, 18, 29, 30]

const SMALL_LOCATIONS := [
	Vector3(0, -4240, 0),
	Vector3(-1792, -4184, 0),
	Vector3(1792, -4184, 0),
	Vector3(-940, -3308, 0),
	Vector3(940, -3308, 0),
	Vector3(0, -2816, 0),
	Vector3(-3584, -2484, 0),
	Vector3(3584, -2484, 0),
	Vector3(-1788, -2300, 0),
	Vector3(1788, -2300, 0),
	Vector3(-2048, -1036, 0),
	Vector3(0, -1024, 0),
	Vector3(2048, -1036, 0),
	Vector3(-1024, 0, 0),
	Vector3(1024, 0, 0),
	Vector3(-2048, 1036, 0),
	Vector3(0, 1024, 0),
	Vector3(2048, 1036, 0),
	Vector3(-1788, 2300, 0),
	Vector3(1788, 2300, 0),
	Vector3(-3584, 2484, 0),
	Vector3(3584, 2484, 0),
	Vector3(0, 2816, 0),
	Vector3(-940, 3310, 0),
	Vector3(940, 3308, 0),
	Vector3(-1792, 4184, 0),
	Vector3(1792, 4184, 0),
	Vector3(0, 4240, 0)
]

const SMALL_STATE_INDICES := [
	0, 1, 2, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16,
	17, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 31, 32, 33
]

var large_material := ShaderMaterial.new()
var small_material := ShaderMaterial.new()
var orb_material := ShaderMaterial.new()
var halo_material := ShaderMaterial.new()
var disc_material := ShaderMaterial.new()
var orb_roots: Array[Node3D] = []
var pads_by_state_index: Array[Node3D] = []
var effects_by_state_index: Array[Node3D] = []
var materials_by_state_index: Array[ShaderMaterial] = []
var animation_time := 0.0

func _ready() -> void:
	large_material.shader = SURFACE_SHADER
	large_material.set_shader_parameter("large_pad", true)
	small_material.shader = SURFACE_SHADER
	small_material.set_shader_parameter("large_pad", false)
	orb_material.shader = ORB_SHADER
	halo_material.shader = HALO_SHADER
	disc_material.shader = DISC_SHADER
	pads_by_state_index.resize(LARGE_LOCATIONS.size() + SMALL_LOCATIONS.size())
	effects_by_state_index.resize(pads_by_state_index.size())
	materials_by_state_index.resize(pads_by_state_index.size())
	_spawn_group(LARGE_MODEL, LARGE_LOCATIONS, LARGE_STATE_INDICES, "Large", large_material, true)
	_spawn_group(SMALL_MODEL, SMALL_LOCATIONS, SMALL_STATE_INDICES, "Small", small_material, false)

func _process(delta: float) -> void:
	animation_time += delta
	for index in orb_roots.size():
		var orb_root := orb_roots[index]
		orb_root.position.y = 0.82 + sin(animation_time * 2.1 + index * 0.73) * 0.045
		orb_root.rotation_degrees.y = fmod(animation_time * 28.0 + index * 41.0, 360.0)

func set_states(states: Array) -> void:
	for index in mini(states.size(), pads_by_state_index.size()):
		var is_active := bool(states[index])
		effects_by_state_index[index].visible = is_active
		materials_by_state_index[index].set_shader_parameter("active", is_active)

func _spawn_group(model: PackedScene, locations: Array, state_indices: Array, prefix: String, material: Material, large: bool) -> void:
	for index in locations.size():
		var pad := model.instantiate() as Node3D
		var pad_material := material.duplicate() as ShaderMaterial
		pad.name = "%sPad%02d" % [prefix, index]
		pad.position = RLCoordinates.position_to_godot(locations[index])
		pad.scale = Vector3.ONE * MODEL_SCALE
		_apply_material(pad, pad_material)
		var effect: Node3D
		if large:
			effect = _add_large_effect(pad)
		else:
			effect = _add_small_effect(pad)
		add_child(pad)
		var state_index: int = state_indices[index]
		pads_by_state_index[state_index] = pad
		effects_by_state_index[state_index] = effect
		materials_by_state_index[state_index] = pad_material

func _apply_material(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		node.material_override = material
	for child in node.get_children():
		_apply_material(child, material)

func _add_large_effect(pad: Node3D) -> Node3D:
	var orb_root := Node3D.new()
	orb_root.name = "EnergyOrb"
	orb_root.position.y = 0.82
	pad.add_child(orb_root)
	orb_roots.append(orb_root)

	var orb_mesh := SphereMesh.new()
	orb_mesh.radius = 0.22
	orb_mesh.height = 0.44
	orb_mesh.radial_segments = 48
	orb_mesh.rings = 24
	var orb := MeshInstance3D.new()
	orb.mesh = orb_mesh
	orb.material_override = orb_material
	orb_root.add_child(orb)

	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 0.29
	halo_mesh.height = 0.58
	halo_mesh.radial_segments = 40
	halo_mesh.rings = 20
	var halo := MeshInstance3D.new()
	halo.mesh = halo_mesh
	halo.material_override = halo_material
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orb_root.add_child(halo)

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.52, 0.08)
	light.light_energy = 0.5
	light.omni_range = 2.8
	light.omni_attenuation = 1.4
	light.shadow_enabled = false
	orb_root.add_child(light)
	return orb_root

func _add_small_effect(pad: Node3D) -> Node3D:
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 0.34
	disc_mesh.bottom_radius = 0.34
	disc_mesh.height = 0.022
	disc_mesh.radial_segments = 48
	var disc := MeshInstance3D.new()
	disc.name = "EnergyDisc"
	disc.position.y = 0.075
	disc.mesh = disc_mesh
	disc.material_override = disc_material
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pad.add_child(disc)
	return disc
