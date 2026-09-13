extends RefCounted
## Reusable original model instances. Meshes/materials/textures are shared by unit type.
var catalog: RefCounted
var meshes: Dictionary = {}
var materials: Dictionary = {}
var textures: Dictionary = {}

func _init(source: RefCounted) -> void:
	catalog = source

static func vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), -float(value[2])) / 65536.0

func material_for(face: Dictionary) -> StandardMaterial3D:
	var key := "texture:" + str(face.texture) if face.texture != null else "color:" + str(face.color)
	if materials.has(key):
		return materials[key]
	var material := StandardMaterial3D.new()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if face.texture != null:
		if not textures.has(face.texture):
			var image := Image.load_from_file(catalog.root.path_join(catalog.index.textures[face.texture]))
			textures[face.texture] = ImageTexture.create_from_image(image)
		material.albedo_texture = textures[face.texture]
	else:
		var palette_index := int(face.color) if face.color != null else 128
		var rgb: Array = catalog.index.palette[clampi(palette_index, 0, 255)]
		material.albedo_color = Color8(int(rgb[0]), int(rgb[1]), int(rgb[2]))
	materials[key] = material
	return material

func prepare(unit_id: String) -> void:
	if meshes.has(unit_id):
		return
	var unit: Dictionary = catalog.load_unit(unit_id)
	assert(unit.get("model") != null, "Unit needs an original model: " + unit_id)
	var pieces: Array = []
	for piece: Dictionary in unit.model.pieces:
		var groups: Dictionary = {}
		for face: Dictionary in piece.faces:
			var material := material_for(face)
			if not groups.has(material):
				groups[material] = []
			groups[material].append(face)
		var mesh := ArrayMesh.new()
		for material: StandardMaterial3D in groups:
			var surface := SurfaceTool.new()
			surface.begin(Mesh.PRIMITIVE_TRIANGLES)
			surface.set_material(material)
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for face: Dictionary in groups[material]:
				var indices: Array = face.indices
				for triangle in range(1, indices.size() - 1):
					for index: int in [0, triangle, triangle + 1]:
						surface.set_uv(uv[index % 4])
						surface.add_vertex(vector(piece.vertices[int(indices[index])]))
			surface.generate_normals()
			surface.commit(mesh)
		pieces.append(mesh)
	meshes[unit_id] = pieces

func instantiate(unit_id: String) -> Node3D:
	unit_id = unit_id.to_lower()
	prepare(unit_id)
	var unit: Dictionary = catalog.load_unit(unit_id)
	var root := Node3D.new()
	root.name = unit_id
	var nodes: Array[Node3D] = []
	var rig: Dictionary = {}
	var origins: Dictionary = {}
	for i in range(unit.model.pieces.size()):
		var piece: Dictionary = unit.model.pieces[i]
		var node := Node3D.new()
		node.name = piece.name
		node.position = vector(piece.offset)
		if int(piece.parent) < 0:
			root.add_child(node)
		else:
			nodes[int(piece.parent)].add_child(node)
		nodes.append(node)
		var key := String(piece.name).to_lower()
		rig[key] = node
		origins[key] = node.position
		var mesh: ArrayMesh = meshes[unit_id][i]
		if mesh.get_surface_count() > 0:
			var instance := MeshInstance3D.new()
			instance.mesh = mesh
			node.add_child(instance)
	root.set_meta("rig", rig)
	root.set_meta("origins", origins)
	root.set_meta("pieces", nodes)
	return root

static func apply_pose(root: Node3D, pieces: Array) -> void:
	var rig: Dictionary = root.get_meta("rig")
	var origins: Dictionary = root.get_meta("origins")
	for piece: Dictionary in pieces:
		var key := String(piece.name).to_lower()
		if not rig.has(key):
			continue
		var node: Node3D = rig[key]
		node.position = origins[key] + vector(piece.position)
		var angle := Vector3(float(piece.rotation[0]), float(piece.rotation[1]), float(piece.rotation[2])) * TAU / 65536.0
		node.rotation = Vector3(-angle.x, -angle.y, angle.z)
		node.visible = bool(piece.visible)
