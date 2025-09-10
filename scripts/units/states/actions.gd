class_name UnitActions

# Centralized unit actions (chop, fight, etc.). Static methods, pure helpers.

static func perform_lumberjack(farmer: Node, map: Node, tile: Vector2, slot: int, queue: Array) -> bool:
    if not (farmer and map):
        return false
    if not map.has_method("start_chop"):
        return false
    # Primary target first
    if slot >= 0 and map.start_chop(tile, slot, farmer):
        return true
    # Fallback to short neighbor queue if provided
    if queue and queue is Array:
        for it in queue:
            if it == null:
                continue
            var t: Vector2 = it.tile if it.has("tile") else it.get("tile", tile)
            var s: int = int(it.slot) if it.has("slot") else int(it.get("slot", -1))
            if s >= 0 and map.start_chop(t, s, farmer):
                return true
    return false
