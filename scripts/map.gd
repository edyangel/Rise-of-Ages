extends Node2D

# Grid map: each tile is TILE_SIZE x TILE_SIZE
# NOTE: tiles can be treated as chunks; objects/structures occupy parts of tiles or multiple tiles
const TILE_SIZE = 48
const MAP_W = 80
const MAP_H = 60

# Chunk streaming config (tiles per chunk and streaming behavior)
const CHUNK_TILES_X := 32
const CHUNK_TILES_Y := 32
const VIEW_RADIUS_CHUNKS := 2 # how many chunks around each unit to keep loaded
const UNLOAD_DELAY_SEC := 30.0

# for demo, spawn constructors in a few tiles
var units: Array = []
var selected_unit = null
var selected_units: Array = []
# tile occupancy: map from "x,y" -> Array[5] of unit or null
var tile_slots := {}
var unit_slot := {} # map unit -> {tile=Vector2, slot=int}
var resource_slots := {} # tile_key -> Array[5] of null|"TREE"|"TRUNK"
var tile_blockers := {} # tile_key -> StaticBody2D to block movement when dense

# random world decorations (tile coords)
var trees: Array = []
var golds: Array = []
var rocks: Array = []
var tumbleweeds: Array = []
var tree_atlas: Texture2D = null
var cactus_atlas: Texture2D = null
var coconut_atlas: Texture2D = null
var dead_atlas: Texture2D = null
var wdead_atlas: Texture2D = null
var pine_atlas: Texture2D = null
var wintertrees_atlas: Texture2D = null
var rocks_atlas: Texture2D = null
var tumbleweed_atlas: Texture2D = null
var _hp_overlay: Node2D = null
var _sel_overlay: Node2D = null
const TREE_COUNT = 60
const CACTUS_COUNT = 20
const COCONUT_COUNT = 12
const DEADTREE_COUNT = 16
const PINETREE_COUNT = 12
const WDEAD_COUNT = 10
const WINTREES_COUNT = 14
const ROCKS_COUNT = 32
const TUMBLEWEED_COUNT = 6
const GOLD_COUNT = 20
const TREE_COLS = 4
const SHOW_GRID := false
const USE_PROCEDURAL_BIOMES := true
var WORLD_SEED: int = 12345

# Chunk streaming state
var _terrain: Node = null
var _chunk_builder: Node = null
var _chunk_nodes := {}        # key "cx,cy" -> TileMap (or Node) of the chunk
var _chunk_last_seen := {}    # key -> last time (seconds) it was within view radius
var _stream_accum := 0.0

# --- Chunk Streaming Helpers ---
func _chunk_key(cx: int, cy: int) -> String:
	return "%d,%d" % [cx, cy]

func _tile_to_chunk(tile: Vector2) -> Vector2i:
	return Vector2i(int(floor(tile.x / CHUNK_TILES_X)), int(floor(tile.y / CHUNK_TILES_Y)))

func _ensure_chunk_loaded(cx: int, cy: int) -> void:
	if _terrain == null:
		return
	var key = _chunk_key(cx, cy)
	_chunk_last_seen[key] = Time.get_unix_time_from_system()
	if _chunk_nodes.has(key) and _chunk_nodes[key] != null:
		return
	# compute tiles for edge chunks not to exceed MAP bounds
	var base_tx = cx * CHUNK_TILES_X
	var base_ty = cy * CHUNK_TILES_Y
	if base_tx >= MAP_W or base_ty >= MAP_H:
		return
	var tiles_x = min(CHUNK_TILES_X, MAP_W - base_tx)
	var tiles_y = min(CHUNK_TILES_Y, MAP_H - base_ty)
	var node = null
	if USE_PROCEDURAL_BIOMES and _terrain and _terrain.has_method("create_biome_chunk_tilemap"):
		node = _terrain.create_biome_chunk_tilemap(self, Vector2(cx, cy), tiles_x, tiles_y, TILE_SIZE, WORLD_SEED)
	elif _chunk_builder and _chunk_builder.has_method("create_tilemap_chunk"):
		node = _chunk_builder.create_tilemap_chunk(self, Vector2i(cx, cy), tiles_x, tiles_y, "", false, 0)
	if node != null:
		_chunk_nodes[key] = node
		_chunk_last_seen[key] = Time.get_unix_time_from_system()

func _maybe_unload_old_chunks() -> void:
	var now = Time.get_unix_time_from_system()
	var to_remove := []
	for key in _chunk_nodes.keys():
		var last = float(_chunk_last_seen.get(key, 0.0))
		if now - last > UNLOAD_DELAY_SEC:
			to_remove.append(key)
	for k in to_remove:
		var node = _chunk_nodes[k]
		if node and is_instance_valid(node):
			node.queue_free()
		_chunk_nodes.erase(k)
		# keep last_seen so we don't thrash; will be refreshed when reloaded

func _update_chunk_streaming(_force_all: bool) -> void:
	# collect centers in chunk space for all active units (farmers)
	var centers := []
	for u in units:
		if not (u and u is Node2D):
			continue
		var tile = Vector2(int(floor(u.global_position.x / TILE_SIZE)), int(floor(u.global_position.y / TILE_SIZE)))
		var ch = _tile_to_chunk(tile)
		centers.append(ch)
	# include selection center if no units
	if centers.size() == 0:
		centers.append(Vector2i(0,0))
	# load around centers within VIEW_RADIUS_CHUNKS
	for c in centers:
		for dy in range(-VIEW_RADIUS_CHUNKS, VIEW_RADIUS_CHUNKS + 1):
			for dx in range(-VIEW_RADIUS_CHUNKS, VIEW_RADIUS_CHUNKS + 1):
				var cx = c.x + dx
				var cy = c.y + dy
				_ensure_chunk_loaded(cx, cy)
	# unload chunks not seen in a while
	_maybe_unload_old_chunks()

# Drag-selection state
var drag_select_active: bool = false
var drag_select_start: Vector2 = Vector2.ZERO
var drag_select_current: Vector2 = Vector2.ZERO
const DRAG_THRESHOLD := 8.0
# Mobile double-tap to start drag-select
const DOUBLE_TAP_WINDOW := 0.35
var _last_touch_release_time := -1e9
var _drag_touch_id := -1

var TreeConfig = preload("res://scripts/tree_data.gd")
var chop_tasks := {}
var cut_queues := {} # unit -> Array of {tile:Vector2, slot:int}
var order_markers: Array = [] # [{pos:Vector2, ttl:float}] transient visuals for issued orders

func _ready():
	# randomize decorations
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	trees.clear()
	golds.clear()
	# load atlases (use central TreeData)
	if ResourceLoader.exists(TreeConfig.ATLAS):
		tree_atlas = load(TreeConfig.ATLAS)
	else:
		tree_atlas = null
	if ResourceLoader.exists(TreeConfig.CACTUS_ATLAS):
		cactus_atlas = load(TreeConfig.CACTUS_ATLAS)
	else:
		cactus_atlas = null
	if ResourceLoader.exists(TreeConfig.COCONUT_ATLAS):
		coconut_atlas = load(TreeConfig.COCONUT_ATLAS)
	else:
		coconut_atlas = null
	# optional atlases
	if ResourceLoader.exists(TreeConfig.DEAD_ATLAS):
		dead_atlas = load(TreeConfig.DEAD_ATLAS)
	else:
		dead_atlas = null
	if ResourceLoader.exists(TreeConfig.WDEAD_ATLAS):
		wdead_atlas = load(TreeConfig.WDEAD_ATLAS)
	else:
		wdead_atlas = null
	if ResourceLoader.exists(TreeConfig.PINE_ATLAS):
		pine_atlas = load(TreeConfig.PINE_ATLAS)
	else:
		pine_atlas = null
	if ResourceLoader.exists(TreeConfig.WINTREES_ATLAS):
		wintertrees_atlas = load(TreeConfig.WINTREES_ATLAS)
	else:
		wintertrees_atlas = null
	if ResourceLoader.exists(TreeConfig.ROCKS_ATLAS):
		rocks_atlas = load(TreeConfig.ROCKS_ATLAS)
	else:
		rocks_atlas = null
	if ResourceLoader.exists(TreeConfig.TUMBLEWEED_ATLAS):
		tumbleweed_atlas = load(TreeConfig.TUMBLEWEED_ATLAS)
	else:
		tumbleweed_atlas = null

	if not USE_PROCEDURAL_BIOMES:
		# place up to 5 trees per tile (random count) until reaching TREE_COUNT
		var placed := 0
		var guard := 0
		while placed < TREE_COUNT and guard < TREE_COUNT * 20:
			guard += 1
			var tile = Vector2(rng.randi_range(0, MAP_W - 1), rng.randi_range(0, MAP_H - 1))
			_ensure_resource_slots(tile)
			var k = _get_tile_key(tile)
			# compute free slots for trees on this tile
			var free_slots: Array = []
			for si in range(5):
				if resource_slots[k][si] == null:
					free_slots.append(si)
			if free_slots.size() == 0:
				continue
			# decide how many to place here this iteration
			var can_place = min(free_slots.size(), TREE_COUNT - placed)
			var to_place = rng.randi_range(1, can_place)
			# pick random unique slots
			for j in range(to_place):
				if free_slots.size() == 0:
					break
				var pick_idx = rng.randi_range(0, free_slots.size() - 1)
				var slot = int(free_slots[pick_idx])
				free_slots.remove_at(pick_idx)
				# choose tree type (default sheet "trees")
				var name_idx = rng.randi_range(0, TreeConfig.DEFAULT_TYPES.size() - 1)
				var type_name = TreeConfig.DEFAULT_TYPES[name_idx]
				var type_idx = TreeConfig.frame_for_type_name(type_name)
				# store and spawn node
				trees.append({"tile": tile, "slot": slot, "type": type_idx, "type_name": type_name, "sheet": "trees"})
				var new_idx = trees.size() - 1
				if tree_atlas:
					var tp = _world_pos_for_slot(tile, slot)
					var tw = int(tree_atlas.get_size().x / TreeConfig.FRAME_COLS)
					var th = int(tree_atlas.get_size().y)
					var at = AtlasTexture.new()
					at.atlas = tree_atlas
					at.region = Rect2(type_idx * tw, 0, tw, th)
					var s = Sprite2D.new()
					s.texture = at
					var tree_scale = 1.5
					s.position = tp
					s.scale = Vector2(tree_scale, tree_scale)
					s.centered = true
					s.z_index = 40
					# crisp pixel art
					s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
					s.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
					add_child(s)
					trees[new_idx]["node"] = s
					# attach a tiny trunk collider for realistic passage blocking
					_attach_trunk_collider(s, tw, th)
				resource_slots[k][slot] = "TREE"
				placed += 1
		# Spawn some cactus
	var cactus_spawned := 0
	var cactus_guard := 0
	while not USE_PROCEDURAL_BIOMES and cactus_spawned < CACTUS_COUNT and cactus_guard < CACTUS_COUNT * 20:
		cactus_guard += 1
		var tile = Vector2(rng.randi_range(0, MAP_W - 1), rng.randi_range(0, MAP_H - 1))
		_ensure_resource_slots(tile)
		var k = _get_tile_key(tile)
		var free_slots: Array = []
		for si in range(5):
			if resource_slots[k][si] == null:
				free_slots.append(si)
		if free_slots.size() == 0:
			continue
		var slot = int(free_slots[rng.randi_range(0, free_slots.size() - 1)])
		var frame_idx = rng.randi_range(1, TreeConfig.CACTUS_COLS * TreeConfig.CACTUS_ROWS)
		trees.append({"tile": tile, "slot": slot, "type": frame_idx, "type_name": "cactus%d" % frame_idx, "sheet": "cactus"})
		var new_idx2 = trees.size() - 1
		if cactus_atlas:
			var tp2 = _world_pos_for_slot(tile, slot)
			var fw = int(cactus_atlas.get_size().x / TreeConfig.CACTUS_COLS)
			var fh = int(cactus_atlas.get_size().y / TreeConfig.CACTUS_ROWS)
			var zero = frame_idx - 1
			var col = zero % TreeConfig.CACTUS_COLS
			var row = int(zero / float(TreeConfig.CACTUS_COLS))
			var at2 = AtlasTexture.new()
			at2.atlas = cactus_atlas
			at2.region = Rect2(col * fw, row * fh, fw, fh)
			var sc = Sprite2D.new()
			sc.texture = at2
			sc.position = tp2
			sc.scale = Vector2(1.5, 1.5)
			sc.centered = true
			sc.z_index = 40
			# crisp
			sc.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sc.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			add_child(sc)
			trees[new_idx2]["node"] = sc
			# add trunk collider
			_attach_trunk_collider(sc, fw, fh)
		resource_slots[k][slot] = "TREE"
		cactus_spawned += 1

	# Spawn some coconut palms (frames 3..6 are full palms)
	var coco_spawned := 0
	var coco_guard := 0
	while not USE_PROCEDURAL_BIOMES and coco_spawned < COCONUT_COUNT and coco_guard < COCONUT_COUNT * 20:
		coco_guard += 1
		var tile = Vector2(rng.randi_range(0, MAP_W - 1), rng.randi_range(0, MAP_H - 1))
		_ensure_resource_slots(tile)
		var k2 = _get_tile_key(tile)
		var free_slots2: Array = []
		for si in range(5):
			if resource_slots[k2][si] == null:
				free_slots2.append(si)
		if free_slots2.size() == 0:
			continue
		var slot2 = int(free_slots2[rng.randi_range(0, free_slots2.size() - 1)])
		var frame_coco = [3,4,5,6][rng.randi_range(0, 3)]
		trees.append({"tile": tile, "slot": slot2, "type": frame_coco, "type_name": "coconut", "sheet": "coconut"})
		var new_idx3 = trees.size() - 1
		if coconut_atlas:
			var tp3 = _world_pos_for_slot(tile, slot2)
			var fw3 = int(coconut_atlas.get_size().x / TreeConfig.COCONUT_COLS)
			var fh3 = int(coconut_atlas.get_size().y / TreeConfig.COCONUT_ROWS)
			var zero3 = frame_coco - 1
			var col3 = zero3 % TreeConfig.COCONUT_COLS
			var row3 = int(zero3 / float(TreeConfig.COCONUT_COLS))
			var at3 = AtlasTexture.new()
			at3.atlas = coconut_atlas
			at3.region = Rect2(col3 * fw3, row3 * fh3, fw3, fh3)
			var sp = Sprite2D.new()
			sp.texture = at3
			sp.position = tp3
			sp.scale = Vector2(1.5, 1.5)
			sp.centered = true
			sp.z_index = 40
			# crisp
			sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			add_child(sp)
			trees[new_idx3]["node"] = sp
			# add trunk collider
			_attach_trunk_collider(sp, fw3, fh3)
		resource_slots[k2][slot2] = "TREE"
		coco_spawned += 1

	# Spawn some dead trees (frames 3..4 live; 1..2 trunks)
	var dead_spawned := 0
	var dead_guard := 0
	while not USE_PROCEDURAL_BIOMES and dead_spawned < DEADTREE_COUNT and dead_guard < DEADTREE_COUNT * 20:
		dead_guard += 1
		var tile = Vector2(rng.randi_range(0, MAP_W - 1), rng.randi_range(0, MAP_H - 1))
		_ensure_resource_slots(tile)
		var kdt = _get_tile_key(tile)
		var free_slots_dt: Array = []
		for si in range(5):
			if resource_slots[kdt][si] == null:
				free_slots_dt.append(si)
		if free_slots_dt.size() == 0:
			continue
		var slot_dt = int(free_slots_dt[rng.randi_range(0, free_slots_dt.size() - 1)])
		var frame_dt = [3,4][rng.randi_range(0,1)]
		trees.append({"tile": tile, "slot": slot_dt, "type": frame_dt, "type_name": "dead", "sheet": "deadtrees"})
		var idx_dt = trees.size() - 1
		if dead_atlas:
			var tp_dt = _world_pos_for_slot(tile, slot_dt)
			var fw_dt = int(dead_atlas.get_size().x / TreeConfig.DEAD_COLS)
			var fh_dt = int(dead_atlas.get_size().y / TreeConfig.DEAD_ROWS)
			var z_dt = frame_dt - 1
			var col_dt = z_dt % TreeConfig.DEAD_COLS
			var row_dt = int(z_dt / float(TreeConfig.DEAD_COLS))
			var at_dt = AtlasTexture.new()
			at_dt.atlas = dead_atlas
			at_dt.region = Rect2(col_dt * fw_dt, row_dt * fh_dt, fw_dt, fh_dt)
			var sp_dt = Sprite2D.new()
			sp_dt.texture = at_dt
			sp_dt.position = tp_dt
			sp_dt.scale = Vector2(1.5, 1.5)
			sp_dt.centered = true
			sp_dt.z_index = 40
			# crisp
			sp_dt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp_dt.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			add_child(sp_dt)
			trees[idx_dt]["node"] = sp_dt
			# add trunk collider
			_attach_trunk_collider(sp_dt, fw_dt, fh_dt)
		resource_slots[kdt][slot_dt] = "TREE"
		dead_spawned += 1

	# Spawn some pines (2..3 are trees; 1 trunk)
	var pine_spawned := 0
	var pine_guard := 0
	while not USE_PROCEDURAL_BIOMES and pine_spawned < PINETREE_COUNT and pine_guard < PINETREE_COUNT * 20:
		pine_guard += 1
		var tile = Vector2(rng.randi_range(0, MAP_W - 1), rng.randi_range(0, MAP_H - 1))
		_ensure_resource_slots(tile)
		var kpn = _get_tile_key(tile)
		var free_slots_pn: Array = []
		for si in range(5):
			if resource_slots[kpn][si] == null:
				free_slots_pn.append(si)
		if free_slots_pn.size() == 0:
			continue
		var slot_pn = int(free_slots_pn[rng.randi_range(0, free_slots_pn.size() - 1)])
		var frame_pn = [2,3][rng.randi_range(0,1)]
		trees.append({"tile": tile, "slot": slot_pn, "type": frame_pn, "type_name": "pine", "sheet": "pinetrees"})
		var idx_pn = trees.size() - 1
		if pine_atlas:
			var tp_pn = _world_pos_for_slot(tile, slot_pn)
			var fw_pn = int(pine_atlas.get_size().x / TreeConfig.PINE_COLS)
			var fh_pn = int(pine_atlas.get_size().y / TreeConfig.PINE_ROWS)
			var z_pn = frame_pn - 1
			var col_pn = z_pn % TreeConfig.PINE_COLS
			var row_pn = int(z_pn / float(TreeConfig.PINE_COLS))
			var at_pn = AtlasTexture.new()
			at_pn.atlas = pine_atlas
			at_pn.region = Rect2(col_pn * fw_pn, row_pn * fh_pn, fw_pn, fh_pn)
			var sp_pn = Sprite2D.new()
			sp_pn.texture = at_pn
			sp_pn.position = tp_pn
			sp_pn.scale = Vector2(1.5, 1.5)
			sp_pn.centered = true
			sp_pn.z_index = 40
			# crisp
			sp_pn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp_pn.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			add_child(sp_pn)
			trees[idx_pn]["node"] = sp_pn
			# add trunk collider
			_attach_trunk_collider(sp_pn, fw_pn, fh_pn)
		resource_slots[kpn][slot_pn] = "TREE"
		pine_spawned += 1

	# Spawn some winter dead trees (3..4 live)
	var wdead_spawned := 0
	var wdead_guard := 0
	while not USE_PROCEDURAL_BIOMES and wdead_spawned < WDEAD_COUNT and wdead_guard < WDEAD_COUNT * 20:
		wdead_guard += 1
		var tile = Vector2(rng.randi_range(0, MAP_W - 1), rng.randi_range(0, MAP_H - 1))
		_ensure_resource_slots(tile)
		var kwd = _get_tile_key(tile)
		var free_slots_wd: Array = []
		for si in range(5):
			if resource_slots[kwd][si] == null:
				free_slots_wd.append(si)
		if free_slots_wd.size() == 0:
			continue
		var slot_wd = int(free_slots_wd[rng.randi_range(0, free_slots_wd.size() - 1)])
		var frame_wd = [3,4][rng.randi_range(0,1)]
		trees.append({"tile": tile, "slot": slot_wd, "type": frame_wd, "type_name": "wdead", "sheet": "winterdeadtrees"})
		var idx_wd = trees.size() - 1
		if wdead_atlas:
			var tp_wd = _world_pos_for_slot(tile, slot_wd)
			var fw_wd = int(wdead_atlas.get_size().x / TreeConfig.WDEAD_COLS)
			var fh_wd = int(wdead_atlas.get_size().y / TreeConfig.WDEAD_ROWS)
			var z_wd = frame_wd - 1
			var col_wd = z_wd % TreeConfig.WDEAD_COLS
			var row_wd = int(z_wd / float(TreeConfig.WDEAD_COLS))
			var at_wd = AtlasTexture.new()
			at_wd.atlas = wdead_atlas
			at_wd.region = Rect2(col_wd * fw_wd, row_wd * fh_wd, fw_wd, fh_wd)
			var sp_wd = Sprite2D.new()
			sp_wd.texture = at_wd
			sp_wd.position = tp_wd
			sp_wd.scale = Vector2(1.5, 1.5)
			sp_wd.centered = true
			sp_wd.z_index = 40
			# crisp
			sp_wd.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp_wd.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			add_child(sp_wd)
			trees[idx_wd]["node"] = sp_wd
			# add trunk collider
			_attach_trunk_collider(sp_wd, fw_wd, fh_wd)
		resource_slots[kwd][slot_wd] = "TREE"
		wdead_spawned += 1

	# Spawn some winter trees (4x4 grid; choose non-trunk frames)
	var wtrees_spawned := 0
	var wtrees_guard := 0
	while not USE_PROCEDURAL_BIOMES and wtrees_spawned < WINTREES_COUNT and wtrees_guard < WINTREES_COUNT * 20:
		wtrees_guard += 1
		var tile = Vector2(rng.randi_range(0, MAP_W - 1), rng.randi_range(0, MAP_H - 1))
		_ensure_resource_slots(tile)
		var kwt = _get_tile_key(tile)
		var free_slots_wt: Array = []
		for si in range(5):
			if resource_slots[kwt][si] == null:
				free_slots_wt.append(si)
		if free_slots_wt.size() == 0:
			continue
		var slot_wt = int(free_slots_wt[rng.randi_range(0, free_slots_wt.size() - 1)])
		var cols_wt = TreeConfig.WINTREES_COLS
		var rows_wt = TreeConfig.WINTREES_ROWS
		var frame_wt := 1
		# pick a non-trunk column (col 1..3), random row; prefer row 3 (snow) sometimes
		var row_choice = rng.randi_range(0, rows_wt - 1)
		if rng.randf() < 0.5:
			row_choice = rows_wt - 1
		var col_choice = rng.randi_range(1, cols_wt - 1) # avoid trunk at col 0
		frame_wt = row_choice * cols_wt + (col_choice + 1) # 1-based
		trees.append({"tile": tile, "slot": slot_wt, "type": frame_wt, "type_name": "wintertree", "sheet": "wintertrees"})
		var idx_wt = trees.size() - 1
		if wintertrees_atlas:
			var tp_wt = _world_pos_for_slot(tile, slot_wt)
			var fw_wt = int(wintertrees_atlas.get_size().x / cols_wt)
			var fh_wt = int(wintertrees_atlas.get_size().y / rows_wt)
			var z_wt = frame_wt - 1
			var col_wt = z_wt % cols_wt
			var row_wt2 = int(z_wt / float(cols_wt))
			var at_wt = AtlasTexture.new()
			at_wt.atlas = wintertrees_atlas
			at_wt.region = Rect2(col_wt * fw_wt, row_wt2 * fh_wt, fw_wt, fh_wt)
			var sp_wt = Sprite2D.new()
			sp_wt.texture = at_wt
			sp_wt.position = tp_wt
			sp_wt.scale = Vector2(1.5, 1.5)
			sp_wt.centered = true
			sp_wt.z_index = 40
			# crisp
			sp_wt.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp_wt.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			add_child(sp_wt)
			trees[idx_wt]["node"] = sp_wt
			# add trunk collider
			_attach_trunk_collider(sp_wt, fw_wt, fh_wt)
		resource_slots[kwt][slot_wt] = "TREE"
		wtrees_spawned += 1

	# Spawn decorative rocks
	var rocks_spawned := 0
	var rocks_guard := 0
	while not USE_PROCEDURAL_BIOMES and rocks_spawned < ROCKS_COUNT and rocks_guard < ROCKS_COUNT * 10:
		rocks_guard += 1
		if not rocks_atlas:
			break
		var tile = Vector2(rng.randi_range(0, MAP_W - 1), rng.randi_range(0, MAP_H - 1))
		var posr = _world_pos_for_slot(tile, rng.randi_range(0,4))
		var cols_r = TreeConfig.ROCKS_COLS
		var rows_r = TreeConfig.ROCKS_ROWS
		var frame_r = rng.randi_range(1, cols_r * rows_r)
		var z_r = frame_r - 1
		var col_r = z_r % cols_r
		var row_r = int(z_r / float(cols_r))
		var fw_r = int(rocks_atlas.get_size().x / cols_r)
		var fh_r = int(rocks_atlas.get_size().y / rows_r)
		var at_r = AtlasTexture.new()
		at_r.atlas = rocks_atlas
		at_r.region = Rect2(col_r * fw_r, row_r * fh_r, fw_r, fh_r)
		var sp_r = Sprite2D.new()
		sp_r.texture = at_r
		sp_r.position = posr
		sp_r.scale = Vector2(1.3, 1.3)
		sp_r.centered = true
		sp_r.z_index = 20
		# crisp
		sp_r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp_r.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		add_child(sp_r)
		rocks.append(sp_r)
		rocks_spawned += 1

	# Spawn tumbleweeds (rolling props)
	var tw_spawned := 0
	if tumbleweed_atlas and not USE_PROCEDURAL_BIOMES:
		while tw_spawned < TUMBLEWEED_COUNT:
			var ytile = rng.randi_range(0, MAP_H - 1)
			var left = rng.randf() < 0.5
			var posx = -TILE_SIZE * 0.5 if left else MAP_W * TILE_SIZE + TILE_SIZE * 0.5
			var posy = ytile * TILE_SIZE + TILE_SIZE * rng.randf()
			var frame_tw = rng.randi_range(1, 2)
			var fw_tw = int(tumbleweed_atlas.get_size().x / TreeConfig.TUMBLEWEED_COLS)
			var fh_tw = int(tumbleweed_atlas.get_size().y / TreeConfig.TUMBLEWEED_ROWS)
			var z_tw = frame_tw - 1
			var col_tw = z_tw % TreeConfig.TUMBLEWEED_COLS
			var row_tw = int(z_tw / float(TreeConfig.TUMBLEWEED_COLS))
			var at_tw = AtlasTexture.new()
			at_tw.atlas = tumbleweed_atlas
			at_tw.region = Rect2(col_tw * fw_tw, row_tw * fh_tw, fw_tw, fh_tw)
			var sp_tw = Sprite2D.new()
			sp_tw.texture = at_tw
			sp_tw.position = Vector2(posx, posy)
			sp_tw.scale = Vector2(1.2, 1.2)
			sp_tw.centered = true
			sp_tw.z_index = 10
			# crisp
			sp_tw.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sp_tw.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
			add_child(sp_tw)
			var dir = Vector2(1, 0) if left else Vector2(-1, 0)
			var speed = TILE_SIZE * rng.randf_range(0.15, 0.35)
			tumbleweeds.append({"node": sp_tw, "dir": dir, "speed": speed, "tex": at_tw, "fw": fw_tw, "fh": fh_tw, "frame": frame_tw, "timer": 0.0})
			tw_spawned += 1

	for i in range(GOLD_COUNT):
		golds.append(Vector2(rng.randi_range(0, MAP_W - 1), rng.randi_range(0, MAP_H - 1)))

	# initial draw requested via deferred update removed (use node-based sprites)
	# Setup streaming terrain using separated biome/chunk builders
	if Engine.is_editor_hint() == false:
		var BiomeScript = load("res://scripts/world/biome.gd") if ResourceLoader.exists("res://scripts/world/biome.gd") else null
		var ChunkScript = load("res://scripts/world/chunk.gd") if ResourceLoader.exists("res://scripts/world/chunk.gd") else null
		_terrain = BiomeScript.new() if BiomeScript != null else null
		_chunk_builder = ChunkScript.new() if ChunkScript != null else null
		if _terrain: add_child(_terrain)
		if _chunk_builder: add_child(_chunk_builder)
		# Prime streaming once at start
		_update_chunk_streaming(true)
	_spawn_demo_constructors()
	_spawn_demo_soldados()
	# Create HP overlay to render above sprites
	var overlay_script = load("res://scripts/ui/hp_overlay.gd") if ResourceLoader.exists("res://scripts/ui/hp_overlay.gd") else null
	var ov = Node2D.new()
	ov.name = "HpOverlay"
	ov.z_index = 1000
	if overlay_script:
		ov.set_script(overlay_script)
	add_child(ov)
	_hp_overlay = ov
	# selection overlay draws only the drag-rect; reduces redraw cost
	var sel_overlay := Node2D.new()
	sel_overlay.name = "SelectionOverlay"
	sel_overlay.z_index = 999
	var sel_script = load("res://scripts/ui/selection_overlay.gd")
	if sel_script:
		sel_overlay.set_script(sel_script)
	add_child(sel_overlay)
	_sel_overlay = sel_overlay
	set_process_input(true)

func _input(event):
	# Mouse: drag-select with LMB
	if event is InputEventMouseButton:
		var wp = get_global_mouse_position()
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			drag_select_start = wp
			drag_select_current = wp
			drag_select_active = false
			if _sel_overlay and _sel_overlay.has_method("clear"):
				_sel_overlay.call("clear")
			# don't single-select yet; decide on release
			return
		elif event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# release: finalize
			if drag_select_active:
				_finish_drag_select()
				if _sel_overlay and _sel_overlay.has_method("clear"):
					_sel_overlay.call("clear")
				return
			else:
				_handle_left_click(wp)
				return
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_handle_right_click(wp)
			return

	if event is InputEventMouseMotion:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			drag_select_current = get_global_mouse_position()
			if not drag_select_active:
				if drag_select_current.distance_to(drag_select_start) >= DRAG_THRESHOLD:
					drag_select_active = true
			if drag_select_active:
				if _sel_overlay and _sel_overlay.has_method("set_rect"):
					_sel_overlay.call("set_rect", drag_select_start, drag_select_current)
			return

	# Mobile: double-tap then hold and drag to select
	if event is InputEventScreenTouch:
		if event.pressed:
			var now = Time.get_unix_time_from_system()
			if now - _last_touch_release_time <= DOUBLE_TAP_WINDOW:
				# second tap begins drag-select
				_drag_touch_id = event.index
				drag_select_start = event.position
				drag_select_current = event.position
				drag_select_active = false
				if _sel_overlay and _sel_overlay.has_method("clear"):
					_sel_overlay.call("clear")
				return
		else:
			# touch released
			_last_touch_release_time = Time.get_unix_time_from_system()
			if _drag_touch_id == event.index:
				if drag_select_active:
					_finish_drag_select()
					if _sel_overlay and _sel_overlay.has_method("clear"):
						_sel_overlay.call("clear")
				_drag_touch_id = -1
				return

	if event is InputEventScreenDrag:
		if _drag_touch_id != -1 and event.index == _drag_touch_id:
			drag_select_current = event.position
			if not drag_select_active:
				if drag_select_current.distance_to(drag_select_start) >= DRAG_THRESHOLD:
					drag_select_active = true
			if drag_select_active:
				if _sel_overlay and _sel_overlay.has_method("set_rect"):
					_sel_overlay.call("set_rect", drag_select_start, drag_select_current)
			return


func _handle_left_click(world_pos: Vector2) -> void:
	# If multiple units are currently selected, a left click should clear selection
	if selected_units.size() > 1:
		_clear_selection()
		return
	# Select nearest unit within radius; else clear selection
	var radius = TILE_SIZE * 0.5
	var found = null
	var min_d = 1e9
	for c in units:
		var d = c.global_position.distance_to(world_pos)
		if d < radius and d < min_d:
			found = c
			min_d = d
	if found:
		_clear_selection()
		selected_unit = found
		selected_units = [found]
		if found.has_method("set_selected"):
			found.set_selected(true)
		return
	# empty click: clear all
	_clear_selection()

func _handle_right_click(world_pos: Vector2) -> void:
	# Determine the active selection list
	var sel: Array = []
	if selected_units.size() > 0:
		sel = selected_units.duplicate()
	elif selected_unit:
		sel = [selected_unit]
	else:
		return

	# Prefer trees in the clicked tile only to avoid scanning the whole list
	var dest_tile = Vector2(floor(world_pos.x / TILE_SIZE), floor(world_pos.y / TILE_SIZE))
	var nearest = null
	var nd = 1e9
	var tk = _get_tile_key(dest_tile)
	if resource_slots.has(tk):
		for si in range(5):
			if resource_slots[tk][si] != "TREE":
				continue
			# Find a live tree entry matching tile+slot
			for t in trees:
				if int(t.get("type", 0)) <= 0:
					continue
				if t["tile"] != dest_tile or int(t.get("slot", -1)) != si:
					continue
				var tp = _world_pos_for_slot(dest_tile, si)
				var d = tp.distance_to(world_pos)
				if d < nd:
					nd = d
					nearest = t
				break

	# If clicking right on a tree inside the clicked tile and very close, assign chopping; otherwise prefer move
	var chop_radius := TILE_SIZE * 0.35
	if nearest and nd < chop_radius:
		var tilev: Vector2 = nearest["tile"]
		var first_slot: int = int(nearest["slot"])
		var assigned_any := 0
		# Build smart queue: trees within 5 tiles from the clicked tree
		var queue_list := _find_neighbor_trees(tilev, 5)
		for u in sel:
			var assigned := false
			var used_tile := tilev
			var used_slot := first_slot
			# Try primary
			if start_chop(tilev, first_slot, u):
				assigned = true
				cut_queues[u] = queue_list.duplicate()
				if u and u.has_method("set_lumberjack"):
					u.set_lumberjack(true)
			else:
				# immediate fallback: try from queue
				var qcopy: Array = queue_list.duplicate()
				while qcopy.size() > 0 and not assigned:
					var nxt = qcopy.pop_front()
					used_tile = nxt.tile
					used_slot = int(nxt.slot)
					if start_chop(used_tile, used_slot, u):
						assigned = true
						cut_queues[u] = qcopy
						if u and u.has_method("set_lumberjack"):
							u.set_lumberjack(true)
						break
			if assigned:
				assigned_any += 1
				# add transient visual marker at assigned target
				var pos = _world_pos_for_slot(used_tile, used_slot)
				order_markers.append({"pos": pos, "ttl": 0.7})
		if assigned_any > 0:
			print("Assigned chopping to %d units near %s" % [assigned_any, str(tilev)])
			queue_redraw()
			return

	# Otherwise move: reserve slots on destination tile for up to 5 units
	var moved := 0
	for u in sel:
		# Cancel chopping assignment and disable lumberjack mode on pure move order
		_cancel_unit_chops(u)
		if u and u.has_method("set_lumberjack"):
			u.set_lumberjack(false)
		var reserved = _reserve_slot_for_unit(dest_tile, u)
		if reserved == -1:
			continue
		# Move to exact fixed slot in the destination tile
		var target = _world_pos_for_slot(dest_tile, reserved)
		if u and u.has_method("move_to"):
			u.move_to(target)
			moved += 1
	if moved == 0:
		print("Tile %s is full; no units moved" % str(dest_tile))

func _find_neighbor_trees(center_tile: Vector2, radius_tiles: int) -> Array:
	var res: Array = []
	for t in trees:
		if int(t.get("type", 0)) == 0:
			continue
		var tt: Vector2 = t["tile"]
		var dx = abs(int(tt.x) - int(center_tile.x))
		var dy = abs(int(tt.y) - int(center_tile.y))
		var cheb = max(dx, dy)
		if cheb <= radius_tiles:
			res.append({"tile": tt, "slot": int(t["slot"])})
	# sort by distance from center for consistent ordering
	res.sort_custom(func(a, b):
		var da = (a.tile - center_tile).length()
		var db = (b.tile - center_tile).length()
		return da < db
	)
	# drop the very first if it's exactly the center tree
	if res.size() > 0 and res[0].tile == center_tile:
		res.remove_at(0)
	return res

func _attempt_next_chop(unit) -> void:
	# 1) Try queued targets if exist
	if cut_queues.has(unit):
		var q: Array = cut_queues[unit]
		while q.size() > 0:
			var nxt = q.pop_front()
			if start_chop(nxt.tile, int(nxt.slot), unit):
				cut_queues[unit] = q
				return
		# queue exhausted
		cut_queues.erase(unit)

	# 2) No queue (or failed): pick next tree depending on unit mode
	if unit and unit is Node2D:
		# If unit is in lumberjack mode, constrain search to a 5-tile radius
		var use_radius := false
		if unit.has_method("is_lumberjack"):
			use_radius = bool(unit.is_lumberjack())
		if use_radius:
			var utile = Vector2(floor(unit.global_position.x / TILE_SIZE), floor(unit.global_position.y / TILE_SIZE))
			var np2 = _find_nearby_live_tree(utile, 5)
			if np2 != null and np2.has("tile"):
				if start_chop(np2.tile, int(np2.slot), unit):
					return
		else:
			var np = _find_nearest_live_tree(unit.global_position)
			if np != null and np.has("tile"):
				if start_chop(np.tile, int(np.slot), unit):
					return

	# 3) Nothing to chop: park the unit at a free slot in its current tile
	_park_unit(unit)

func _find_nearest_live_tree(from_pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e9
	for t in trees:
		if int(t.get("type", 0)) <= 0:
			continue
		var tilev: Vector2 = t["tile"]
		var slot: int = int(t["slot"])
		var pos = _world_pos_for_slot(tilev, slot)
		var d = from_pos.distance_to(pos)
		if d < best_d:
			best_d = d
			best = {"tile": tilev, "slot": slot}
	return best

func _find_nearby_live_tree(center_tile: Vector2, radius_tiles: int) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 1e9
	for t in trees:
		if int(t.get("type", 0)) <= 0:
			continue
		var tt: Vector2 = t["tile"]
		var dx = abs(int(tt.x) - int(center_tile.x))
		var dy = abs(int(tt.y) - int(center_tile.y))
		var cheb = max(dx, dy)
		if cheb > radius_tiles:
			continue
		var slot: int = int(t["slot"])
		var pos = _world_pos_for_slot(tt, slot)
		var d = pos.distance_to(center_tile * TILE_SIZE + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0))
		if d < best_d:
			best_d = d
			best = {"tile": tt, "slot": slot}
	return best

func _park_unit(unit) -> void:
	if not (unit and unit is Node2D):
		return
	var utile = Vector2(floor(unit.global_position.x / TILE_SIZE), floor(unit.global_position.y / TILE_SIZE))
	_ensure_tile_slots(utile)
	var reserved = _reserve_slot_for_unit(utile, unit)
	if reserved == -1:
		# try the 4-neighborhood as fallback
		var neighbors = [Vector2(1,0), Vector2(-1,0), Vector2(0,1), Vector2(0,-1)]
		for off in neighbors:
			var t2 = utile + off
			_ensure_tile_slots(t2)
			reserved = _reserve_slot_for_unit(t2, unit)
			if reserved != -1:
				var park_target = _world_pos_for_slot(t2, reserved)
				if unit.has_method("move_to"):
					unit.move_to(park_target)
				return
		# nothing found: stay; ensure idle animation by moving to current position
		if unit.has_method("move_to"):
			unit.move_to(unit.global_position)
		return
	# same-tile parking
	var target = _world_pos_for_slot(utile, reserved)
	if unit.has_method("move_to"):
		unit.move_to(target)

func _draw():
	# draw grid (debug only)
	if SHOW_GRID:
		for y in range(MAP_H):
			for x in range(MAP_W):
				var pos = Vector2(x * TILE_SIZE, y * TILE_SIZE)
				# tile border
				draw_rect(Rect2(pos, Vector2(TILE_SIZE, TILE_SIZE)), Color(0.15,0.9,0.15), false, 2)
				# draw 5-slot markers (center + 4 corners) as small green squares
				var base = pos + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
				var q = TILE_SIZE/4.0
				var s = Vector2(6,6)
				var c = Color(0.1,1.0,0.1,0.9)
				draw_rect(Rect2(base - s*0.5, s), c, true)
				draw_rect(Rect2(base + Vector2(-q,-q) - s*0.5, s), c, true)
				draw_rect(Rect2(base + Vector2(q,-q) - s*0.5, s), c, true)
				draw_rect(Rect2(base + Vector2(-q,q) - s*0.5, s), c, true)
				draw_rect(Rect2(base + Vector2(q,q) - s*0.5, s), c, true)

	# draw trees using atlas (Trees.png has 4 frames horizontally: 0=felled, 1..3 = live types)
	for t in trees:
		var tile = t["tile"]
		var slot = t["slot"]
		var k = _get_tile_key(tile)
		# debug: report if a live tree is drawn but resource slot already marked TRUNK
		if resource_slots.has(k) and resource_slots[k][slot] == "TRUNK":
			print("DRAW CONFLICT: live tree present at %s slot %d type=%d but slot marked TRUNK" % [str(tile), slot, int(t.get("type",1))])
		# if this tree has a node (Sprite2D) we've already created, skip immediate draw of sprite (but still show HP bar)
		var has_tree_node: bool = t.has("node") and t["node"] != null
		# if felled we draw a spawned trunk Sprite2D instead (created on chop finish)
		if int(t.get("type", 1)) == 0:
			continue
		var tp = _world_pos_for_slot(tile, slot)
		if not has_tree_node:
			var tree_scale = 1.5
			if tree_atlas:
				var frame_idx = clamp(int(t.get("type", 1)), 0, TreeConfig.FRAME_COLS - 1)
				var tw = int(tree_atlas.get_size().x / TreeConfig.FRAME_COLS)
				var th = int(tree_atlas.get_size().y)
				var src = Rect2(frame_idx * tw, 0, tw, th)
				var draw_w = tw * tree_scale
				var draw_h = th * tree_scale
				# position so the base of the tree sits on the slot position
				draw_texture_rect_region(tree_atlas, Rect2(tp - Vector2(draw_w / 2.0, draw_h), Vector2(draw_w, draw_h)), src)
			else:
				# fallback drawing (scaled)
				draw_line(tp, tp + Vector2(0,-40 * tree_scale), Color(0.36,0.2,0.09), 6)
				draw_circle(tp + Vector2(0,-50 * tree_scale), 12 * tree_scale, Color(0.1,0.45,0.1))



	# draw gold as golden circles
	for p in golds:
		var gp = (p * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		draw_circle(gp, 10, Color(1.0,0.84,0.0))

	# Selection rectangle is drawn by SelectionOverlay

	# transient order markers
	for m in order_markers:
		var alpha = clamp(m.ttl / 0.7, 0.0, 1.0)
		var col = Color(0.2, 1.0, 0.3, alpha)
		var radius = TILE_SIZE * (0.25 + 0.25 * (1.0 - alpha))
		draw_arc(m.pos, radius, 0.0, TAU, 24, col, 2.0)

func _current_selection_rect() -> Rect2:
	var p1 = drag_select_start
	var p2 = drag_select_current
	var top_left = Vector2(min(p1.x, p2.x), min(p1.y, p2.y))
	var size = Vector2(abs(p2.x - p1.x), abs(p2.y - p1.y))
	return Rect2(top_left, size)

func _finish_drag_select() -> void:
	var rect = _current_selection_rect()
	# Update selected states
	_clear_selection()
	for u in units:
		if not (u and u is Node2D):
			continue
		var pos: Vector2 = u.global_position
		if rect.has_point(pos):
			if u.has_method("set_selected"):
				u.set_selected(true)
			selected_units.append(u)
	# set primary selected_unit as first, if any
	if selected_units.size() > 0:
		selected_unit = selected_units[0]
	else:
		selected_unit = null
	# reset state and redraw
	drag_select_active = false
	queue_redraw()

func _clear_selection() -> void:
	if selected_unit and (not selected_units.has(selected_unit)):
		if selected_unit.has_method("set_selected"):
			selected_unit.set_selected(false)
	for u in selected_units:
		if u and u.has_method("set_selected"):
			u.set_selected(false)
	selected_units.clear()
	selected_unit = null

func _spawn_demo_constructors():
	var scene = load("res://scenes/units/constructor.tscn")
	var positions = [Vector2(1,1), Vector2(3,2), Vector2(6,4)]
	for p in positions:
		var inst = scene.instantiate()
		add_child(inst)
		units.append(inst)
		var tile = p
		var reserved = _reserve_slot_for_unit(tile, inst)
		if reserved == -1:
			# fallback: place at center
			inst.position = (p * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		else:
			inst.position = _world_pos_for_slot(tile, reserved)
		print("Spawned constructor at %s" % str(inst.position))

func _spawn_demo_soldados():
	var scene = load("res://scenes/units/farmer.tscn")
	# place three farmers near the center tile
	var center_tile = Vector2(int(MAP_W / 2.0), int(MAP_H / 2.0))
	var positions = [center_tile, center_tile + Vector2(1,0), center_tile + Vector2(-1,0)]
	for p in positions:
		var inst = scene.instantiate()
		add_child(inst)
		units.append(inst)
		var reserved = _reserve_slot_for_unit(p, inst)
		if reserved == -1:
			inst.position = (p * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
		else:
			inst.position = _world_pos_for_slot(p, reserved)
		print("Spawned farmer at %s" % str(inst.position))


func _get_tile_key(tile: Vector2) -> String:
	return "%d,%d" % [int(tile.x), int(tile.y)]

func _ensure_tile_slots(tile: Vector2) -> void:
	var k = _get_tile_key(tile)
	if not tile_slots.has(k):
		tile_slots[k] = [null, null, null, null, null]

func _ensure_resource_slots(tile: Vector2) -> void:
	var k = _get_tile_key(tile)
	if not resource_slots.has(k):
		resource_slots[k] = [null, null, null, null, null]

# Attach a small static trunk collider at the base of a tree sprite.
# frame_w/frame_h are the source atlas frame dimensions in pixels (pre-scale).
func _attach_trunk_collider(sp: Node2D, _frame_w: int, frame_h: int) -> void:
	if sp == null:
		return
	# Avoid duplicating if already present
	if sp.has_node("TrunkBody"):
		return
	var body := StaticBody2D.new()
	body.name = "TrunkBody"
	body.collision_layer = 1
	body.collision_mask = 1
	# Place near bottom-center of the sprite. Local coords before scale.
	var y_off := float(frame_h) * 0.5 - 2.0
	body.position = Vector2(0.0, y_off)
	var rect := RectangleShape2D.new()
	# Keep world size around 8x8 px (previously 6x6), regardless of sprite scale
	var s := Vector2.ONE
	if sp is Node2D:
		s = sp.scale
	var target := 8.0
	var local_size := Vector2(max(1.0, target / max(0.001, s.x)), max(1.0, target / max(0.001, s.y)))
	rect.size = local_size
	var cs := CollisionShape2D.new()
	cs.shape = rect
	body.add_child(cs)
	sp.add_child(body)

func _live_tree_count_in_tile(tile: Vector2) -> int:
	var k = _get_tile_key(tile)
	if not resource_slots.has(k):
		return 0
	var c := 0
	for si in range(5):
		if resource_slots[k][si] == "TREE":
			c += 1
	return c

func _update_tile_blocker(tile: Vector2) -> void:
	var k = _get_tile_key(tile)
	var count = _live_tree_count_in_tile(tile)
	if count >= 3:
		if not tile_blockers.has(k) or tile_blockers[k] == null:
			var body = StaticBody2D.new()
			body.name = "tile_blocker_%s" % k
			body.position = (tile * TILE_SIZE) + Vector2(TILE_SIZE/2.0, TILE_SIZE/2.0)
			body.z_index = 5
			body.collision_layer = 1
			body.collision_mask = 1
			var shape = RectangleShape2D.new()
			shape.size = Vector2(TILE_SIZE * 0.95, TILE_SIZE * 0.95)
			var cs = CollisionShape2D.new()
			cs.shape = shape
			body.add_child(cs)
			add_child(body)
			tile_blockers[k] = body
	else:
		if tile_blockers.has(k) and tile_blockers[k] != null:
			if tile_blockers[k].is_inside_tree():
				tile_blockers[k].queue_free()
			tile_blockers.erase(k)

func _find_free_slot(tile: Vector2) -> int:
	_ensure_tile_slots(tile)
	var k = _get_tile_key(tile)
	var arr = tile_slots[k]
	for i in range(arr.size()):
		if arr[i] == null:
			return i
	return -1

func _world_pos_for_slot(tile: Vector2, slot_idx: int) -> Vector2:
	var base = (tile * TILE_SIZE) + Vector2(TILE_SIZE / 2.0, TILE_SIZE / 2.0)
	var quarter = TILE_SIZE / 4.0
	match slot_idx:
		0:
			return base
		1:
			return base + Vector2(-quarter, -quarter)
		2:
			return base + Vector2(quarter, -quarter)
		3:
			return base + Vector2(-quarter, quarter)
		4:
			return base + Vector2(quarter, quarter)
	return base

func _reserve_slot_for_unit(tile: Vector2, unit) -> int:
	# free previous slot if any
	if unit_slot.has(unit):
		var prev = unit_slot[unit]
		var pk = _get_tile_key(prev.tile)
		if tile_slots.has(pk) and tile_slots[pk][prev.slot] == unit:
			tile_slots[pk][prev.slot] = null
		unit_slot.erase(unit)

	var free_idx = _find_free_slot(tile)
	if free_idx == -1:
		return -1
	var k = _get_tile_key(tile)
	tile_slots[k][free_idx] = unit
	unit_slot[unit] = {"tile": tile, "slot": free_idx}
	return free_idx

func _process(delta: float) -> void:
	# dynamic chunk streaming heartbeat
	_stream_accum += delta
	if _stream_accum >= 0.5:
		_stream_accum = 0.0
		_update_chunk_streaming(false)

	# advance chopping tasks
	var keys = chop_tasks.keys()
	for k in keys:
		var task = chop_tasks[k]
		var units_arr = task.units
		# Only count units that are actually inside the task tile
		var active := 0
		for u in units_arr:
			if not (u and u is Node2D):
				continue
			var utile = Vector2(floor(u.global_position.x / TILE_SIZE), floor(u.global_position.y / TILE_SIZE))
			if utile == task.tile:
				active += 1
				# Nudge units into chopping state so attack animation plays immediately
				if u.has_method("start_chopping"):
					var assigned_slot := int(task.slot)
					if task.has("assigned_slot") and task.assigned_slot.has(u):
						assigned_slot = int(task.assigned_slot[u])
					u.start_chopping(task.tile, assigned_slot)
		# If no active choppers, still keep task but don't tick
		if active > 0:
			# refresh tree HP bar visibility while being chopped
			var now_ts = Time.get_unix_time_from_system()
			for i in range(trees.size()):
				var tt = trees[i]
				if tt["tile"] == task.tile and int(tt.get("slot", -1)) == int(task.slot) and int(tt.get("type", 0)) > 0:
					tt["_hp_show_until"] = now_ts + 2.0
					if _hp_overlay:
						_hp_overlay.queue_redraw()
					break
			if not task.has("hp_remaining"):
				# Initialize from current tree HP so progress persists across task cancel/restart
				var cur_hp := 30
				for i in range(trees.size()):
					var tt = trees[i]
					if tt["tile"] == task.tile and int(tt.get("slot", -1)) == int(task.slot) and int(tt.get("type", 0)) > 0:
						cur_hp = int(tt.get("hp", 30))
						break
				task.hp_remaining = cur_hp
			if not task.has("tick_accum"):
				task.tick_accum = 0.0
			# Tick per-second wood and HP reduction
			task.tick_accum += delta
			if task.tick_accum >= 1.0:
				var ticks = int(floor(task.tick_accum))
				var total = active * ticks
				# Cap damage by current tree HP to avoid desync
				var cap_hp := int(task.hp_remaining)
				for i in range(trees.size()):
					var tt = trees[i]
					if tt["tile"] == task.tile and int(tt.get("slot", -1)) == int(task.slot) and int(tt.get("type", 0)) > 0:
						cap_hp = min(cap_hp, int(tt.get("hp", 30)))
						break
				var dmg = min(cap_hp, total)
				if dmg > 0:
					# award wood now (1 per second por farmer)
					var game = get_tree().get_current_scene()
					if game and game.has_method("add_wood"):
						game.add_wood(dmg)
					# lower HP on task and tree entry (keep them in sync)
					task.hp_remaining = max(0, int(task.hp_remaining) - dmg)
					for i in range(trees.size()):
						var tt = trees[i]
						if tt["tile"] == task.tile and int(tt.get("slot", -1)) == int(task.slot) and int(tt.get("type", 0)) > 0:
							if not tt.has("hp_max"):
								tt["hp_max"] = 30
							tt["hp"] = max(0, int(tt.get("hp", 30)) - dmg)
							# also ensure visibility extends at least 2s beyond last damage application
							tt["_hp_show_until"] = Time.get_unix_time_from_system() + 2.0
							if _hp_overlay:
								_hp_overlay.queue_redraw()
							break
					task.tick_accum -= float(ticks)
					queue_redraw()
			# Finish when HP depleted (by task or by tree entry)
			var hp_now := int(task.hp_remaining)
			if hp_now > 0:
				# double-check per-tree HP in case of desync
				for i in range(trees.size()):
					var tt2 = trees[i]
					if tt2["tile"] == task.tile and int(tt2.get("slot", -1)) == int(task.slot) and int(tt2.get("type", 0)) > 0:
						hp_now = min(hp_now, int(tt2.get("hp", 30)))
						break
			if hp_now <= 0:
				# Only chop if still has assignees (avoid chopping stale targets)
				if task.units.size() > 0:
					chop_tree_at(task.tile, task.slot)
				# notify units and attempt next queued tree
				for u in units_arr:
					if u and u.has_method("stop_chopping"):
						u.stop_chopping()
					_attempt_next_chop(u)
				# free unit reservations that belong to this finished task's tile (avoid wiping new assignments)
				for u in units_arr:
					# clear any assigned approach target stored on the task
					if task.has("approach") and task.approach.has(u):
						task.approach.erase(u)
					if u and unit_slot.has(u):
						var prev = unit_slot[u]
						# only clear if reservation is on the finished tile
						if prev.tile == task.tile:
							var pk = _get_tile_key(prev.tile)
							if tile_slots.has(pk) and tile_slots[pk][prev.slot] == u:
								tile_slots[pk][prev.slot] = null
							unit_slot.erase(u)
				chop_tasks.erase(k)

	# update transient order markers
	if order_markers.size() > 0:
		for i in range(order_markers.size() - 1, -1, -1):
			order_markers[i].ttl -= delta
			if order_markers[i].ttl <= 0.0:
				order_markers.remove_at(i)
		queue_redraw()

	# move tumbleweeds
	if tumbleweeds.size() > 0:
		var left_bound = -TILE_SIZE
		var right_bound = MAP_W * TILE_SIZE + TILE_SIZE
		for tw in tumbleweeds:
			if tw.has("node") and tw.node and tw.node is Node2D:
				tw.node.position += tw.dir * tw.speed * delta
				# animate between 2 frames while rolling
				tw.timer += delta
				if tw.timer >= 0.15:
					tw.timer = 0.0
					tw.frame = 1 if tw.frame == 2 else 2
					var z_tw = tw.frame - 1
					var col_tw = z_tw % TreeConfig.TUMBLEWEED_COLS
					var row_tw = int(z_tw / float(TreeConfig.TUMBLEWEED_COLS))
					if tw.has("tex") and tw.tex:
						tw.tex.region = Rect2(col_tw * tw.fw, row_tw * tw.fh, tw.fw, tw.fh)
				# wrap around
				if tw.dir.x > 0 and tw.node.position.x > right_bound:
					tw.node.position.x = left_bound
				elif tw.dir.x < 0 and tw.node.position.x < left_bound:
					tw.node.position.x = right_bound

func start_chop(tile: Vector2, slot: int, unit) -> bool:
	# cancel any previous chopping assignments for this unit
	_cancel_unit_chops(unit)
	# reserve slot
	# ensure this tile+slot has a live tree
	var has_live := false
	for t in trees:
		if t["tile"] == tile and int(t.get("slot", -1)) == slot and int(t.get("type", 0)) > 0:
			has_live = true
			break
	if not has_live:
		if unit and unit.has_method("stop_chopping"):
			unit.stop_chopping()
		return false
	var reserved = _reserve_slot_for_unit(tile, unit)
	if reserved == -1:
		if unit and unit.has_method("stop_chopping"):
			unit.stop_chopping()
		return false
	# build task key
	var key = _get_tile_key(tile) + ":" + str(slot)
	if not chop_tasks.has(key):
		# Initialize hp_remaining from current tree HP to preserve progress
		var cur_hp := 30
		for i in range(trees.size()):
			var et = trees[i]
			if et["tile"] == tile and int(et.get("slot", -1)) == slot and int(et.get("type", 0)) > 0:
				cur_hp = int(et.get("hp", 30))
				break
		chop_tasks[key] = {"tile": tile, "slot": slot, "units": [], "approach": {}, "assigned_slot": {}, "hp_remaining": cur_hp, "tick_accum": 0.0}
	var task = chop_tasks[key]
	if not task.units.has(unit):
		task.units.append(unit)
		# assign exact slot center (no random approach) so units park at the 5 fixed points
		var base = _world_pos_for_slot(tile, slot)
		task.approach[unit] = base
		task.assigned_slot[unit] = slot
	# mark tree as recently chopped to show HP bar
	for i in range(trees.size()):
		var et = trees[i]
		if et["tile"] == tile and int(et.get("slot", -1)) == slot and int(et.get("type", 0)) > 0:
			et["_hp_show_until"] = Time.get_unix_time_from_system() + 2.0
			queue_redraw()
			if _hp_overlay:
				_hp_overlay.queue_redraw()
			break
	# instruct unit to move to slot
	var target = _world_pos_for_slot(tile, slot)
	if unit and unit.has_method("move_to"):
		# move exactly to the slot center (or task.approach which equals slot center)
		if chop_tasks.has(key) and chop_tasks[key].has("approach") and chop_tasks[key].approach.has(unit):
			unit.move_to(chop_tasks[key].approach[unit])
		else:
			unit.move_to(target)
	return true

func _cancel_unit_chops(unit) -> void:
	# Remove unit from any existing chop tasks and free its reserved slot
	var keys = chop_tasks.keys()
	for k in keys:
		var task = chop_tasks[k]
		if task.units.has(unit):
			task.units.erase(unit)
			if task.has("approach") and task.approach.has(unit):
				task.approach.erase(unit)
			if task.has("assigned_slot") and task.assigned_slot.has(unit):
				task.assigned_slot.erase(unit)
			# stop unit chopping animation/state if it was chopping this task
			if unit and unit.has_method("stop_chopping"):
				unit.stop_chopping()
			# free reservation for this unit if present
			if unit_slot.has(unit):
				var prev = unit_slot[unit]
				var pk = _get_tile_key(prev.tile)
				if tile_slots.has(pk) and tile_slots[pk][prev.slot] == unit:
					tile_slots[pk][prev.slot] = null
				unit_slot.erase(unit)
			# if no more units assigned, drop the task
			if task.units.size() == 0:
				chop_tasks.erase(k)

func chop_tree_at(tile: Vector2, slot_idx: int) -> bool:
	# remove all matching live tree entries for this tile+slot (collect indices)
	var matches := []
	for i in range(trees.size()):
		var tt = trees[i]
		if tt["tile"] == tile and tt["slot"] == slot_idx and int(tt.get("type", 0)) > 0:
			matches.append(i)

	if matches.size() == 0:
		return false

	# resource yield
	var game = get_tree().get_current_scene()
	var base_yield_wood := 1
	var extra_food := 0
	# decide trunk sprite and yield based on first matched entry
	var first_entry = trees[matches[0]] if matches.size() > 0 else {}
	var sheet := String(first_entry.get("sheet", "trees"))
	var fidx := int(first_entry.get("type", 1))
	if sheet == "coconut":
		var food_dict = TreeConfig.food_yield_for("coconut", fidx)
		extra_food = int(food_dict.get("food", 0))
	if game and game.has_method("add_wood") and base_yield_wood > 0:
		game.add_wood(base_yield_wood)
	if extra_food > 0 and game and game.has_method("add_food"):
		game.add_food(extra_food)
	print("chop_tree_at: tile=%s slot=%d felled %d entries sheet=%s" % [str(tile), slot_idx, matches.size(), sheet])

	# stop any choppers stuck on this tile/slot
	_stop_choppers_on(tile, slot_idx)

	# spawn a single trunk Sprite2D (varies by sheet)
	var tp = _world_pos_for_slot(tile, slot_idx)
	var trunk_frame = TreeConfig.trunk_frame_for(sheet, fidx)
	var tex: Texture2D = TreeConfig.texture_for(sheet)
	if tex and trunk_frame >= 0:
		var cols = TreeConfig.sheet_cols(sheet)
		var rows = TreeConfig.sheet_rows(sheet)
		var fw = int(tex.get_size().x / cols)
		var fh = int(tex.get_size().y / rows)
		var zero = trunk_frame
		# most sheets are 1-based; legacy "trees" is 0-based at trunk
		if sheet != "trees":
			zero = trunk_frame - 1
		var col = zero % cols
		var row = int(zero / float(cols))
		var at_tex = AtlasTexture.new()
		at_tex.atlas = tex
		at_tex.region = Rect2(col * fw, row * fh, fw, fh)
		var sp_tr = Sprite2D.new()
		sp_tr.texture = at_tex
		sp_tr.position = tp
		sp_tr.scale = Vector2(1.5, 1.5)
		sp_tr.centered = true
		sp_tr.z_index = 50
		# crisp pixel art for trunk sprite
		sp_tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp_tr.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
		add_child(sp_tr)
	# cactus: no trunk (trunk_frame = -1) so nothing spawned

	# mark slot as TRUNK in resource map
	var pk = _get_tile_key(tile)
	if resource_slots.has(pk):
		resource_slots[pk][slot_idx] = "TRUNK"
	# No tile blockers; per-tree colliders handle passage

	# remove the matched entries explicitly (reverse order to keep indices valid)
	var removed_matched = 0
	for i in range(matches.size() - 1, -1, -1):
		var idx = matches[i]
		if idx >= 0 and idx < trees.size():
			# free any node child first
			var entry = trees[idx]
			if entry.has("node") and entry["node"] != null and entry["node"].is_inside_tree():
				entry["node"].queue_free()
				entry["node"] = null
			trees.remove_at(idx)
			removed_matched += 1

	# also remove any other tree entries that overlap this world position (cleanup duplicates)
	# use a slightly larger threshold to tolerate slot offsets and rounding
	var removed_overlap = 0
	var cleanup_radius = TILE_SIZE * 0.25 # ~12 pixels
	for i in range(trees.size() - 1, -1, -1):
		var tt = trees[i]
		var tpos = _world_pos_for_slot(tt["tile"], tt["slot"])
		if tpos.distance_to(tp) <= cleanup_radius:
			# free node if present
			if tt.has("node") and tt["node"] != null and tt["node"].is_inside_tree():
				tt["node"].queue_free()
				tt["node"] = null
			trees.remove_at(i)
			removed_overlap += 1
	print("chop_tree_at: removed matched=%d overlap=%d entries" % [removed_matched, removed_overlap])

	return true

func _stop_choppers_on(tile: Vector2, slot_idx: int) -> void:
	# Safety: stop any units still flagged as chopping this tile/slot (e.g., if desync)
	for u in units:
		if not (u and u.has_method("stop_chopping")):
			continue
		var is_chopping := false
		var utile := Vector2.ZERO
		var uslot := -1
		# Access internal state (GDScript allows accessing vars via get)
		var ic = u.get("_is_chopping") if u else null
		if typeof(ic) == TYPE_BOOL and ic:
			is_chopping = true
			var ct = u.get("_chop_tile")
			var cs = u.get("_chop_slot")
			if ct != null:
				utile = ct
			if cs != null:
				uslot = int(cs)
		if is_chopping and utile == tile and uslot == slot_idx:
			u.stop_chopping()

# Helper APIs used by terrain.gd to integrate decorations into the map
func get_free_resource_slot(tile: Vector2) -> int:
	_ensure_resource_slots(tile)
	var k = _get_tile_key(tile)
	# Return any free slot (0..4), including center; blockers handle passability when dense
	var free: Array = []
	for si in range(5):
		if resource_slots[k][si] == null:
			free.append(si)
	if free.size() == 0:
		return -1
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	return int(free[rng.randi_range(0, free.size() - 1)])

func spawn_tree_entry(sheet: String, frame_idx: int, tile: Vector2, slot: int) -> void:
	if slot == -1:
		slot = get_free_resource_slot(tile)
		if slot == -1:
			return
	_ensure_resource_slots(tile)
	var k = _get_tile_key(tile)
	if resource_slots[k][slot] != null:
		return
	var tex: Texture2D = TreeConfig.texture_for(sheet)
	if tex == null:
		return
	var cols = TreeConfig.sheet_cols(sheet)
	var rows = TreeConfig.sheet_rows(sheet)
	var fw = int(tex.get_size().x / cols)
	var fh = int(tex.get_size().y / rows)
	var zero = frame_idx
	if sheet != "trees":
		zero = frame_idx - 1
	var col = zero % cols
	var row = int(zero / float(cols))
	var at = AtlasTexture.new()
	at.atlas = tex
	at.region = Rect2(col * fw, row * fh, fw, fh)
	var sp = Sprite2D.new()
	sp.texture = at
	sp.position = _world_pos_for_slot(tile, slot)
	sp.scale = Vector2(1.5, 1.5)
	sp.centered = true
	sp.z_index = 40
	# crisp pixel art for spawned trees/decorations
	sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sp.texture_repeat = CanvasItem.TEXTURE_REPEAT_DISABLED
	add_child(sp)
	# Initialize per-tree HP so wood yields per second are tracked (30 total)
	var hpv := 30
	trees.append({"tile": tile, "slot": slot, "type": frame_idx, "type_name": sheet, "sheet": sheet, "node": sp, "hp_max": hpv, "hp": hpv, "_hp_show_until": -1e9})
	resource_slots[k][slot] = "TREE"
	# Add a small trunk collider instead of tile-wide blockers
	var cols2 = TreeConfig.sheet_cols(sheet)
	var rows2 = TreeConfig.sheet_rows(sheet)
	var tex2: Texture2D = TreeConfig.texture_for(sheet)
	if tex2:
		var fw2 = int(tex2.get_size().x / cols2)
		var fh2 = int(tex2.get_size().y / rows2)
		_attach_trunk_collider(sp, fw2, fh2)

func register_tumbleweed(node: Node2D, atlas: AtlasTexture, fw: int, fh: int, frame: int, dir: Vector2, speed: float) -> void:
	tumbleweeds.append({"node": node, "tex": atlas, "fw": fw, "fh": fh, "frame": frame, "dir": dir, "speed": speed, "timer": 0.0})

func register_rock_node(node: Node2D) -> void:
	rocks.append(node)
