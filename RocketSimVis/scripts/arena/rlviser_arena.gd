class_name Arena
extends Node3D

const SURFACE_SHADER := preload("res://shaders/arena_surface.gdshader")
const DETAIL_NORMAL := preload("res://assets/textures/ArenaDetail_N.tga")

@export_file("*.gmb") var stadium_path := "res://assets/arena/stadium.gmb"

func _ready() -> void:
	_load_stadium()

func _load_stadium() -> void:
	var file := FileAccess.open(stadium_path, FileAccess.READ)
	if file == null:
		push_error("Could not open RLViser stadium at %s" % stadium_path)
		return
	if file.get_buffer(4).get_string_from_ascii() != "GST1":
		push_error("Invalid RLViser stadium file")
		return

	var group_count := file.get_32()
	for group_index in group_count:
		var color := Color(file.get_float(), file.get_float(), file.get_float(), file.get_float())
		var transparent := file.get_8() != 0
		var textured := file.get_8() != 0
		var mesh := _read_group_mesh(file)
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "StadiumGroup%02d" % group_index
		mesh_instance.mesh = mesh
		mesh_instance.material_override = _create_material(color, transparent, textured)
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if transparent else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mesh_instance)

	file.close()

func _read_group_mesh(file: FileAccess) -> ArrayMesh:
	var vertex_count := file.get_32()
	var positions := PackedVector3Array()
	positions.resize(vertex_count)
	for index in vertex_count:
		positions[index] = Vector3(file.get_float(), file.get_float(), file.get_float())

	var uvs := PackedVector2Array()
	uvs.resize(vertex_count)
	for index in vertex_count:
		uvs[index] = Vector2(file.get_float(), file.get_float())

	var index_count := file.get_32()
	var indices := PackedInt32Array()
	indices.resize(index_count)
	for index in index_count:
		indices[index] = file.get_32()

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in vertex_count:
		surface.set_uv(uvs[index])
		surface.add_vertex(positions[index])
	for index in indices:
		surface.add_index(index)
	surface.generate_normals()
	return surface.commit()

func _create_material(color: Color, transparent: bool, textured: bool) -> Material:
	if transparent:
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.70, 0.78, 0.84, 0.24) if textured else Color(0.62, 0.68, 0.70, 0.32)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		return material

	var material := ShaderMaterial.new()
	material.shader = SURFACE_SHADER
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("detail_normal", DETAIL_NORMAL)
	return material
