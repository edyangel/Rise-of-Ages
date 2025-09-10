extends Resource

class_name Biomas

# Biome and grass atlas helpers for 3x2 (48x32) texture

# Biome names
const GRASS := "grass"
const SAND := "sand"
const GRAY := "gray"

# Atlas layout
const FRAME_COLS := 3
const FRAME_ROWS := 2

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

const FRAME_PAIR_LIGHT_FOR_INTENSE := {4: 1, 5: 2, 6: 3}
const FRAME_PAIR_INTENSE_FOR_LIGHT := {1: 4, 2: 5, 3: 6}

# Choose a grass frame with configurable detail density (probability per detail frame 5 and 6)
static func choose_grass_frame(rng: RandomNumberGenerator, is_edge: bool, use_light_edges: bool, detail_density_per_frame: float = 0.025) -> int:
    # Majority 4; details 5 and 6 each with detail_density_per_frame
    var r = rng.randf()
    var p_detail_total = clamp(detail_density_per_frame * 2.0, 0.0, 0.98)
    var p4 = 1.0 - p_detail_total
    var intense := 4
    if r >= p4:
        var r2 = (r - p4) / max(p_detail_total, 1e-6)
        intense = 5 if r2 < 0.5 else 6
    if use_light_edges and is_edge:
        return FRAME_PAIR_LIGHT_FOR_INTENSE.get(intense, 1)
    return intense

static func atlas_frame_coords(idx: int) -> Vector2i:
    idx = clamp(idx, 1, FRAME_COLS * FRAME_ROWS)
    var zero = idx - 1
    return Vector2i(zero % FRAME_COLS, int(zero / float(FRAME_COLS)))

static func atlas_region_rect(tex: Texture2D, idx: int) -> Rect2:
    if tex == null:
        return Rect2()
    var sz = tex.get_size()
    var fw = int(sz.x / FRAME_COLS)
    var fh = int(sz.y / FRAME_ROWS)
    var p = atlas_frame_coords(idx)
    return Rect2(p.x * fw, p.y * fh, fw, fh)
