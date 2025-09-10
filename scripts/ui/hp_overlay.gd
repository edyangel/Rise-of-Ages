extends Node2D

var map_ref: Node2D = null
var _poll_accum := 0.0
const POLL_PERIOD := 0.1

func _ready():
	# try to discover the map node (assume parent)
	map_ref = get_parent()
	set_process(true)

func _process(delta: float) -> void:
	_poll_accum += delta
	if _poll_accum < POLL_PERIOD:
		return
	_poll_accum = 0.0
	# Redraw only when there are active bars to show (10Hz)
	if map_ref and map_ref.trees.size() > 0:
		var now_overlay = Time.get_unix_time_from_system()
		for t in map_ref.trees:
			if int(t.get("type", 0)) <= 0:
				continue
			var show_until = float(t.get("_hp_show_until", -1e9))
			if now_overlay <= show_until:
				queue_redraw()
				break

func _draw():
	if map_ref == null:
		return
	# Draw only the HP bars for trees while show window is active
	var TILE_SIZE: float = 48.0
	# Try to derive tile size from parent's slot positions if possible
	if map_ref and map_ref.has_method("_world_pos_for_slot") and map_ref.trees.size() > 0:
		var sample = map_ref.trees[0]
		var tp1: Vector2 = map_ref._world_pos_for_slot(sample.tile, 1)
		var tp2: Vector2 = map_ref._world_pos_for_slot(sample.tile, 2)
		var half = abs(tp2.x - tp1.x) # equals TILE_SIZE / 2
		if half > 0.0:
			TILE_SIZE = half * 2.0
	var now_overlay = Time.get_unix_time_from_system()
	for t in map_ref.trees:
		if int(t.get("type", 0)) <= 0:
			continue
		var show_until = float(t.get("_hp_show_until", -1e9))
		if now_overlay > show_until:
			continue
		var tile2 = t["tile"]
		var slot2 = t["slot"]
		var tp2: Vector2 = map_ref._world_pos_for_slot(tile2, slot2) if map_ref.has_method("_world_pos_for_slot") else Vector2.ZERO
		var hp_max2 := int(t.get("hp_max", 30))
		var hp_cur2 := int(t.get("hp", 30))
		var w2: float = TILE_SIZE * 0.6
		var h2: float = 4.0
		var off2 := Vector2(0, -TILE_SIZE * 0.6)
		var pos_bar2 = tp2 + off2 - Vector2(w2/2.0, 0)
		draw_rect(Rect2(pos_bar2 + Vector2(-1,-1), Vector2(w2+2, h2+2)), Color(0,0,0,0.6), true)
		var frac2: float = clamp(float(hp_cur2) / float(max(hp_max2,1)), 0.0, 1.0)
		draw_rect(Rect2(pos_bar2, Vector2(w2 * frac2, h2)), Color(0.2,1.0,0.2,0.95), true)

