class_name UnitStates

# Shared state tags across all unit types.
const LUMBERJACK := "lumberjack"
const MINER := "miner"
const DEFENSIVE := "defensive"
const OFFENSIVE := "offensive"

# Default allowed states per unit type. Modify at runtime via setters below.
static var _allowed: Dictionary = {
	"farmer": [LUMBERJACK, MINER, DEFENSIVE, OFFENSIVE],
	"soldier": [DEFENSIVE, OFFENSIVE],
	"constructor": [DEFENSIVE],
}

static func allowed_for(unit_type: String) -> Array:
	if _allowed.has(unit_type):
		return _allowed[unit_type]
	return []

static func is_allowed(unit_type: String, state: String) -> bool:
	var arr = allowed_for(unit_type)
	return arr.has(state)

static func set_allowed(unit_type: String, states: Array) -> void:
	_allowed[unit_type] = states.duplicate()

static func enable_state(unit_type: String, state: String) -> void:
	var arr = allowed_for(unit_type)
	if not arr.has(state):
		arr.append(state)
	_allowed[unit_type] = arr

static func disable_state(unit_type: String, state: String) -> void:
	var arr = allowed_for(unit_type)
	if arr.has(state):
		arr.erase(state)
	_allowed[unit_type] = arr
