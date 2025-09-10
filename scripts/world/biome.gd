extends Node

# Biome-based chunk generator (extracted from terrain.gd)

const FRAME_COLS := 3
const FRAME_ROWS := 2
const WINTER_COLS := 8
const WINTER_ROWS := 1
const SHORE_COLS := 5
const SHORE_ROWS := 1

# Atlases
@export var grass_texture_path: String = "res://MiniWorldSprites/Ground/TexturedGrass.png"
@export var deadgrass_texture_path: String = "res://MiniWorldSprites/Ground/DeadGrass.png"
@export var winter_texture_path: String = "res://MiniWorldSprites/Ground/Winter.png"
@export var shore_texture_path: String = "res://MiniWorldSprites/Ground/Shore.png"

var grass_tex: Texture2D = null
var deadgrass_tex: Texture2D = null
var winter_tex: Texture2D = null
var shore_tex: Texture2D = null

# Biome ids
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

# Noise config
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
    _load_textures()
    _init_noises()

func _load_textures():
    if ResourceLoader.exists(grass_texture_path):
        grass_tex = load(grass_texture_path)
    else:
        grass_tex = null
    if ResourceLoader.exists(deadgrass_texture_path):
        deadgrass_tex = load(deadgrass_texture_path)
    else:
        deadgrass_tex = null
    if ResourceLoader.exists(winter_texture_path):
        winter_tex = load(winter_texture_path)
    else:
        winter_tex = null
    if ResourceLoader.exists(shore_texture_path):
        shore_tex = load(shore_texture_path)
    else:
        shore_tex = null

func _init_noises():
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

    _noise_cluster = FastNoiseLite.new()
    _noise_cluster.seed = base_seed + 3000
    _noise_cluster.noise_type = FastNoiseLite.TYPE_SIMPLEX
    _noise_cluster.fractal_type = FastNoiseLite.FRACTAL_FBM
    _noise_cluster.fractal_octaves = 3
    _noise_cluster.fractal_lacunarity = 2.0
    _noise_cluster.fractal_gain = 0.5
    _noise_cluster.frequency = 0.006

func _n01(x: float) -> float:
    return clamp((x + 1.0) * 0.5, 0.0, 1.0)

func _classify_biome(h: float, t: float, u: float) -> String:
    if h < -0.4:
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
    return BIOME_TEMPERATE

func create_biome_chunk_tilemap(map_node: Node, chunk_pos: Vector2, tiles_x: int, tiles_y: int, _tile_size: int, world_seed: int = -1) -> TileMap:
    if world_seed != -1:
        base_seed = world_seed
        _init_noises()
    if grass_tex == null or deadgrass_tex == null or winter_tex == null or shore_tex == null:
        _load_textures()

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
                var p2 := Vector2i(rx, ry)
                if not src_d.has_tile(p2): src_d.create_tile(p2)
        ts.add_source(src_d)
        src_ids["dead"] = ts.get_source_id(ts.get_source_count() - 1)

    if winter_tex:
        var src_w := TileSetAtlasSource.new()
        src_w.texture = winter_tex
        var w_fw = int(winter_tex.get_size().x / WINTER_COLS)
        var w_fh = int(winter_tex.get_size().y / WINTER_ROWS)
        src_w.texture_region_size = Vector2i(w_fw, w_fh)
        for rx in range(WINTER_COLS):
            var p3 := Vector2i(rx, 0)
            if not src_w.has_tile(p3): src_w.create_tile(p3)
        ts.add_source(src_w)
        src_ids["winter"] = ts.get_source_id(ts.get_source_count() - 1)

    if shore_tex:
        var src_s := TileSetAtlasSource.new()
        src_s.texture = shore_tex
        var s_fw = int(shore_tex.get_size().x / SHORE_COLS)
        var s_fh = int(shore_tex.get_size().y / SHORE_ROWS)
        src_s.texture_region_size = Vector2i(s_fw, s_fh)
        for rx in range(SHORE_COLS):
            var p4 := Vector2i(rx, 0)
            if not src_s.has_tile(p4): src_s.create_tile(p4)
        ts.add_source(src_s)
        src_ids["shore"] = ts.get_source_id(ts.get_source_count() - 1)

    var tm := TileMap.new()
    tm.tile_set = ts
    tm.name = "chunk_biome_tm_%d_%d" % [int(chunk_pos.x), int(chunk_pos.y)]
    tm.z_as_relative = false
    tm.z_index = -100
    tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    tm.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
    # scale 3x3 to map 16x16 logical to square world tiles
    tm.scale = Vector2(3.0, 3.0)
    if map_node:
        map_node.add_child(tm)

    var biome_map := []
    biome_map.resize(tiles_y)
    for y in range(tiles_y):
        biome_map[y] = []
        biome_map[y].resize(tiles_x)

    var base_cell := Vector2i(int(chunk_pos.x * tiles_x), int(chunk_pos.y * tiles_y))
    var rng = RandomNumberGenerator.new()
    rng.seed = base_seed

    # First pass: classify biomes
    for y in range(tiles_y):
        for x in range(tiles_x):
            var wx = (base_cell.x + x)
            var wy = (base_cell.y + y)
            var h = _noise_height.get_noise_2d(wx, wy)
            var t = _noise_temp.get_noise_2d(wx, wy)
            var u = _n01(_noise_humid.get_noise_2d(wx, wy))
            var b = _classify_biome(h, t, u)
            biome_map[y][x] = {"biome": b, "h": h, "t": t, "u": u}

    # Second pass: place tiles and spawn decorations
    var tile_size := _tile_size
    for y in range(tiles_y):
        for x in range(tiles_x):
            var entry = biome_map[y][x]
            var b = String(entry.biome)
            var h = float(entry.h)
            var _t = float(entry.t)
            var u = float(entry.u)
            var cell = base_cell + Vector2i(x, y)
            match b:
                BIOME_SEA:
                    if src_ids.has("shore"):
                        tm.set_cell(0, cell, src_ids["shore"], Vector2i(4, 0), 0) # water frame 5
                BIOME_BEACH:
                    if src_ids.has("shore"):
                        var k = clamp((h + 0.3) / 0.1, 0.0, 1.0)
                        var f0 = int(round(4 - k * 3))
                        tm.set_cell(0, cell, src_ids["shore"], Vector2i(f0 - 1, 0), 0)
                BIOME_DESERT:
                    if src_ids.has("shore"):
                        var f1 = 1 if rng.randf() > 0.05 else 2
                        tm.set_cell(0, cell, src_ids["shore"], Vector2i(f1 - 1, 0), 0)
                BIOME_TEMPERATE:
                    if src_ids.has("grass"):
                        var is_edge = _neighbor_differs_map(biome_map, tiles_x, tiles_y, x, y, BIOME_TEMPERATE)
                        var fr = 4
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
                        # Chickens prefer open grass: when not in clustered trees and moderate humidity
                        if map_node and map_node.has_method("spawn_chicken_group_once"):
                            var open_grass := (not is_edge) and (u < 0.55)
                            # Use cluster noise as proxy for tree density
                            var cluster_v = _n01(_noise_cluster.get_noise_2d(cell.x, cell.y))
                            if open_grass and cluster_v < 0.5:
                                if rng.randf() < 0.0015: # rare per tile
                                    map_node.spawn_chicken_group_once(Vector2(cell.x, cell.y), 3, 8)
                BIOME_TAIGA:
                    if src_ids.has("winter"):
                        tm.set_cell(0, cell, src_ids["winter"], Vector2i(5, 0), 0) # gray base
                BIOME_TUNDRA:
                    if src_ids.has("dead"):
                        var fr2 = 4
                        var r1 = rng.randf()
                        if r1 >= 0.95:
                            fr2 = 5 if r1 < 0.975 else 6
                        var idx2 = fr2 - 1
                        var col2 = idx2 % FRAME_COLS
                        var row2 = int(idx2 / float(FRAME_COLS))
                        tm.set_cell(0, cell, src_ids["dead"], Vector2i(col2, row2), 0)
                        # Very rare chickens wandering in sparse tundra clearings
                        if map_node and map_node.has_method("spawn_chicken_group_once"):
                            var cluster_v2 = _n01(_noise_cluster.get_noise_2d(cell.x, cell.y))
                            if cluster_v2 < 0.45 and rng.randf() < 0.001:
                                map_node.spawn_chicken_group_once(Vector2(cell.x, cell.y), 3, 6)
                BIOME_SNOW_MOUNTAIN:
                    if src_ids.has("winter"):
                        tm.set_cell(0, cell, src_ids["winter"], Vector2i(4, 0), 0) # snow base

            # Decorations per-biome (clustered patches)
            if map_node:
                var tile = Vector2(cell.x, cell.y)
                # compute cluster mask once per tile (0..1)
                var cval = _n01(_noise_cluster.get_noise_2d(cell.x, cell.y))

                if b == BIOME_TEMPERATE and u > 0.35 and map_node.has_method("spawn_tree_entry"):
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
                        var p_tf = lerp(0.01, 0.12, clamp((u - 0.35) / 0.65, 0.0, 1.0))
                        if rng.randf() < p_tf:
                            var type_name_tf2 = ["oak", "pine", "birch"][rng.randi_range(0,2)]
                            var type_idx_tf2 = TreeConfig.frame_for_type_name(type_name_tf2)
                            var slot_tf2 = -1
                            if map_node.has_method("get_free_resource_slot"):
                                slot_tf2 = map_node.get_free_resource_slot(tile)
                            if slot_tf2 != -1:
                                map_node.spawn_tree_entry("trees", type_idx_tf2, tile, slot_tf2)

                    # Neighbor-aware fill
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

                elif b == BIOME_BEACH:
                    if rng.randf() < 0.04 and map_node.has_method("spawn_tree_entry"):
                        var palm = [3,4,5,6][rng.randi_range(0,3)]
                        var slot = -1
                        if map_node.has_method("get_free_resource_slot"):
                            slot = map_node.get_free_resource_slot(tile)
                        if slot != -1:
                            map_node.spawn_tree_entry("coconut", palm, tile, slot)
                    # Chickens also roam beaches occasionally (few trees)
                    if map_node and map_node.has_method("spawn_chicken_group_once") and rng.randf() < 0.001:
                        map_node.spawn_chicken_group_once(Vector2(cell.x, cell.y), 3, 6)

                elif b == BIOME_DESERT:
                    if map_node.has_method("spawn_tree_entry"):
                        var cactus_clustered = cval > 0.78 and rng.randf() < 0.30
                        if cactus_clustered:
                            var count_cx = 1 + rng.randi_range(0, 1)
                            for i_cx in range(count_cx):
                                var cframe = rng.randi_range(1, TreeConfig.CACTUS_COLS * TreeConfig.CACTUS_ROWS)
                                var slot_cx = -1
                                if map_node.has_method("get_free_resource_slot"):
                                    slot_cx = map_node.get_free_resource_slot(tile)
                                if slot_cx == -1:
                                    break
                                map_node.spawn_tree_entry("cactus", cframe, tile, slot_cx)
                        else:
                            if rng.randf() < 0.010:
                                var cframe2 = rng.randi_range(1, TreeConfig.CACTUS_COLS * TreeConfig.CACTUS_ROWS)
                                var slot_c2 = -1
                                if map_node.has_method("get_free_resource_slot"):
                                    slot_c2 = map_node.get_free_resource_slot(tile)
                                if slot_c2 != -1:
                                    map_node.spawn_tree_entry("cactus", cframe2, tile, slot_c2)
                    # rare oasis palms
                    if u > 0.65 and cval > 0.7 and rng.randf() < 0.015 and map_node.has_method("spawn_tree_entry"):
                        var palm2 = [3,4,5,6][rng.randi_range(0,3)]
                        var slot_p2 = -1
                        if map_node.has_method("get_free_resource_slot"):
                            slot_p2 = map_node.get_free_resource_slot(tile)
                        if slot_p2 != -1:
                            map_node.spawn_tree_entry("coconut", palm2, tile, slot_p2)
                    if rng.randf() < 0.02 and map_node.has_method("register_tumbleweed"):
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
                            sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
                            sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
                            map_node.add_child(sp)
                            var dir = Vector2(-1, 0)
                            var speed = tile_size * rng.randf_range(0.15, 0.35)
                            map_node.register_tumbleweed(sp, at, fw, fh, frame_tw, dir, speed)

                elif b == BIOME_TAIGA:
                    if map_node.has_method("spawn_tree_entry"):
                        if cval > 0.55:
                            var count_pg = 2 + rng.randi_range(0, 1)
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

                elif b == BIOME_TUNDRA:
                    if map_node.has_method("spawn_tree_entry"):
                        if cval > 0.56:
                            var count_dt = 2 + rng.randi_range(0, 2)
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
                        var frame_r = rng.randi_range(10, 12)
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
                        sp_r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
                        sp_r.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
                        map_node.add_child(sp_r)
                        map_node.register_rock_node(sp_r)

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
                        sp2.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
                        sp2.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
                        map_node.add_child(sp2)
                        map_node.register_rock_node(sp2)

    return tm

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
