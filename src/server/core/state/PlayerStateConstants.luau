-- Why: Centralize primitive player-state defaults and allowed keys so the rest of the server core
-- does not duplicate magic strings or drift in behavior.
-- How: Require this module anywhere a state module needs canonical defaults or validation rules.

local PlayerStateConstants = {}

PlayerStateConstants.DEFAULT_LEVEL = 1
PlayerStateConstants.DEFAULT_ROLL_COUNT = 0
PlayerStateConstants.DEFAULT_COINS = 0

local DEFAULT_STATS = {
	Luck = 0,
	RollSpeed = 1,
	PotionDuration = 0,
	FoilChance = 0,
	Points = 0,
}

local DEFAULT_ITEMS = {
	AutoRoll2x20s = 0,
	LuckPotion = 0,
	FoilChancePotion = 0,
}

local ALLOCATABLE_STATS = {
	Luck = true,
	RollSpeed = true,
	PotionDuration = true,
	FoilChance = true,
}

-- Why: Return detached copies of internal templates so callers never mutate shared defaults.
-- How: Pass any table into this helper and it returns a shallow clone of that table.
local function cloneTable(source)
	return table.clone(source)
end

-- Why: Expose the canonical stat defaults from a single place.
-- How: Call this when creating or resetting a player's stat block.
function PlayerStateConstants.GetDefaultStats()
	return cloneTable(DEFAULT_STATS)
end

-- Why: Expose the canonical starter item counters from a single place.
-- How: Call this when creating or sanitizing the player's item inventory.
function PlayerStateConstants.GetDefaultItems()
	return cloneTable(DEFAULT_ITEMS)
end

-- Why: Make the allocatable stat allowlist inspectable without exposing the backing table directly.
-- How: Call this when tooling or debug code needs the full allowed stat map.
function PlayerStateConstants.GetAllocatableStats()
	return cloneTable(ALLOCATABLE_STATS)
end

-- Why: Keep stat-point validation consistent across all state mutations.
-- How: Pass a stat name string and this returns true only for supported allocatable stats.
function PlayerStateConstants.IsAllocatableStat(statName)
	return ALLOCATABLE_STATS[statName] == true
end

return PlayerStateConstants
