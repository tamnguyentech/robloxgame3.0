-- Why: Keep progression/resource mutation separate from stats and collection logic for cleaner ownership.
-- How: Use these helpers to mutate coins, roll count, and level on a cached player state.

local PlayerStateStore = require(script.Parent:WaitForChild("PlayerStateStore"))

local PlayerProgressionState = {}

-- Why: Apply one consistent integer conversion for progression deltas.
-- How: Pass any numeric-like value and this returns a floored integer delta.
local function toIntegerDelta(value)
	return math.floor(tonumber(value) or 0)
end

-- Why: Add currency without allowing a player's coin count to go negative.
-- How: Pass a userId and a positive or negative delta; this returns the new coin total.
function PlayerProgressionState.AddCoins(userId, amount)
	local state = PlayerStateStore.GetState(userId)
	state.coins = math.max(0, state.coins + toIntegerDelta(amount))
	return state.coins
end

-- Why: Mutate total roll count from one dedicated place so roll economy logic stays consistent.
-- How: Pass a userId and a delta; this returns the new roll-count total.
function PlayerProgressionState.AddRollCount(userId, amount)
	local state = PlayerStateStore.GetState(userId)
	state.rollCount = math.max(0, state.rollCount + toIntegerDelta(amount))
	return state.rollCount
end

-- Why: Keep level writes clamped and centralized to avoid invalid progression state.
-- How: Pass a userId and any numeric-like level value; this returns the sanitized stored level.
function PlayerProgressionState.SetLevel(userId, level)
	local state = PlayerStateStore.GetState(userId)
	state.level = math.max(1, math.floor(tonumber(level) or 1))
	return state.level
end

return PlayerProgressionState
