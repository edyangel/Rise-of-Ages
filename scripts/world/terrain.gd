extends Node

# Simple terrain/chunk generator for the project.
# Assumptions based on your description:
# - The texture 'res://texturedGrass.png' contains 6 sub-images laid out 3x2 (left->right, top->bottom)
#   with indexes 1..6 (top row 1,2,3 ; bottom row 4,5,6).
# - Each sub-image will be scaled to the project's TILE_SIZE (default 48) when rendered.

# Grass atlas frame guide (3x2 grid in a 48x32 texture; each frame is 16x16):
# Top row (light tones / borders)
#   1: light variant paired with 4 (use around solid green 4)
#   2: light variant paired with 5 (use around detail 5)
#   3: light variant paired with 6 (use around detail 6)
# Bottom row (intense tones)
#   4: solid intense green (default, majority of the terrain)
#   5: intense green with grass detail (scatter randomly)
#   6: intense green with grass detail (scatter randomly)
# Transition pairs: 1 ↔ 4, 2 ↔ 5, 3 ↔ 6

const TILE_SIZE := 48
const FRAME_COLS := 3
const FRAME_ROWS := 2

@export var grass_texture_path: String = "res://MiniWorldSprites/Ground/TexturedGrass.png"
var grass_tex: Texture2D = null

# Dead grass atlas (same layout 3x2 as TexturedGrass)
@export var deadgrass_texture_path: String = "res://MiniWorldSprites/Ground/DeadGrass.png"
var deadgrass_tex: Texture2D = null

# Winter atlas (1x8, 16x128): frames left->right
# 1: hielo (agua helada), 2: más helada, 3: congelada, 4: muy congelada
# 5: nieve, 6: gris, 7: verde oscuro, 8: verde claro
@export var winter_texture_path: String = "res://MiniWorldSprites/Ground/Winter.png"
const WINTER_COLS := 8
const WINTER_ROWS := 1
var winter_tex: Texture2D = null

# Shore atlas (1x5, 16x80): 1 arena, 2 arena+poca agua, 3 más agua, 4 mucha agua, 5 totalmente agua
@export var shore_texture_path: String = "res://MiniWorldSprites/Ground/Shore.png"
const SHORE_COLS := 5
const SHORE_ROWS := 1
var shore_tex: Texture2D = null

# Biome noise configuration
@export var base_seed: int = 1337
@export var height_scale: float = 0.015
@export var temp_scale: float = 0.01
@export var humid_scale: float = 0.01
@export var height_octaves: int = 4
@export var temp_octaves: int = 3
@export var humid_octaves: int = 3
@export var height_lacunarity: float = 2.0
@export var temp_lacunarity: float = 2.0
@export var humid_lacunarity: float = 2.0
@export var height_persistence: float = 0.5
@export var temp_persistence: float = 0.5
@export var humid_persistence: float = 0.5

var _noise_height: FastNoiseLite
var _noise_temp: FastNoiseLite
var _noise_humid: FastNoiseLite
var _noise_cluster: FastNoiseLite

var TreeConfig = preload("res://scripts/tree_data.gd")

func _ready():
	# lazy load the texture so the script can be used as a utility
	if ResourceLoader.exists(grass_texture_path):
		grass_tex = load(grass_texture_path)
	else:
		grass_tex = null
		print("[terrain] Warning: texturedGrass.png not found at %s" % grass_texture_path)

	if ResourceLoader.exists(deadgrass_texture_path):
		deadgrass_tex = load(deadgrass_texture_path)
	else:
		deadgrass_tex = null
		print("[terrain] Warning: DeadGrass.png not found at %s" % deadgrass_texture_path)

	if ResourceLoader.exists(winter_texture_path):
		winter_tex = load(winter_texture_path)
	else:
		winter_tex = null
		print("[terrain] Warning: Winter.png not found at %s" % winter_texture_path)

	if ResourceLoader.exists(shore_texture_path):
		shore_tex = load(shore_texture_path)
	else:
		shore_tex = null
		print("[terrain] Warning: Shore.png not found at %s" % shore_texture_path)

	# Initialize noise generators
	_noise_height = FastNoiseLite.new()
	_noise_height.seed = base_seed
	_noise_height.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_height.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_height.fractal_octaves = height_octaves
	_noise_height.fractal_lacunarity = height_lacunarity
	_noise_height.fractal_gain = height_persistence
	_noise_height.frequency = max(height_scale, 0.0001)

	_noise_temp = FastNoiseLite.new()
	_noise_temp.seed = base_seed + 1000
	_noise_temp.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_temp.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_temp.fractal_octaves = temp_octaves
	_noise_temp.fractal_lacunarity = temp_lacunarity
	_noise_temp.fractal_gain = temp_persistence
	_noise_temp.frequency = max(temp_scale, 0.0001)

	_noise_humid = FastNoiseLite.new()
	_noise_humid.seed = base_seed + 2000
	_noise_humid.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_humid.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_humid.fractal_octaves = humid_octaves
	_noise_humid.fractal_lacunarity = humid_lacunarity
	_noise_humid.fractal_gain = humid_persistence
	_noise_humid.frequency = max(humid_scale, 0.0001)

	# Cluster noise used to create patches/manchones of vegetation
	_noise_cluster = FastNoiseLite.new()
	_noise_cluster.seed = base_seed + 3000
	_noise_cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise_cluster.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise_cluster.fractal_octaves = 3
	_noise_cluster.fractal_lacunarity = 2.0
	_noise_cluster.fractal_gain = 0.5
	_noise_cluster.frequency = 0.006 # low frequency -> large blobs

# Build a unit quad 2D mesh (centered at origin) with UV 0..1
func _build_unit_mesh() -> ArrayMesh:
	var am = ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	var verts := PackedVector2Array([
		Vector2(-0.5, -0.5),
		Vector2( 0.5, -0.5),
		Vector2( 0.5,  0.5),
		Vector2(-0.5,  0.5),
	])
	var uvs := PackedVector2Array([
		Vector2(0.0, 0.0),
		Vector2(1.0, 0.0),
		Vector2(1.0, 1.0),
		Vector2(0.0, 1.0),
	])
	var indices := PackedInt32Array([0,1,2, 0,2,3])
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am

# Build an AtlasTexture sub-region from a 3x2 grid index (1..6)
func _make_subtexture(atlas: Texture2D, frame_idx: int) -> Texture2D:
	if atlas == null:
		return null
	frame_idx = clamp(frame_idx, 1, FRAME_COLS * FRAME_ROWS)
	var tex_size = atlas.get_size()
	var fw = int(tex_size.x / FRAME_COLS)
	var fh = int(tex_size.y / FRAME_ROWS)
	var zero_idx = frame_idx - 1
	var col = zero_idx % FRAME_COLS
	var row = int(zero_idx / float(FRAME_COLS))
	var at = AtlasTexture.new()
	at.atlas = atlas
	at.region = Rect2(col * fw, row * fh, fw, fh)
	return at

func _make_winter_subtexture(frame_idx: int) -> Texture2D:
	if winter_tex == null:
		return null
	frame_idx = clamp(frame_idx, 1, WINTER_COLS * WINTER_ROWS)
	var tex_size = winter_tex.get_size()
	var fw = int(tex_size.x / WINTER_COLS)
	var fh = int(tex_size.y / WINTER_ROWS)
	var zero = frame_idx - 1
	var col = zero % WINTER_COLS
	var row = int(zero / float(WINTER_COLS))
	var at = AtlasTexture.new()
	at.atlas = winter_tex
	at.region = Rect2(col * fw, row * fh, fw, fh)
	return at

# Transition pairs between light (1..3) and intense (4..6) frames
const FRAME_PAIR_LIGHT_FOR_INTENSE := {4: 1, 5: 2, 6: 3}
const FRAME_PAIR_INTENSE_FOR_LIGHT := {1: 4, 2: 5, 3: 6}

# Choose a grass frame with rules:
# - Default: mostly frame 4 (intense solid)
# - Scatter frames 5 and 6 randomly as grass details
# - Optionally, at edges (e.g., near roads later), use the paired light frame (1,2,3)
func _choose_grass_frame(rng: RandomNumberGenerator, is_edge: bool, use_light_edges: bool) -> int:
	# Weighted choice for intense frames: 4 (95%), 5 (2.5%), 6 (2.5%) -> less scattered grass
	var r = rng.randf()
	var intense := 4
	if r >= 0.95:
		intense = 5 if r < 0.975 else 6
	if use_light_edges and is_edge:
		return FRAME_PAIR_LIGHT_FOR_INTENSE.get(intense, 1)
	return intense

# Map logical frame index (1..6) -> region Rect2 in the atlas
func frame_region_for_index(idx: int) -> Rect2:
	if not grass_tex:
		return Rect2()
	var tex_size = grass_tex.get_size()
	var fw = int(tex_size.x / FRAME_COLS)
	var fh = int(tex_size.y / FRAME_ROWS)
	idx = clamp(idx, 1, FRAME_COLS * FRAME_ROWS)
	var zero_idx = idx - 1
	var col = zero_idx % FRAME_COLS
	var row = int(zero_idx / float(FRAME_COLS))
	return Rect2(col * fw, row * fh, fw, fh)

func winter_region_for_index(idx: int) -> Rect2:
	if not winter_tex:
		return Rect2()
	var tex_size = winter_tex.get_size()
	var fw = int(tex_size.x / WINTER_COLS)
	var fh = int(tex_size.y / WINTER_ROWS)
	idx = clamp(idx, 1, WINTER_COLS * WINTER_ROWS)
	var zero_idx = idx - 1
	var col = zero_idx % WINTER_COLS
	var row = int(zero_idx / float(WINTER_COLS))
	return Rect2(col * fw, row * fh, fw, fh)

func shore_region_for_index(idx: int) -> Rect2:
	if not shore_tex:
		return Rect2()
	var tex_size = shore_tex.get_size()
	var fw = int(tex_size.x / SHORE_COLS)
	var fh = int(tex_size.y / SHORE_ROWS)
	idx = clamp(idx, 1, SHORE_COLS * SHORE_ROWS)
	var zero_idx = idx - 1
	var col = zero_idx % SHORE_COLS
	var row = int(zero_idx / float(SHORE_COLS))
	return Rect2(col * fw, row * fh, fw, fh)

# Create a TileMap chunk using the shore atlas (1x5, 16x80) scaled to tile_size.
# frame 1: arena, ... frame 5: totalmente agua (azul).
func create_shore_chunk_tilemap(parent: Node, chunk_pos: Vector2, tiles_x: int, tiles_y: int, tile_size: int = TILE_SIZE, forced_frame: int = 0) -> TileMap:
	if shore_tex == null:
		if ResourceLoader.exists(shore_texture_path):
			shore_tex = load(shore_texture_path)
		else:
			return null

	var ts := TileSet.new()
	var src := TileSetAtlasSource.new()
	src.texture = shore_tex
	var tile_px := Vector2i(int(shore_tex.get_size().x / SHORE_COLS), int(shore_tex.get_size().y / SHORE_ROWS))
	src.texture_region_size = tile_px
	src.separation = Vector2i.ZERO
	src.margins = Vector2i.ZERO
	for rx in range(SHORE_COLS):
		var pos := Vector2i(rx, 0)
		if not src.has_tile(pos):
			src.create_tile(pos)
	ts.add_source(src)

	var tm := TileMap.new()
	tm.tile_set = ts
	tm.name = "chunk_shore_tm_%d_%d" % [int(chunk_pos.x), int(chunk_pos.y)]
	tm.z_as_relative = false
	tm.z_index = -100
	tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tm.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	tm.cell_quadrant_size = 1
	tm.tile_set.tile_size = Vector2i(tile_px.x, tile_px.y)
	# Scale 16x16 atlas tiles uniformly to square world tiles (48x48)
	tm.scale = Vector2(3.0, 3.0)

	var base_cell := Vector2i(int(chunk_pos.x * tiles_x), int(chunk_pos.y * tiles_y))
	var src_id := ts.get_source_id(0)
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for y in range(tiles_y):
		for x in range(tiles_x):
			var frame_idx := 1
			if forced_frame >= 1 and forced_frame <= SHORE_COLS * SHORE_ROWS:
				frame_idx = forced_frame
			else:
				# Gradient simple: más agua (5) hacia la derecha y abajo
				var t = float(x) / float(max(tiles_x - 1, 1))
				var u = float(y) / float(max(tiles_y - 1, 1))
				var w = clamp((t + u) * 0.5, 0.0, 1.0)
				var f = 1 + int(round(w * 4.0)) # 1..5
				# ligeras variaciones aleatorias
				if rng.randf() < 0.05:
					f = clamp(f + rng.randi_range(-1, 1), 1, 5)
				frame_idx = f
			var idx := frame_idx - 1
			var col := idx % SHORE_COLS
			var row := int(idx / float(SHORE_COLS))
			tm.set_cell(0, base_cell + Vector2i(x, y), src_id, Vector2i(col, row), 0)

	if parent:
		parent.add_child(tm)
	return tm

# Biome constants
const BIOME_GRASS = "grass"
const BIOME_SAND = "sand"
const BIOME_GRAY = "gray"
const BIOME_SEA = "sea"
const BIOME_BEACH = "beach"
const BIOME_DESERT = "desert"
const BIOME_TEMPERATE = "temperate_forest"
const BIOME_TAIGA = "taiga"
const BIOME_TUNDRA = "tundra"
const BIOME_SNOW_MOUNTAIN = "snow_mountain"

# Frame selection helpers
# Per your description: frames 1 and 4 are solid color; frames 2,3,5,6 contain grassy details
var SOLID_FRAMES := [1, 4]
var DETAILED_FRAMES := [2, 3, 5, 6]

# Create a chunk Node2D with tiles_x x tiles_y tiles. parent is optional; chunk_pos is in tiles
# This version uses MultiMeshInstance2D to render all tiles in a chunk in a single draw call.
func create_chunk(parent: Node, chunk_pos: Vector2, tiles_x: int, tiles_y: int, biome: String = BIOME_GRASS, tile_size: int = TILE_SIZE, texture_path: String = "", light_edges_on_chunk_border: bool = false, forced_frame: int = 0) -> Node2D:
	# enforce chunk size typical for project: caller may request 64x64
	var count = tiles_x * tiles_y
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.instance_count = count
	# Provide a centered unit quad 2D mesh with UV 0..1 for all instances
	mm.mesh = _build_unit_mesh()

	# Choose atlas texture (per-chunk). If texture_path provided, load it; otherwise use grass_tex
	var atlas: Texture2D = null
	if texture_path != "" and ResourceLoader.exists(texture_path):
		atlas = load(texture_path)
	else:
		atlas = grass_tex
	# Compute per-frame aspect to avoid distortion (frame size = atlas / grid)
	var aspect := 1.0
	if atlas:
		var tex_size = atlas.get_size()
		if tex_size.x > 0.0 and tex_size.y > 0.0:
			var fw = tex_size.x / FRAME_COLS
			var fh = tex_size.y / FRAME_ROWS
			if fw > 0.0:
				aspect = fh / fw

	# prepare multimesh instance transforms and per-instance custom data (frame index)
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var base_px = Vector2(chunk_pos.x * tiles_x * tile_size, chunk_pos.y * tiles_y * tile_size)
	var idx = 0
	for y in range(tiles_y):
		for x in range(tiles_x):
			var px = base_px + Vector2(x * tile_size, y * tile_size)
			# pick a frame according to biome
			var frame_idx = 4
			match biome:
				BIOME_GRASS:
					var is_border := (x == 0 or y == 0 or x == tiles_x - 1 or y == tiles_y - 1)
					frame_idx = _choose_grass_frame(rng, is_border, light_edges_on_chunk_border)
				BIOME_SAND:
					# Placeholder: reuse solid frames; adjust when sand atlas available
					frame_idx = SOLID_FRAMES[rng.randi_range(0, SOLID_FRAMES.size() - 1)]
				BIOME_GRAY:
					# Placeholder: reuse detailed frames; adjust when gray atlas available
					frame_idx = DETAILED_FRAMES[rng.randi_range(0, DETAILED_FRAMES.size() - 1)]

			if forced_frame >= 1 and forced_frame <= FRAME_COLS * FRAME_ROWS:
				frame_idx = forced_frame

			# create 2D transform for instance (positioned at tile center)
			var center = px + Vector2(tile_size / 2.0, tile_size / 2.0)
			# non-uniform scale to preserve atlas tile aspect (width: tile_size, height: tile_size * aspect)
			var sx = float(tile_size)
			var sy = float(tile_size) * aspect
			var t = Transform2D(Vector2(sx, 0), Vector2(0, sy), center)
			mm.set_instance_transform_2d(idx, t)
			# Encode frame index (1..N) into 0..1 range for INSTANCE_CUSTOM.x
			var total_frames := FRAME_COLS * FRAME_ROWS
			var enc := (float(frame_idx - 1) / float(total_frames - 1)) if total_frames > 1 else 0.0
			mm.set_instance_custom_data(idx, Color(enc, 0.0, 0.0, 0.0))
			idx += 1

	# build node
	var mnode = MultiMeshInstance2D.new()
	mnode.multimesh = mm
	mnode.name = "chunk_%d_%d" % [int(chunk_pos.x), int(chunk_pos.y)]
	# Ensure terrain renders behind units and props
	mnode.z_as_relative = false
	mnode.z_index = -100

	# If a single frame is forced, use an AtlasTexture sub-region across the whole chunk
	if atlas and forced_frame >= 1 and forced_frame <= FRAME_COLS * FRAME_ROWS:
		var subtex := _make_subtexture(atlas, forced_frame)
		var mat_simple = ShaderMaterial.new()
		var sh_simple = Shader.new()
		sh_simple.code = """
			shader_type canvas_item;
			void fragment() {
				COLOR = texture(TEXTURE, UV) * COLOR;
			}
		"""
		mat_simple.shader = sh_simple
		mnode.material = mat_simple
		if mm.mesh and mm.mesh.get_surface_count() > 0:
			mm.mesh.surface_set_material(0, mat_simple)
		mnode.texture = subtex
	# Otherwise, create shader material to sample atlas and use custom data to pick subregion per instance
	elif atlas:
		var mat = ShaderMaterial.new()
		var sh = Shader.new()
		sh.code = """
			shader_type canvas_item;
			uniform int cols = 3;
			uniform int rows = 2;
			varying vec2 v_uv_local;
			void vertex() {
				// Map quad VERTEX -0.5..0.5 to 0..1 for local UV per tile
				v_uv_local = VERTEX + vec2(0.5, 0.5);
			}
			void fragment() {
				// Decode frame index from 0..1 encoded custom data
		int total = cols * rows;
		int idx_n = int(round(INSTANCE_CUSTOM.x * float(max(total - 1, 1))));
		int fi = idx_n + 1;
				if (fi < 1 || fi > cols * rows) {
					fi = (INSTANCE_ID % (cols * rows)) + 1;
				}
				int idx = fi - 1;
				int col = idx % cols;
				int row = idx / cols;
				// Cada tile es 1.0/cols x 1.0/rows en UV
				vec2 tile_uv = vec2(1.0/float(cols), 1.0/float(rows));
				// UV local dentro del tile (0..1) derivado de la geometría del quad
				vec2 uv_local = clamp(v_uv_local, 0.0, 1.0);
				// Offset para el tile correspondiente
				vec2 uv_offset = vec2(float(col) * tile_uv.x, float(row) * tile_uv.y);
				vec2 final_uv = uv_offset + uv_local * tile_uv;
				COLOR = texture(TEXTURE, final_uv);
			}
		"""
		mat.shader = sh
		mat.set_shader_parameter("cols", FRAME_COLS)
		mat.set_shader_parameter("rows", FRAME_ROWS)
		mnode.material = mat
		# Also bind material to mesh surface to ensure shader is used in all pipelines
		if mm.mesh and mm.mesh.get_surface_count() > 0:
			mm.mesh.surface_set_material(0, mat)
		# Bind atlas as the node texture so TEXTURE is valid in the shader
		mnode.texture = atlas

	# attach to parent
	if parent:
		parent.add_child(mnode)
	return mnode

# Alternative: TileMap-based chunk using a 3x2 atlas (48x32 -> 6 frames of 16x16), scaled up to tile_size (e.g., 48x32)
func create_chunk_tilemap(parent: Node, chunk_pos: Vector2, tiles_x: int, tiles_y: int, _biome: String = BIOME_GRASS, tile_size: int = TILE_SIZE, texture_path: String = "", light_edges_on_chunk_border: bool = false, forced_frame: int = 0) -> TileMap:
	var atlas: Texture2D = null
	if texture_path != "" and ResourceLoader.exists(texture_path):
		atlas = load(texture_path)
	else:
		atlas = grass_tex
	if atlas == null:
		return null

	# 16x16 per frame (3x2 in a 48x32 texture)
	var tile_px := Vector2i(int(atlas.get_size().x / FRAME_COLS), int(atlas.get_size().y / FRAME_ROWS))

	var ts := TileSet.new()
	var src := TileSetAtlasSource.new()
	src.texture = atlas
	src.texture_region_size = tile_px
	src.separation = Vector2i.ZERO
	src.margins = Vector2i.ZERO
	# Create the 3x2 tiles (cols x rows) so they can be referenced by atlas coords
	for ry in range(FRAME_ROWS):
		for rx in range(FRAME_COLS):
			if not src.has_tile(Vector2i(rx, ry)):
				src.create_tile(Vector2i(rx, ry))
	ts.add_source(src)

	var tm := TileMap.new()
	tm.tile_set = ts
	tm.name = "chunk_tm_%d_%d" % [int(chunk_pos.x), int(chunk_pos.y)]
	tm.z_as_relative = false
	tm.z_index = -100
	# Ensure crisp pixel rendering (no smoothing)
	tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tm.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	# Configure tile cell size in world units: 48x32
	tm.cell_quadrant_size = 1
	tm.tile_set.tile_size = Vector2i(tile_px.x, tile_px.y) # logical tile size in the atlas (16x16)
	# Use a transform to map 16x16 logical to 48x48 world: scale 3x3
	tm.scale = Vector2(3.0, 3.0)

	var base_cell := Vector2i(int(chunk_pos.x * tiles_x), int(chunk_pos.y * tiles_y))
	var src_id := ts.get_source_id(0)

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for y in range(tiles_y):
		for x in range(tiles_x):
			var col := 0
			var row := 0
			if forced_frame >= 1 and forced_frame <= FRAME_COLS * FRAME_ROWS:
				var idx := forced_frame - 1
				col = idx % FRAME_COLS
				row = int(idx / float(FRAME_COLS))
			else:
				# Use same distribution as MultiMesh path
				var is_border := (x == 0 or y == 0 or x == tiles_x - 1 or y == tiles_y - 1)
				var frame_idx := _choose_grass_frame(rng, is_border, light_edges_on_chunk_border)
				var idx2 := frame_idx - 1
				col = idx2 % FRAME_COLS
				row = int(idx2 / float(FRAME_COLS))
			tm.set_cell(0, base_cell + Vector2i(x, y), src_id, Vector2i(col, row), 0)

	if parent:
		parent.add_child(tm)
	return tm

# Create a TileMap chunk using the winter atlas (1x8, 16x128) scaled to tile_size (48x32).
# frame guide: 1..4 agua (de helada a muy congelada), 5 nieve, 6 gris, 7 verde oscuro, 8 verde claro
func create_winter_chunk_tilemap(parent: Node, chunk_pos: Vector2, tiles_x: int, tiles_y: int, tile_size: int = TILE_SIZE, forced_frame: int = 0) -> TileMap:
	if winter_tex == null:
		if ResourceLoader.exists(winter_texture_path):
			winter_tex = load(winter_texture_path)
		else:
			return null

	var ts := TileSet.new()
	var src := TileSetAtlasSource.new()
	src.texture = winter_tex
	# Each frame is 16x16; texture is 16x128 laid 1x8 vertically? Your note says 16x128 and 8 frames; we treat it as 1x8 horizontally as described
	var tile_px := Vector2i(int(winter_tex.get_size().x / WINTER_COLS), int(winter_tex.get_size().y / WINTER_ROWS))
	src.texture_region_size = tile_px
	src.separation = Vector2i.ZERO
	src.margins = Vector2i.ZERO
	for rx in range(WINTER_COLS):
		var pos := Vector2i(rx, 0)
		if not src.has_tile(pos):
			src.create_tile(pos)
	ts.add_source(src)

	var tm := TileMap.new()
	tm.tile_set = ts
	tm.name = "chunk_winter_tm_%d_%d" % [int(chunk_pos.x), int(chunk_pos.y)]
	tm.z_as_relative = false
	tm.z_index = -100
	tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tm.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	tm.cell_quadrant_size = 1
	tm.tile_set.tile_size = Vector2i(tile_px.x, tile_px.y)
	# Same world scale as grass: 48x48 per tile (square)
	tm.scale = Vector2(3.0, 3.0)

	var base_cell := Vector2i(int(chunk_pos.x * tiles_x), int(chunk_pos.y * tiles_y))
	var src_id := ts.get_source_id(0)
	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for y in range(tiles_y):
		for x in range(tiles_x):
			var frame_idx := 5 # default to snow for winter biome
			if forced_frame >= 1 and forced_frame <= WINTER_COLS * WINTER_ROWS:
				frame_idx = forced_frame
			else:
				# Simple rule: mostly snow (5), rare patches of gray (6) and frozen water (2..4) near edges
				var r = rng.randf()
				if r < 0.04:
					frame_idx = 6 # gray
				elif r < 0.08:
					frame_idx = 7 # dark green
				elif r < 0.12:
					frame_idx = 8 # light green
				elif r < 0.18:
					frame_idx = rng.randi_range(1, 4) # water iced variants
			var idx := frame_idx - 1
			var col := idx % WINTER_COLS
			var row := int(idx / float(WINTER_COLS))
			tm.set_cell(0, base_cell + Vector2i(x, y), src_id, Vector2i(col, row), 0)

	if parent:
		parent.add_child(tm)
	return tm

# Create a TileMap chunk using the DeadGrass atlas (3x2) with the same distribution rules as grass.
func create_deadgrass_chunk_tilemap(parent: Node, chunk_pos: Vector2, tiles_x: int, tiles_y: int, tile_size: int = TILE_SIZE, light_edges_on_chunk_border: bool = false, forced_frame: int = 0) -> TileMap:
	if deadgrass_tex == null:
		if ResourceLoader.exists(deadgrass_texture_path):
			deadgrass_tex = load(deadgrass_texture_path)
		else:
			return null

	var atlas := deadgrass_tex
	# 16x16 per frame (3x2)
	var tile_px := Vector2i(int(atlas.get_size().x / FRAME_COLS), int(atlas.get_size().y / FRAME_ROWS))

	var ts := TileSet.new()
	var src := TileSetAtlasSource.new()
	src.texture = atlas
	src.texture_region_size = tile_px
	src.separation = Vector2i.ZERO
	src.margins = Vector2i.ZERO
	for ry in range(FRAME_ROWS):
		for rx in range(FRAME_COLS):
			if not src.has_tile(Vector2i(rx, ry)):
				src.create_tile(Vector2i(rx, ry))
	ts.add_source(src)

	var tm := TileMap.new()
	tm.tile_set = ts
	tm.name = "chunk_dead_tm_%d_%d" % [int(chunk_pos.x), int(chunk_pos.y)]
	tm.z_as_relative = false
	tm.z_index = -100
	tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tm.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	tm.cell_quadrant_size = 1
	tm.tile_set.tile_size = Vector2i(tile_px.x, tile_px.y)
	# Map 16x16 to 48x48 world units (square)
	tm.scale = Vector2(3.0, 3.0)

	var base_cell := Vector2i(int(chunk_pos.x * tiles_x), int(chunk_pos.y * tiles_y))
	var src_id := ts.get_source_id(0)

	var rng = RandomNumberGenerator.new()
	rng.randomize()

	for y in range(tiles_y):
		for x in range(tiles_x):
			var col := 0
			var row := 0
			if forced_frame >= 1 and forced_frame <= FRAME_COLS * FRAME_ROWS:
				var idx := forced_frame - 1
				col = idx % FRAME_COLS
				row = int(idx / float(FRAME_COLS))
			else:
				var is_border := (x == 0 or y == 0 or x == tiles_x - 1 or y == tiles_y - 1)
				var frame_idx := _choose_grass_frame(rng, is_border, light_edges_on_chunk_border)
				var idx2 := frame_idx - 1
				col = idx2 % FRAME_COLS
				row = int(idx2 / float(FRAME_COLS))
			tm.set_cell(0, base_cell + Vector2i(x, y), src_id, Vector2i(col, row), 0)

	if parent:
		parent.add_child(tm)
	return tm

# Convenience: create a world of many chunks
func create_world(parent: Node, world_chunks_x: int, world_chunks_y: int, chunk_w: int, chunk_h: int, default_biome: String = BIOME_GRASS, texture_paths: Dictionary = {}) -> Node2D:
	var root = Node2D.new()
	root.name = "world_root"
	for cy in range(world_chunks_y):
		for cx in range(world_chunks_x):
			var biome = default_biome
			# simple alternation example: rows of sand at top
			if cy == 0:
				biome = BIOME_SAND
			elif cy == world_chunks_y - 1:
				biome = BIOME_GRAY
			var tex_path := grass_texture_path
			if texture_paths.has(biome):
				tex_path = String(texture_paths[biome])
			create_chunk(root, Vector2(cx, cy), chunk_w, chunk_h, biome, TILE_SIZE, tex_path)
	if parent:
		parent.add_child(root)
	return root

# Utility to get 0..1 from noise -1..1
func _n01(v: float) -> float:
	return clamp((v + 1.0) * 0.5, 0.0, 1.0)

# Determine biome based on height [-1..1], temperature [-1..1], humidity [0..1]
func _classify_biome(h: float, t: float, u: float) -> String:
	if h < -0.3:
		return BIOME_SEA
	if h < -0.2:
		return BIOME_BEACH
	if h > -0.2 and t > 0.5 and u < 0.3:
		return BIOME_DESERT
	if h >= -0.1 and h <= 0.4 and u > 0.4:
		return BIOME_TEMPERATE
	if h >= 0.2 and h <= 0.6 and t < 0.0:
		return BIOME_TAIGA
	if h >= 0.1 and h <= 0.5 and t < -0.3 and u < 0.4:
		return BIOME_TUNDRA
	if h > 0.6 and t < -0.2:
		return BIOME_SNOW_MOUNTAIN
	# fallback
	return BIOME_TEMPERATE

# Build a TileMap chunk selecting tiles per-biome; also spawns decorations via map helpers
func create_biome_chunk_tilemap(map_node: Node, chunk_pos: Vector2, tiles_x: int, tiles_y: int, tile_size: int = TILE_SIZE, world_seed: int = -1) -> TileMap:
	if world_seed != -1:
		base_seed = world_seed
		if is_inside_tree():
			# re-init noise if needed
			_ready()

	# Ensure atlases loaded
	if grass_tex == null and ResourceLoader.exists(grass_texture_path):
		grass_tex = load(grass_texture_path)
	if deadgrass_tex == null and ResourceLoader.exists(deadgrass_texture_path):
		deadgrass_tex = load(deadgrass_texture_path)
	if winter_tex == null and ResourceLoader.exists(winter_texture_path):
		winter_tex = load(winter_texture_path)
	if shore_tex == null and ResourceLoader.exists(shore_texture_path):
		shore_tex = load(shore_texture_path)

	# Prepare TileSet with multiple atlas sources
	var ts := TileSet.new()
	var src_ids := {}

	if grass_tex:
		var src_g := TileSetAtlasSource.new()
		src_g.texture = grass_tex
		src_g.texture_region_size = Vector2i(int(grass_tex.get_size().x / FRAME_COLS), int(grass_tex.get_size().y / FRAME_ROWS))
		for ry in range(FRAME_ROWS):
			for rx in range(FRAME_COLS):
				var p := Vector2i(rx, ry)
				if not src_g.has_tile(p): src_g.create_tile(p)
		ts.add_source(src_g)
		src_ids["grass"] = ts.get_source_id(ts.get_source_count() - 1)

	if deadgrass_tex:
		var src_d := TileSetAtlasSource.new()
		src_d.texture = deadgrass_tex
		src_d.texture_region_size = Vector2i(int(deadgrass_tex.get_size().x / FRAME_COLS), int(deadgrass_tex.get_size().y / FRAME_ROWS))
		for ry in range(FRAME_ROWS):
			for rx in range(FRAME_COLS):
				var p := Vector2i(rx, ry)
				if not src_d.has_tile(p): src_d.create_tile(p)
		ts.add_source(src_d)
		src_ids["dead"] = ts.get_source_id(ts.get_source_count() - 1)

	if winter_tex:
		var src_w := TileSetAtlasSource.new()
		src_w.texture = winter_tex
		var w_fw = int(winter_tex.get_size().x / WINTER_COLS)
		var w_fh = int(winter_tex.get_size().y / WINTER_ROWS)
		src_w.texture_region_size = Vector2i(w_fw, w_fh)
		for rx in range(WINTER_COLS):
			var p := Vector2i(rx, 0)
			if not src_w.has_tile(p): src_w.create_tile(p)
		ts.add_source(src_w)
		src_ids["winter"] = ts.get_source_id(ts.get_source_count() - 1)

	if shore_tex:
		var src_s := TileSetAtlasSource.new()
		src_s.texture = shore_tex
		var s_fw = int(shore_tex.get_size().x / SHORE_COLS)
		var s_fh = int(shore_tex.get_size().y / SHORE_ROWS)
		src_s.texture_region_size = Vector2i(s_fw, s_fh)
		for rx in range(SHORE_COLS):
			var p := Vector2i(rx, 0)
			if not src_s.has_tile(p): src_s.create_tile(p)
		ts.add_source(src_s)
		src_ids["shore"] = ts.get_source_id(ts.get_source_count() - 1)

	var tm := TileMap.new()
	tm.tile_set = ts
	tm.name = "chunk_biome_tm_%d_%d" % [int(chunk_pos.x), int(chunk_pos.y)]
	tm.z_as_relative = false
	tm.z_index = -100
	tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tm.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	# All atlases use 16x16 tiles; scale to world TILE_SIZE (48x48, squares)
	tm.scale = Vector2(3.0, 3.0)

	if map_node:
		map_node.add_child(tm)

	# First pass: compute biome map and noise fields for this chunk
	var biome_map := []
	biome_map.resize(tiles_y)
	for y in range(tiles_y):
		biome_map[y] = []
		biome_map[y].resize(tiles_x)
	var base_cell := Vector2i(int(chunk_pos.x * tiles_x), int(chunk_pos.y * tiles_y))
	var rng = RandomNumberGenerator.new()
	rng.seed = base_seed

	for y in range(tiles_y):
		for x in range(tiles_x):
			var wx = (base_cell.x + x)
			var wy = (base_cell.y + y)
			var h = _noise_height.get_noise_2d(wx, wy) # -1..1
			var t = _noise_temp.get_noise_2d(wx, wy)   # -1..1
			var u = _n01(_noise_humid.get_noise_2d(wx, wy)) # 0..1
			var b = _classify_biome(h, t, u)
			biome_map[y][x] = {"biome": b, "h": h, "t": t, "u": u}

	# Second pass: place base tiles and spawn decorations
	for y in range(tiles_y):
		for x in range(tiles_x):
			var entry = biome_map[y][x]
			var b = String(entry.biome)
			var h = float(entry.h)
			var _t = float(entry.t)
			var u = float(entry.u)
			var cell = base_cell + Vector2i(x, y)
			# compute cluster mask once per tile (0..1)
			var cval = _n01(_noise_cluster.get_noise_2d(cell.x, cell.y))

			match b:
				BIOME_SEA:
					if src_ids.has("shore"):
						# water frame 5
						var idx0 = 4
						tm.set_cell(0, cell, src_ids["shore"], Vector2i(idx0, 0), 0)
				BIOME_BEACH:
					if src_ids.has("shore"):
						# map h in [-0.3, -0.2) to frames 4..1 (more water near -0.3)
						var k = clamp((h + 0.3) / 0.1, 0.0, 1.0) # 0 at -0.3, 1 at -0.2
						var f0 = int(round(4 - k * 3)) # 4..1
						tm.set_cell(0, cell, src_ids["shore"], Vector2i(f0 - 1, 0), 0)
				BIOME_DESERT:
					if src_ids.has("shore"):
						# use sand (frame 1); occasionally 2 for wet edge
						var f1 = 1 if rng.randf() > 0.05 else 2
						tm.set_cell(0, cell, src_ids["shore"], Vector2i(f1 - 1, 0), 0)
				BIOME_TEMPERATE:
					if src_ids.has("grass"):
						var is_edge = _neighbor_differs_map(biome_map, tiles_x, tiles_y, x, y, BIOME_TEMPERATE)
						var fr = 4
						# simple mimic of _choose_grass_frame
						var r0 = rng.randf()
						if r0 >= 0.95:
							fr = 5 if r0 < 0.975 else 6
						if is_edge:
							var pair = {4:1,5:2,6:3}
							fr = pair.get(fr, 1)
						var idx1 = fr - 1
						var col1 = idx1 % FRAME_COLS
						var row1 = int(idx1 / float(FRAME_COLS))
						tm.set_cell(0, cell, src_ids["grass"], Vector2i(col1, row1), 0)
				BIOME_TAIGA:
					if src_ids.has("winter"):
						# gray base (6)
						tm.set_cell(0, cell, src_ids["winter"], Vector2i(5, 0), 0)
				BIOME_TUNDRA:
					if src_ids.has("dead"):
						# dead grass base, use similar distribution
						var fr2 = 4
						var r1 = rng.randf()
						if r1 >= 0.95:
							fr2 = 5 if r1 < 0.975 else 6
						var idx2 = fr2 - 1
						var col2 = idx2 % FRAME_COLS
						var row2 = int(idx2 / float(FRAME_COLS))
						tm.set_cell(0, cell, src_ids["dead"], Vector2i(col2, row2), 0)
				BIOME_SNOW_MOUNTAIN:
					if src_ids.has("winter"):
						# snow base (5)
						tm.set_cell(0, cell, src_ids["winter"], Vector2i(4, 0), 0)

			# Decorations per-biome (clustered patches/manchones)
			if map_node:
				var tile = Vector2(cell.x, cell.y)
				# Temperate forest: large patches of many trees; but keep max 4 per tile to preserve passage
				if b == BIOME_TEMPERATE and u > 0.35 and map_node.has_method("spawn_tree_entry"):
					# inside cluster -> many trees per tile
					var in_cluster_tf = cval > 0.58
					if in_cluster_tf:
						var count_tf = 2 + rng.randi_range(0, 2) # 2..4
						for i_tf in range(count_tf):
							var type_name_tf = ["oak", "pine", "birch"][rng.randi_range(0,2)]
							var type_idx_tf = TreeConfig.frame_for_type_name(type_name_tf)
							var slot_tf = -1
							if map_node.has_method("get_free_resource_slot"):
								slot_tf = map_node.get_free_resource_slot(tile)
							if slot_tf == -1:
								break
							map_node.spawn_tree_entry("trees", type_idx_tf, tile, slot_tf)
					else:
						# outside cluster -> occasional singles based on humidity
						var p_tf = lerp(0.01, 0.12, clamp((u - 0.35) / 0.65, 0.0, 1.0))
						if rng.randf() < p_tf:
							var type_name_tf2 = ["oak", "pine", "birch"][rng.randi_range(0,2)]
							var type_idx_tf2 = TreeConfig.frame_for_type_name(type_name_tf2)
							var slot_tf2 = -1
							if map_node.has_method("get_free_resource_slot"):
								slot_tf2 = map_node.get_free_resource_slot(tile)
							if slot_tf2 != -1:
								map_node.spawn_tree_entry("trees", type_idx_tf2, tile, slot_tf2)
					# Neighbor-aware fill: if surrounded by forest clusters, fill remaining slots (cap 2 to allow passage)
					var neighbors_clustered := 0
					for oy in range(-1, 2):
						for ox in range(-1, 2):
							if ox == 0 and oy == 0:
								continue
							var nx = x + ox
							var ny = y + oy
							if nx < 0 or ny < 0 or nx >= tiles_x or ny >= tiles_y:
								continue
							var nb = String(biome_map[ny][nx].biome)
							if nb != BIOME_TEMPERATE:
								continue
							var ncell = base_cell + Vector2i(nx, ny)
							var ncval = _n01(_noise_cluster.get_noise_2d(ncell.x, ncell.y))
							if ncval > 0.58:
								neighbors_clustered += 1
					# If at least 5 neighbors are clustered forest, fill remaining slots here
					if neighbors_clustered >= 5 and map_node.has_method("get_free_resource_slot"):
						var added := 0
						while added < 2:
							var free_slot = map_node.get_free_resource_slot(tile)
							if free_slot == -1:
								break
							var type_name_fill = ["oak", "pine", "birch"][rng.randi_range(0,2)]
							var type_idx_fill = TreeConfig.frame_for_type_name(type_name_fill)
							map_node.spawn_tree_entry("trees", type_idx_fill, tile, free_slot)
							added += 1
				# Beach: occasional palms
				elif b == BIOME_BEACH:
					if rng.randf() < 0.04 and map_node.has_method("spawn_tree_entry"):
						var palm = [3,4,5,6][rng.randi_range(0,3)]
						var slot = -1
						if map_node.has_method("get_free_resource_slot"):
							slot = map_node.get_free_resource_slot(tile)
						if slot != -1:
							map_node.spawn_tree_entry("coconut", palm, tile, slot)
				# Desert: cactus mostly dispersos; pequeñas agrupaciones raras; palmeras muy dispersas
				elif b == BIOME_DESERT:
					if map_node.has_method("spawn_tree_entry"):
						var cactus_clustered = cval > 0.78 and rng.randf() < 0.30
						if cactus_clustered:
							var count_cx = 1 + rng.randi_range(0, 1) # 1..2 en cluster pequeño
							for i_cx in range(count_cx):
								var cframe = rng.randi_range(1, TreeConfig.CACTUS_COLS * TreeConfig.CACTUS_ROWS)
								var slot_cx = -1
								if map_node.has_method("get_free_resource_slot"):
									slot_cx = map_node.get_free_resource_slot(tile)
								if slot_cx == -1:
									break
								map_node.spawn_tree_entry("cactus", cframe, tile, slot_cx)
						else:
							# muy dispersos fuera de cluster
							if rng.randf() < 0.010:
								var cframe2 = rng.randi_range(1, TreeConfig.CACTUS_COLS * TreeConfig.CACTUS_ROWS)
								var slot_c2 = -1
								if map_node.has_method("get_free_resource_slot"):
									slot_c2 = map_node.get_free_resource_slot(tile)
								if slot_c2 != -1:
									map_node.spawn_tree_entry("cactus", cframe2, tile, slot_c2)
					# rare oasis palms if desert is unusually humid and clustered
					if u > 0.65 and cval > 0.7 and rng.randf() < 0.015 and map_node.has_method("spawn_tree_entry"):
						var palm2 = [3,4,5,6][rng.randi_range(0,3)]
						var slot_p2 = -1
						if map_node.has_method("get_free_resource_slot"):
							slot_p2 = map_node.get_free_resource_slot(tile)
						if slot_p2 != -1:
							map_node.spawn_tree_entry("coconut", palm2, tile, slot_p2)
					if rng.randf() < 0.02 and map_node.has_method("register_tumbleweed"):
						# Build tumbleweed sprite and register it to roll left (-X)
						if ResourceLoader.exists(TreeConfig.TUMBLEWEED_ATLAS):
							var atlas = load(TreeConfig.TUMBLEWEED_ATLAS)
							var fw = int(atlas.get_size().x / TreeConfig.TUMBLEWEED_COLS)
							var fh = int(atlas.get_size().y / TreeConfig.TUMBLEWEED_ROWS)
							var frame_tw = rng.randi_range(1, 2)
							var zero = frame_tw - 1
							var col_tw = zero % TreeConfig.TUMBLEWEED_COLS
							var row_tw = int(zero / float(TreeConfig.TUMBLEWEED_COLS))
							var at = AtlasTexture.new()
							at.atlas = atlas
							at.region = Rect2(col_tw * fw, row_tw * fh, fw, fh)
							var sp = Sprite2D.new()
							sp.texture = at
							sp.position = Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)
							sp.scale = Vector2(1.2, 1.2)
							sp.centered = true
							sp.z_index = 10
							map_node.add_child(sp)
							var dir = Vector2(-1, 0)
							var speed = tile_size * rng.randf_range(0.15, 0.35)
							map_node.register_tumbleweed(sp, at, fw, fh, frame_tw, dir, speed)
				# Taiga: dense snowy pines
				elif b == BIOME_TAIGA:
					if map_node.has_method("spawn_tree_entry"):
						if cval > 0.55:
							var count_pg = 2 + rng.randi_range(0, 1) # 2..3 pines in cluster
							for i_pg in range(count_pg):
								var pframe = 3 if rng.randf() < 0.7 else 2
								var slot_pg = -1
								if map_node.has_method("get_free_resource_slot"):
									slot_pg = map_node.get_free_resource_slot(tile)
								if slot_pg == -1:
									break
								map_node.spawn_tree_entry("pinetrees", pframe, tile, slot_pg)
						else:
							if rng.randf() < 0.10:
								var pframe2 = 3 if rng.randf() < 0.7 else 2
								var slot_pg2 = -1
								if map_node.has_method("get_free_resource_slot"):
									slot_pg2 = map_node.get_free_resource_slot(tile)
								if slot_pg2 != -1:
									map_node.spawn_tree_entry("pinetrees", pframe2, tile, slot_pg2)
				# Tundra: dead trees and snowy rocks
				elif b == BIOME_TUNDRA:
					if map_node.has_method("spawn_tree_entry"):
						if cval > 0.56:
							var count_dt = 2 + rng.randi_range(0, 2) # 2..4 dead trees in cluster
							for i_dt in range(count_dt):
								var dframe = [3,4][rng.randi_range(0,1)]
								var slot_dt = -1
								if map_node.has_method("get_free_resource_slot"):
									slot_dt = map_node.get_free_resource_slot(tile)
								if slot_dt == -1:
									break
								map_node.spawn_tree_entry("deadtrees", dframe, tile, slot_dt)
						else:
							if rng.randf() < 0.06:
								var dframe2 = [3,4][rng.randi_range(0,1)]
								var slot_dt2 = -1
								if map_node.has_method("get_free_resource_slot"):
									slot_dt2 = map_node.get_free_resource_slot(tile)
								if slot_dt2 != -1:
									map_node.spawn_tree_entry("deadtrees", dframe2, tile, slot_dt2)
					if rng.randf() < 0.06 and ResourceLoader.exists(TreeConfig.ROCKS_ATLAS) and map_node.has_method("register_rock_node"):
						var atlas_r = load(TreeConfig.ROCKS_ATLAS)
						var cols_r = TreeConfig.ROCKS_COLS
						var rows_r = TreeConfig.ROCKS_ROWS
						var fw_r = int(atlas_r.get_size().x / cols_r)
						var fh_r = int(atlas_r.get_size().y / rows_r)
						var frame_r = rng.randi_range(10, 12) # snowy row
						var z = frame_r - 1
						var colr = z % cols_r
						var rowr = int(z / float(cols_r))
						var at_r = AtlasTexture.new()
						at_r.atlas = atlas_r
						at_r.region = Rect2(colr * fw_r, rowr * fh_r, fw_r, fh_r)
						var sp_r = Sprite2D.new()
						sp_r.texture = at_r
						sp_r.position = Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)
						sp_r.scale = Vector2(1.3, 1.3)
						sp_r.centered = true
						sp_r.z_index = 20
						map_node.add_child(sp_r)
						map_node.register_rock_node(sp_r)
				# Snow mountains: mostly snowy rocks
				elif b == BIOME_SNOW_MOUNTAIN:
					if rng.randf() < 0.16 and ResourceLoader.exists(TreeConfig.ROCKS_ATLAS) and map_node.has_method("register_rock_node"):
						var atlas_r2 = load(TreeConfig.ROCKS_ATLAS)
						var cols2 = TreeConfig.ROCKS_COLS
						var rows2 = TreeConfig.ROCKS_ROWS
						var fw2 = int(atlas_r2.get_size().x / cols2)
						var fh2 = int(atlas_r2.get_size().y / rows2)
						var frame2 = rng.randi_range(10, 12)
						var z2 = frame2 - 1
						var col2 = z2 % cols2
						var row2 = int(z2 / float(cols2))
						var at2 = AtlasTexture.new()
						at2.atlas = atlas_r2
						at2.region = Rect2(col2 * fw2, row2 * fh2, fw2, fh2)
						var sp2 = Sprite2D.new()
						sp2.texture = at2
						sp2.position = Vector2((cell.x + 0.5) * tile_size, (cell.y + 0.5) * tile_size)
						sp2.scale = Vector2(1.3, 1.3)
						sp2.centered = true
						sp2.z_index = 20
						map_node.add_child(sp2)
						map_node.register_rock_node(sp2)

	return tm

# Class-scope helper to test if any 4-neighbor differs from a target biome value
func _neighbor_differs_map(biome_map: Array, tiles_x: int, tiles_y: int, ix: int, iy: int, target: String) -> bool:
	var dirs = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	for d in dirs:
		var nx = ix + d.x
		var ny = iy + d.y
		if nx < 0 or ny < 0 or nx >= tiles_x or ny >= tiles_y:
			continue
		if String(biome_map[ny][nx].biome) != target:
			return true
	return false
