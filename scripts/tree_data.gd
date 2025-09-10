class_name TreeData

# Centralized tree/cactus/palm resource configuration
# Legacy/default trees
const ATLAS = "res://MiniWorldSprites/Nature/Trees.png"
const FRAME_COLS = 4

# Additional sheets
const CACTUS_ATLAS = "res://MiniWorldSprites/Nature/Cactus.png" # 64x32 -> 4x2 frames
const CACTUS_COLS = 4
const CACTUS_ROWS = 2

const COCONUT_ATLAS = "res://MiniWorldSprites/Nature/CoconutTrees.png" # 96x16 -> 6x1 frames
const COCONUT_COLS = 6
const COCONUT_ROWS = 1

# Dead trees (brown/pale variants)
const DEAD_ATLAS = "res://MiniWorldSprites/Nature/DeadTrees.png" # 64x16 -> 4x1 frames
const DEAD_COLS = 4
const DEAD_ROWS = 1

# Winter dead trees (snow variants)
const WDEAD_ATLAS = "res://MiniWorldSprites/Nature/WinterDeadTrees.png" # 64x16 -> 4x1 frames
const WDEAD_COLS = 4
const WDEAD_ROWS = 1

# Pine trees (plain/snow)
const PINE_ATLAS = "res://MiniWorldSprites/Nature/PineTrees.png" # 48x16 -> 3x1 frames
const PINE_COLS = 3
const PINE_ROWS = 1

# Winter trees (cooler palette; 4 rows, 4 cols; row 4 has snow)
const WINTREES_ATLAS = "res://MiniWorldSprites/Nature/WinterTrees.png" # 64x64 -> 4x4 frames
const WINTREES_COLS = 4
const WINTREES_ROWS = 4

# Rocks (decorative, not choppable)
const ROCKS_ATLAS = "res://MiniWorldSprites/Nature/Rocks.png" # 48x64 -> 3x4 frames (12 total)
const ROCKS_COLS = 3
const ROCKS_ROWS = 4

# Tumbleweed (decorative mover)
const TUMBLEWEED_ATLAS = "res://MiniWorldSprites/Nature/Tumbleweed.png" # 32x16 -> 2x1 frames
const TUMBLEWEED_COLS = 2
const TUMBLEWEED_ROWS = 1

# Named mapping for default tree frames (0 = felled/trunk)
const TYPE_INDEX = {
    "trunk": 0,
    "oak": 1,
    "pine": 2,
    "birch": 3,
}

# Convenience: names for future use
const DEFAULT_TYPES = ["oak", "pine", "birch"]

static func frame_for_type_name(name: String) -> int:
    if TYPE_INDEX.has(name):
        return int(TYPE_INDEX[name])
    return 0

# Cactus labels (1..8 if 4x2)
static func cactus_frame_for(name: String) -> int:
    # expect names like "cactus1".."cactus8"
    if name.begins_with("cactus"):
        var num_str = name.substr(6)
        var idx = int(num_str)
        return clamp(idx, 1, CACTUS_COLS * CACTUS_ROWS)
    return 1

# Coconut trees mapping
# 1: trunk_right, 2: trunk_left, 3: palm_no_coco_right, 4: palm_coco_right, 5: palm_no_coco_left, 6: palm_coco_left
static func coconut_frame_for(name: String) -> int:
    var map = {
        "trunk_right": 1,
        "trunk_left": 2,
        "palm_no_coco_right": 3,
        "palm_coco_right": 4,
        "palm_no_coco_left": 5,
        "palm_coco_left": 6,
    }
    if map.has(name):
        return int(map[name])
    return 1

static func coconut_trunk_for(frame_idx: int) -> int:
    if frame_idx == 3 or frame_idx == 4:
        return 1 # trunk_right
    if frame_idx == 5 or frame_idx == 6:
        return 2 # trunk_left
    # already trunk
    return frame_idx

static func coconut_food_yield(frame_idx: int) -> int:
    return 1 if (frame_idx == 4 or frame_idx == 6) else 0

static func texture_for(sheet: String) -> Texture2D:
    var path = ""
    match sheet:
        "trees":
            path = ATLAS
        "cactus":
            path = CACTUS_ATLAS
        "coconut":
            path = COCONUT_ATLAS
        "deadtrees":
            path = DEAD_ATLAS
        "winterdeadtrees":
            path = WDEAD_ATLAS
        "pinetrees":
            path = PINE_ATLAS
        "wintertrees":
            path = WINTREES_ATLAS
        "rocks":
            path = ROCKS_ATLAS
        "tumbleweed":
            path = TUMBLEWEED_ATLAS
        _:
            path = ATLAS
    if ResourceLoader.exists(path):
        return load(path)
    return null

static func sheet_cols(sheet: String) -> int:
    match sheet:
        "trees":
            return FRAME_COLS
        "cactus":
            return CACTUS_COLS
        "coconut":
            return COCONUT_COLS
        "deadtrees":
            return DEAD_COLS
        "winterdeadtrees":
            return WDEAD_COLS
        "pinetrees":
            return PINE_COLS
        "wintertrees":
            return WINTREES_COLS
        "rocks":
            return ROCKS_COLS
        "tumbleweed":
            return TUMBLEWEED_COLS
    return FRAME_COLS

static func sheet_rows(sheet: String) -> int:
    match sheet:
        "trees":
            return 1
        "cactus":
            return CACTUS_ROWS
        "coconut":
            return COCONUT_ROWS
        "deadtrees":
            return DEAD_ROWS
        "winterdeadtrees":
            return WDEAD_ROWS
        "pinetrees":
            return PINE_ROWS
        "wintertrees":
            return WINTREES_ROWS
        "rocks":
            return ROCKS_ROWS
        "tumbleweed":
            return TUMBLEWEED_ROWS
    return 1

static func trunk_frame_for(sheet: String, frame_idx: int) -> int:
    match sheet:
        "trees":
            return 0
        "cactus":
            return -1 # no trunk sprite for cactus
        "coconut":
            return coconut_trunk_for(frame_idx)
        "deadtrees":
            # 1,2 are trunks; 3 (dead brown) -> 1; 4 (dead pale) -> 2
            if frame_idx == 3:
                return 1
            if frame_idx == 4:
                return 2
            return frame_idx
        "winterdeadtrees":
            # same mapping as deadtrees
            if frame_idx == 3:
                return 1
            if frame_idx == 4:
                return 2
            return frame_idx
        "pinetrees":
            # 1 trunk, 2 pine, 3 pine snow
            return 1
        "wintertrees":
            # 4x4 grid (1-based frame_idx): choose trunk at column 1 in same row
            var cols = WINTREES_COLS
            var idx = max(frame_idx, 1)
            var r = int((idx - 1) / cols)
            # frames are 1..(rows*cols), so trunk at (row=r, col=0) => 1-based index r*cols + 1
            return r * cols + 1
    return -1

static func food_yield_for(sheet: String, frame_idx: int) -> Dictionary:
    # returns a dict of resources to add, e.g., {"wood": 1} or {"food": 1}
    match sheet:
        "coconut":
            var f = coconut_food_yield(frame_idx)
            if f > 0:
                return {"food": f}
    # default: wood 1
    return {"wood": 1}
