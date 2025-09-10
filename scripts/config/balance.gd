class_name Balance

# Global gameplay balance knobs and helpers.
# Keep it simple and explicit so buildings can bump these at runtime.

# Base search radius (tiles) for lumberjack behavior.
const BASE_LUMBER_RADIUS_TILES := 5

# Global modifiers (can be changed by buildings/upgrades)
static var lumber_radius_bonus_tiles: int = 0
static var lumber_radius_multiplier: float = 0.0 # e.g., 0.2 => +20%

static func lumber_radius_tiles() -> int:
	var base := BASE_LUMBER_RADIUS_TILES
	var mult_bonus := int(round(base * lumber_radius_multiplier))
	return max(1, base + lumber_radius_bonus_tiles + mult_bonus)

# Example API that buildings could call
static func apply_lumber_radius_upgrade_percent(percent: float) -> void:
	# Accumulate percentage; rounding happens in lumber_radius_tiles()
	lumber_radius_multiplier += percent

static func add_lumber_radius_tiles(extra_tiles: int) -> void:
	lumber_radius_bonus_tiles += int(extra_tiles)
