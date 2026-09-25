extends Node3D
## A small Minecraft-looking world around the player: sky, fog, sun, and procedural terrain
## with a flat clearing at spawn, hills, oak trees, flowers and a pond. Built once into a
## single mesh (one surface per block texture) with Minecraft's face shading baked into
## vertex colors, so every material can be unshaded.

const RADIUS := 32 # blocks around the origin
const CLEARING := 4.5 # flat grass around spawn, so nothing gets near the menu panel
const Y_MIN := -8
const Y_MAX := 24
const SIZE := RADIUS * 2 + 1
const HEIGHT := Y_MAX - Y_MIN
const SEED := 1337
const POND_CENTER := Vector2(-10, 9)

const SKY_TOP := Color("78a7ff")
const SKY_HORIZON := Color("c0d8ff")
const GRASS_TINT := Color("91bd59")
const LEAVES_TINT := Color("77ab2f")
const WATER_TINT := Color("3f76e4")

enum { AIR, GRASS, DIRT, STONE, COBBLESTONE, LOG, SAND, LEAVES, WATER, SHORT_GRASS, POPPY, DANDELION }
const LAST_OPAQUE := SAND

## Each face: neighbor direction, Minecraft's brightness, and corners (top-left, top-right,
## bottom-right, bottom-left as seen from outside, so the triangles wind clockwise)
const FACES := [
	{"dir": Vector3i.UP, "shade": 1.0, "corners": [Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)]},
	{"dir": Vector3i.DOWN, "shade": 0.5, "corners": [Vector3(1, 0, 0), Vector3(0, 0, 0), Vector3(0, 0, 1), Vector3(1, 0, 1)]},
	{"dir": Vector3i.BACK, "shade": 0.8, "corners": [Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 0, 1), Vector3(0, 0, 1)]},
	{"dir": Vector3i.FORWARD, "shade": 0.8, "corners": [Vector3(1, 1, 0), Vector3(0, 1, 0), Vector3(0, 0, 0), Vector3(1, 0, 0)]},
	{"dir": Vector3i.RIGHT, "shade": 0.6, "corners": [Vector3(1, 1, 1), Vector3(1, 1, 0), Vector3(1, 0, 0), Vector3(1, 0, 1)]},
	{"dir": Vector3i.LEFT, "shade": 0.6, "corners": [Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(0, 0, 1), Vector3(0, 0, 0)]},
]
const QUAD_UVS := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
const PLANTS := {SHORT_GRASS: "short_grass", POPPY: "poppy", DANDELION: "dandelion"}
const CUTOUT := ["oak_leaves", "short_grass", "poppy", "dandelion"]

var _blocks := PackedByteArray()
var _heights := {} # Vector2i -> height of the column's top face
var _rng := RandomNumberGenerator.new()
var _tools := {} # texture name -> SurfaceTool
var _vertex_counts := {}


func _ready() -> void:
	_build_environment()
	_build_sun()
	_rng.seed = SEED
	_blocks.resize(SIZE * HEIGHT * SIZE)
	_generate_terrain()
	_generate_trees()
	_generate_boulders()
	_generate_plants()
	_build_mesh()


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP
	sky_material.sky_horizon_color = SKY_HORIZON
	sky_material.ground_horizon_color = SKY_HORIZON
	sky_material.ground_bottom_color = SKY_HORIZON
	var sky := Sky.new()
	sky.sky_material = sky_material
	sky.radiance_size = Sky.RADIANCE_SIZE_32

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	# Fades the terrain into the horizon well before its edge
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_light_color = SKY_HORIZON
	env.fog_density = 1.0
	env.fog_depth_begin = 16.0
	env.fog_depth_end = RADIUS - 2.0
	env.fog_sky_affect = 0.0
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)


func _build_sun() -> void:
	var sun := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(45, 45) # Same angular size as in Minecraft
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = load("res://textures/environment/sun.png")
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD # The texture's background is black
	material.disable_fog = true
	quad.material = material
	sun.mesh = quad
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sun)
	var direction := Vector3(0.5, 1.2, -1.0).normalized()
	sun.position = direction * 150.0
	# The quad's visible side is +Z, so aim -Z away from the player
	sun.look_at(sun.position * 2.0, Vector3.UP)


func _index(x: int, y: int, z: int) -> int:
	return ((x + RADIUS) * HEIGHT + (y - Y_MIN)) * SIZE + (z + RADIUS)


## Outside the world counts as solid, so its edges and bottom get no faces
func _get_block(x: int, y: int, z: int) -> int:
	if y >= Y_MAX:
		return AIR
	if y < Y_MIN or x * x + z * z > RADIUS * RADIUS:
		return STONE
	return _blocks[_index(x, y, z)]


func _set_block(x: int, y: int, z: int, block: int) -> void:
	if y >= Y_MIN and y < Y_MAX and x * x + z * z <= RADIUS * RADIUS:
		_blocks[_index(x, y, z)] = block


func _generate_terrain() -> void:
	var noise := FastNoiseLite.new()
	noise.seed = SEED
	noise.frequency = 0.045
	noise.fractal_octaves = 3
	for x in range(-RADIUS, RADIUS + 1):
		for z in range(-RADIUS, RADIUS + 1):
			if x * x + z * z > RADIUS * RADIUS:
				continue
			var distance := Vector2(x, z).length()
			var hills := noise.get_noise_2d(x, z) * 6.0 + 1.5
			var height := maxi(0, roundi(hills * smoothstep(CLEARING, 14.0, distance)))
			var pond := Vector2(x, z).distance_to(POND_CENTER)
			if pond < 2.5:
				height = mini(height, -2)
			elif pond < 4.0:
				height = mini(height, -1)
			_heights[Vector2i(x, z)] = height
			for y in range(Y_MIN, height):
				var block := STONE
				if y == height - 1:
					block = GRASS if height >= 0 else SAND
				elif y >= height - 3:
					block = DIRT
				_set_block(x, y, z, block)
			# Water fills the pond up to sea level (y=0)
			for y in range(height, 0):
				_set_block(x, y, z, WATER)

	# Beaches: grass at sea level next to water becomes sand
	for column: Vector2i in _heights:
		if _heights[column] != 0 or column.length() < CLEARING:
			continue
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if _get_block(column.x + offset.x, -1, column.y + offset.y) == WATER:
				_set_block(column.x, -1, column.y, SAND)
				break


func _generate_trees() -> void:
	var trees: Array[Vector2i] = []
	for attempt in 80:
		if trees.size() >= 9:
			break
		var column := Vector2i(_rng.randi_range(-26, 26), _rng.randi_range(-26, 26))
		var distance := column.length()
		if distance < 9.0 or distance > 26.0:
			continue
		var base: int = _heights.get(column, -1)
		if _get_block(column.x, base - 1, column.y) != GRASS:
			continue
		if trees.any(func(other: Vector2i) -> bool: return (other - column).length() < 6.0):
			continue
		trees.append(column)
		_place_tree(column.x, base, column.y)


## An oak like Minecraft's: a 4-6 block trunk, two wide layers of leaves and two narrow ones
func _place_tree(x: int, base: int, z: int) -> void:
	var trunk := _rng.randi_range(4, 6)
	_set_block(x, base - 1, z, DIRT)
	for layer in 4:
		var y := base + trunk - 3 + layer
		var reach := 2 if layer < 2 else 1
		for dx in range(-reach, reach + 1):
			for dz in range(-reach, reach + 1):
				if absi(dx) == reach and absi(dz) == reach and (layer == 3 or _rng.randf() < 0.5):
					continue
				if _get_block(x + dx, y, z + dz) == AIR:
					_set_block(x + dx, y, z + dz, LEAVES)
	for y in range(base, base + trunk):
		_set_block(x, y, z, LOG)


func _generate_boulders() -> void:
	for boulder in 3:
		var angle := _rng.randf() * TAU
		var column := Vector2i(Vector2.from_angle(angle) * _rng.randf_range(10.0, 22.0))
		var base: int = _heights.get(column, -1)
		if base < 0:
			continue
		for dx in 2:
			for dz in 2:
				var top: int = _heights.get(column + Vector2i(dx, dz), base)
				if _get_block(column.x + dx, top, column.y + dz) == AIR:
					_set_block(column.x + dx, top, column.y + dz, COBBLESTONE)
		_set_block(column.x, base + 1, column.y, COBBLESTONE)


func _generate_plants() -> void:
	for column: Vector2i in _heights:
		if column.length() < 1.5:
			continue
		var y: int = _heights[column]
		if _get_block(column.x, y - 1, column.y) != GRASS or _get_block(column.x, y, column.y) != AIR:
			continue
		var roll := _rng.randf()
		if roll < 0.02:
			_set_block(column.x, y, column.y, POPPY)
		elif roll < 0.04:
			_set_block(column.x, y, column.y, DANDELION)
		elif roll < 0.16:
			_set_block(column.x, y, column.y, SHORT_GRASS)


func _build_mesh() -> void:
	for column: Vector2i in _heights:
		var x := column.x
		var z := column.y
		# Columns are solid up to their surface, so anything below the lowest neighboring
		# surface is buried and has no faces to show
		var lowest: int = _heights[column]
		for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			lowest = mini(lowest, _heights.get(column + offset, lowest))
		for y in range(maxi(Y_MIN, lowest - 1), Y_MAX):
			var block: int = _blocks[_index(x, y, z)]
			if block == AIR:
				continue
			# Cells are centered on whole x/z, so the player stands in the middle of a block
			var corner := Vector3(x - 0.5, y, z - 0.5)
			if PLANTS.has(block):
				_add_plant(block, corner)
				continue
			for face: Dictionary in FACES:
				var dir: Vector3i = face.dir
				if _shows_face(block, _get_block(x + dir.x, y + dir.y, z + dir.z)):
					_add_face(block, face, corner)

	var mesh := ArrayMesh.new()
	for texture: String in _tools:
		var tool: SurfaceTool = _tools[texture]
		tool.set_material(_material(texture))
		tool.commit(mesh)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _shows_face(block: int, neighbor: int) -> bool:
	if neighbor != AIR and neighbor <= LAST_OPAQUE:
		return false
	return neighbor != block # No faces inside leaves or water


func _add_face(block: int, face: Dictionary, corner: Vector3) -> void:
	var dir: Vector3i = face.dir
	var texture := "dirt"
	var tint := Color.WHITE
	match block:
		GRASS:
			if dir == Vector3i.UP:
				texture = "grass_block_top"
				tint = GRASS_TINT
			elif dir != Vector3i.DOWN:
				texture = "grass_block_side"
		STONE: texture = "stone"
		COBBLESTONE: texture = "cobblestone"
		SAND: texture = "sand"
		LOG: texture = "oak_log_top" if dir.y != 0 else "oak_log"
		LEAVES:
			texture = "oak_leaves"
			tint = LEAVES_TINT
		WATER:
			texture = "water_still"
			tint = WATER_TINT
	var shade: float = face.shade
	var color := Color(tint.r * shade, tint.g * shade, tint.b * shade)
	var corners: Array[Vector3] = []
	for offset: Vector3 in face.corners:
		# Water sits a little below the top of its block, like in Minecraft
		if block == WATER and offset.y == 1.0:
			offset.y = 0.875
		corners.append(corner + offset)
	_add_quad(texture, corners, color)


## Two crossed quads, nudged around like Minecraft's short grass
func _add_plant(block: int, corner: Vector3) -> void:
	var texture: String = PLANTS[block]
	var tint := GRASS_TINT if block == SHORT_GRASS else Color.WHITE
	var nudge := Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2))
	var center := corner + Vector3(0.5, 0, 0.5) + nudge
	var reach := 0.45
	for diagonal in [Vector3(reach, 0, reach), Vector3(reach, 0, -reach)]:
		_add_quad(texture, [
			center - diagonal + Vector3.UP,
			center + diagonal + Vector3.UP,
			center + diagonal,
			center - diagonal,
		], tint)


func _add_quad(texture: String, corners: Array[Vector3], color: Color) -> void:
	if not _tools.has(texture):
		var new_tool := SurfaceTool.new()
		new_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		_tools[texture] = new_tool
		_vertex_counts[texture] = 0
	var tool: SurfaceTool = _tools[texture]
	var first: int = _vertex_counts[texture]
	for i in 4:
		tool.set_color(color)
		tool.set_uv(QUAD_UVS[i])
		tool.add_vertex(corners[i])
	for i in [0, 1, 2, 0, 2, 3]:
		tool.add_index(first + i)
	_vertex_counts[texture] = first + 4


func _material(texture: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = load("res://textures/block/%s.png" % texture)
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true # Tints and shading are in Minecraft's sRGB
	if texture in CUTOUT:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
	elif texture == "water_still":
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material
