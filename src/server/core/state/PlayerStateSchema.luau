-- Why: Define the authoritative in-memory player-state shape and all normalization rules in one module.
-- How: Use this module to create new state, sanitize loaded data, and build save snapshots.

local PlayerStateConstants = require(script.Parent:WaitForChild("PlayerStateConstants"))

local PlayerStateSchema = {}

-- Why: Clamp all integer state values with one consistent rule so progression and stat fields behave predictably.
-- How: Pass the raw value, a minimum bound, and a fallback value; this returns a safe integer.
local function clampInteger(value, minimumValue, fallbackValue)
	return math.max(minimumValue, math.floor(tonumber(value) or fallbackValue))
end

-- Why: Preserve array-shaped collections while stripping invalid entries that would corrupt runtime state.
-- How: Pass a source table and whether empty strings should be preserved for fixed-slot arrays like combat.
local function cloneStringArray(source, allowEmptyString)
	local out = {}
	if type(source) ~= "table" then
		return out
	end

	for _, value in ipairs(source) do
		if type(value) == "string" then
			if value ~= "" or allowEmptyString then
				table.insert(out, value)
			end
		elseif allowEmptyString then
			table.insert(out, "")
		end
	end

	return out
end

-- Why: Normalize numeric dictionary collections like items and booster packs without losing unknown future keys.
-- How: Pass a source table and an optional default dictionary; this returns a sanitized cloned dictionary.
local function cloneNonNegativeDictionary(source, defaults)
	local out = defaults and table.clone(defaults) or {}
	if type(source) ~= "table" then
		return out
	end

	for key, value in pairs(source) do
		if type(key) == "string" then
			out[key] = math.max(0, math.floor(tonumber(value) or 0))
		end
	end

	return out
end

-- Why: Keep stat sanitization centralized so every load, set, reset, and save path shares identical bounds.
-- How: Pass an incoming stats table plus an optional fallback stats table; this returns a safe cloned stats table.
function PlayerStateSchema.SanitizeStats(stats, fallbackStats)
	local baseStats = fallbackStats and table.clone(fallbackStats) or PlayerStateConstants.GetDefaultStats()
	if type(stats) ~= "table" then
		return baseStats
	end

	baseStats.Luck = clampInteger(stats.Luck, 0, baseStats.Luck)
	baseStats.RollSpeed = clampInteger(stats.RollSpeed, 1, baseStats.RollSpeed)
	baseStats.PotionDuration = clampInteger(stats.PotionDuration, 0, baseStats.PotionDuration)
	baseStats.FoilChance = clampInteger(stats.FoilChance, 0, baseStats.FoilChance)
	-- Points are derived from level and spent stats; never trust a loaded/stored Points value.
	baseStats.Points = 0

	return baseStats
end

-- Why: Make stat points deterministic and repairable from (level, allocated stats).
-- How: Pass a stats table and level; returns a cloned table with Points recomputed and
--      overspent allocations clamped down in a deterministic order.
function PlayerStateSchema.ReconcileStatsToLevel(stats, level)
	local out = PlayerStateSchema.SanitizeStats(stats)
	local totalPoints = math.max(1, math.floor(tonumber(level) or 1))

	-- Spent points are the sum of allocatable stats above their defaults.
	local spent = 0
	spent += math.max(0, out.Luck)
	spent += math.max(0, out.PotionDuration)
	spent += math.max(0, out.FoilChance)
	spent += math.max(0, (out.RollSpeed or 1) - 1)

	local overspend = spent - totalPoints
	if overspend > 0 then
		-- Deterministic rollback order so downgrades are predictable:
		-- FoilChance → PotionDuration → Luck → RollSpeed (down to 1).
		local function reduceField(field, minValue)
			if overspend <= 0 then return end
			local current = tonumber(out[field]) or 0
			local floorMin = tonumber(minValue) or 0
			local reducible = math.max(0, current - floorMin)
			local take = math.min(reducible, overspend)
			if take > 0 then
				out[field] = current - take
				overspend -= take
			end
		end

		reduceField("FoilChance", 0)
		reduceField("PotionDuration", 0)
		reduceField("Luck", 0)
		reduceField("RollSpeed", 1)
	end

	local spentAfter = 0
	spentAfter += math.max(0, out.Luck)
	spentAfter += math.max(0, out.PotionDuration)
	spentAfter += math.max(0, out.FoilChance)
	spentAfter += math.max(0, (out.RollSpeed or 1) - 1)
	out.Points = math.max(0, totalPoints - spentAfter)

	return out
end

-- Why: Ensure the item ledger always contains valid counters for starter items while still allowing future item ids.
-- How: Pass a loaded item dictionary and this returns a sanitized cloned version with defaults applied.
function PlayerStateSchema.SanitizeItems(items)
	return cloneNonNegativeDictionary(items, PlayerStateConstants.GetDefaultItems())
end

-- Why: Create the canonical default server-side player state from a single definition.
-- How: Call this whenever a player enters the cache for the first time.
function PlayerStateSchema.CreateDefaultState()
	return {
		level = PlayerStateConstants.DEFAULT_LEVEL,
		rollCount = PlayerStateConstants.DEFAULT_ROLL_COUNT,
		coins = PlayerStateConstants.DEFAULT_COINS,
		stats = PlayerStateConstants.GetDefaultStats(),
		inventory = {},
		combat = {},
		boosterPacks = {},
		items = PlayerStateSchema.SanitizeItems(nil),
	}
end

-- Why: Apply loaded save data using the same normalization rules used by new state creation.
-- How: Pass an existing mutable state table and a raw loaded data table; this mutates the state in place and returns it.
function PlayerStateSchema.ApplyLoadedData(state, data)
	if type(state) ~= "table" then
		return PlayerStateSchema.CreateDefaultState()
	end
	if type(data) ~= "table" then
		return state
	end

	state.level = clampInteger(data.level, 1, state.level or PlayerStateConstants.DEFAULT_LEVEL)
	state.rollCount = clampInteger(data.rollCount, 0, state.rollCount or PlayerStateConstants.DEFAULT_ROLL_COUNT)
	state.coins = clampInteger(data.coins, 0, state.coins or PlayerStateConstants.DEFAULT_COINS)
	state.stats = PlayerStateSchema.ReconcileStatsToLevel(PlayerStateSchema.SanitizeStats(data.stats, state.stats), state.level)
	state.inventory = cloneStringArray(data.inventory, false)
	state.combat = cloneStringArray(data.combat, true)
	state.boosterPacks = cloneNonNegativeDictionary(data.boosterPacks)
	state.items = PlayerStateSchema.SanitizeItems(data.items)

	return state
end

-- Why: Build a detached save-safe snapshot so external callers never mutate live cached state by reference.
-- How: Pass a live state table and this returns a cloned table with only persisted fields.
function PlayerStateSchema.CreateSaveData(state)
	local sourceState = (type(state) == "table") and state or PlayerStateSchema.CreateDefaultState()
	return {
		level = clampInteger(sourceState.level, 1, PlayerStateConstants.DEFAULT_LEVEL),
		rollCount = clampInteger(sourceState.rollCount, 0, PlayerStateConstants.DEFAULT_ROLL_COUNT),
		coins = clampInteger(sourceState.coins, 0, PlayerStateConstants.DEFAULT_COINS),
		stats = PlayerStateSchema.ReconcileStatsToLevel(PlayerStateSchema.SanitizeStats(sourceState.stats), sourceState.level),
		inventory = cloneStringArray(sourceState.inventory, false),
		combat = cloneStringArray(sourceState.combat, true),
		boosterPacks = cloneNonNegativeDictionary(sourceState.boosterPacks),
		items = PlayerStateSchema.SanitizeItems(sourceState.items),
	}
end

return PlayerStateSchema
