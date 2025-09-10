extends Node

# TileMap-based chunk builder using a 3x2 grass atlas (48x32)

const TILE_SIZE := 48
const FRAME_COLS := 3
const FRAME_ROWS := 2

@export var grass_texture_path: String = "res://MiniWorldSprites/Ground/TexturedGrass.png"

var BiomasUtil = preload("res://scripts/world/biomas.gd")

func create_tilemap_chunk(parent: Node, chunk_pos: Vector2i, tiles_x: int, tiles_y: int, texture_path: String = "", light_edges_on_chunk_border: bool = false, forced_frame: int = 0, detail_density: float = 0.025) -> TileMap:
    var atlas: Texture2D = null
    if texture_path != "" and ResourceLoader.exists(texture_path):
        atlas = load(texture_path)
    elif ResourceLoader.exists(grass_texture_path):
        atlas = load(grass_texture_path)
    if atlas == null:
        return null

    var tile_px := Vector2i(int(atlas.get_size().x / FRAME_COLS), int(atlas.get_size().y / FRAME_ROWS)) # 16x16

    var ts := TileSet.new()
    var src := TileSetAtlasSource.new()
    src.texture = atlas
    src.texture_region_size = tile_px
    for ry in range(FRAME_ROWS):
        for rx in range(FRAME_COLS):
            if not src.has_tile(Vector2i(rx, ry)):
                src.create_tile(Vector2i(rx, ry))
    ts.add_source(src)

    var tm := TileMap.new()
    tm.tile_set = ts
    tm.name = "chunk_tm_%d_%d" % [chunk_pos.x, chunk_pos.y]
    tm.z_as_relative = false
    tm.z_index = -100
    tm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
    tm.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
    tm.tile_set.tile_size = Vector2i(tile_px.x, tile_px.y) # 16x16 logical size
    # Render base textures at 1/4 area (half width/height) using 2x2 sub-tiles
    var SUB := 2
    # Previously 16->48 (3x,2x). Now 16->24 and 16->16 per sub-cell; four cells fill one world tile.
    tm.scale = Vector2(3.0 / float(SUB), 2.0 / float(SUB))

    var base_cell := Vector2i(chunk_pos.x * tiles_x * SUB, chunk_pos.y * tiles_y * SUB)
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
                var frame_idx := BiomasUtil.choose_grass_frame(rng, is_border, light_edges_on_chunk_border, detail_density)
                var p = BiomasUtil.atlas_frame_coords(frame_idx)
                col = p.x
                row = p.y
            # Fill 2x2 sub-cells for this world tile
            for sy in range(SUB):
                for sx in range(SUB):
                    tm.set_cell(0, base_cell + Vector2i(x * SUB + sx, y * SUB + sy), src_id, Vector2i(col, row), 0)

    if parent:
        parent.add_child(tm)
    return tm
