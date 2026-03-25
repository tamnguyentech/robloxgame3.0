-- BalanceConfig.luau
-- Centralized balance configuration for easy patching and game balance updates
-- All player stat multipliers, base rates, and idle roll settings can be changed here

local BalanceConfig = {}

-- ============================================================================
-- IDLE ROLL SETTINGS
-- ============================================================================

-- Base time between idle rolls (in seconds)
BalanceConfig.BASE_AUTO_ROLL_INTERVAL = 2

-- Tick interval for the idle roll loop (smaller = more responsive but more CPU)
BalanceConfig.TICK_INTERVAL = 0.2

-- ============================================================================
-- PROGRESSION
-- ============================================================================

-- Number of rolls required per level (flat formula).
-- level = math.floor(totalRollCount / ROLLS_PER_LEVEL) + 1
-- Changing this value rebalances leveling speed without touching any other code.
BalanceConfig.ROLLS_PER_LEVEL = 100

-- ============================================================================
-- LUCK STAT CONFIGURATION
-- ============================================================================

-- How much each Luck point increases rare drop rates
-- Default: 0.05 = 5% increase per Luck point
-- Example: 10 Luck = 50% increased rare drop rates
BalanceConfig.LUCK_MULTIPLIER_PER_POINT = 0.05

-- Maximum luck multiplier cap (prevents infinite scaling)
-- Default: 5.0 = 500% max increase (at 80 Luck points)
BalanceConfig.LUCK_MULTIPLIER_CAP = 5.0

-- Base rarity drop rates (percentages, must sum to 100)
BalanceConfig.BASE_RARITY_RATES = {
	God = 0.01,      -- 0.01% base chance
	Legendary = 1,   -- 1% base chance
	Epic = 9,        -- 9% base chance
	Rare = 30,       -- 30% base chance
	Uncommon = 59.99, -- 59.99% base chance
}

-- ============================================================================
-- ROLL SPEED STAT CONFIGURATION
-- ============================================================================

-- How much each Roll Speed point reduces idle roll interval
-- Default: 0.10 = 10% reduction per point
-- Example: Roll Speed 6 = 50% faster rolls (half the interval)
BalanceConfig.ROLL_SPEED_REDUCTION_PER_POINT = 0.05

-- Minimum roll speed multiplier (can't go below this speed)
-- Default: 0.5 = fastest possible is 50% of base interval (2x speed)
-- At Roll Speed 6: interval = 2 * 0.5 = 1 second per roll
BalanceConfig.ROLL_SPEED_MIN_MULTIPLIER = 0.5

-- Base Roll Speed stat value for new players
BalanceConfig.ROLL_SPEED_BASE_VALUE = 1

-- ============================================================================
-- POTION / BORDER STAT CONFIGURATION
-- ============================================================================

-- Each Potion Duration point increases potion duration by 10%
BalanceConfig.POTION_DURATION_BONUS_PER_POINT = 0.10

-- Each Foil Chance point adds 0.25% foiled card chance
BalanceConfig.FOIL_CHANCE_PERCENT_PER_POINT = 0.25

-- Centralized foil card visual palette
BalanceConfig.FOIL_VISUALS = {
	TagBackgroundColor = Color3.fromRGB(255, 205, 92),
	StrokeColor = Color3.fromRGB(255, 215, 102),
	GlowColor = Color3.fromRGB(255, 226, 138),
	TagStrokeColor = Color3.fromRGB(255, 243, 184),
	GradientColorSequence = ColorSequence.new{
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 205, 92)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 243, 184)),
		ColorSequenceKeypoint.new(0.7, Color3.fromRGB(255, 226, 138)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 215, 102)),
	},
}

-- Default foil tier (lowest tier; used for legacy refs at 0 FoilChance).
-- Why: Base tier is removed; Silver is the entry point so even new players'
-- bordered cards look polished rather than plain.
BalanceConfig.DEFAULT_FOIL_TIER = "Silver"

-- Border tier order (ascending — also the foil upgrade path shown to players).
-- Why: Diamond and Rainbow are separate tiers; the top tier "Rainbow" has the
-- full-spectrum iridescent holo effect.
BalanceConfig.FOIL_TIER_ORDER = {"Silver", "Gold", "Diamond", "Rainbow"}

-- FoilChance stat points required to unlock each tier for rolled foiled cards.
-- NOTE: These thresholds are now RETIRED for auto-roll. All tiers are rollable
-- from 0 FoilChance points via weighted probability (see RollFoilTier below).
-- Kept here for UI label reference only (e.g. "Gold unlocks at 50 points").
BalanceConfig.FOIL_TIER_THRESHOLDS = {
	Silver  = 0,
	Gold    = 50,
	Diamond = 150,
	Rainbow = 300,
}

-- Base weights for each foil tier when a foiled card is rolled.
-- Any tier is always rollable regardless of stat investment.
-- Higher tiers are rarer but never locked behind a threshold.
-- Total base weight = 100 (Silver 76.5 + Gold 20 + Diamond 3 + Rainbow 0.5).
BalanceConfig.FOIL_TIER_BASE_WEIGHTS = {
	Silver  = 76.5,
	Gold    = 20,
	Diamond = 3,
	Rainbow = 0.5,
}

-- Per-FoilChance-point weight shift toward rarer tiers.
-- Silver absorbs the reduction so the total weight stays stable.
-- Caps prevent Silver weight from going below 1.
-- Example at 100 points: Gold +10, Diamond +3, Rainbow +1 → Silver = 56.
BalanceConfig.FOIL_TIER_WEIGHT_SHIFT_PER_POINT = {
	Gold    = 0.10,
	Diamond = 0.03,
	Rainbow = 0.01,
}

-- Attack / HP multipliers applied to bordered cards at each tier.
-- Why: higher tier = greater power reward on top of the foil visual.
BalanceConfig.FOIL_TIER_MULTIPLIERS = {
	Silver = {
		AtkMultiplier = 2,
		HpMultiplier = 2,
	},
	Gold = {
		AtkMultiplier = 3,
		HpMultiplier = 3,
	},
	Diamond = {
		AtkMultiplier = 4,
		HpMultiplier = 4,
	},
	Rainbow = {
		AtkMultiplier = 5,
		HpMultiplier = 5,
	},
}

-- ============================================================================
-- STAT ALLOCATION CONFIGURATION
-- ============================================================================

-- Points granted per level up
BalanceConfig.POINTS_PER_LEVEL = 1

-- Starting stat values for new players
BalanceConfig.STARTING_STATS = {
	Luck = 0,
	RollSpeed = 1,
	PotionDuration = 0,
	FoilChance = 0,
	Points = 1, -- Starting points at level 1
}

-- Maximum cap for each stat (nil means no cap)
BalanceConfig.STAT_CAPS = {
	Luck = nil,      -- No cap
	RollSpeed = nil, -- No cap
	PotionDuration = nil,
	FoilChance = nil,
	Points = nil,    -- No cap (dynamic based on level)
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Calculate the luck multiplier based on luck stat value
function BalanceConfig.CalculateLuckMultiplier(luckValue)
	local rawMultiplier = 1 + (luckValue * BalanceConfig.LUCK_MULTIPLIER_PER_POINT)
	return math.min(rawMultiplier, 1 + BalanceConfig.LUCK_MULTIPLIER_CAP)
end

-- Calculate the roll speed interval multiplier based on roll speed stat value
function BalanceConfig.CalculateRollSpeedMultiplier(rollSpeedValue)
	local reduction = (rollSpeedValue - BalanceConfig.ROLL_SPEED_BASE_VALUE) * BalanceConfig.ROLL_SPEED_REDUCTION_PER_POINT
	local multiplier = 1 - reduction
	return math.max(multiplier, BalanceConfig.ROLL_SPEED_MIN_MULTIPLIER)
end

-- Calculate the final idle roll interval
function BalanceConfig.CalculateRollInterval(luckValue, rollSpeedValue, autoRollMultiplier)
	local baseInterval = BalanceConfig.BASE_AUTO_ROLL_INTERVAL
	local speedMult = BalanceConfig.CalculateRollSpeedMultiplier(rollSpeedValue)
	local autoMult = autoRollMultiplier or 1
	
	return (baseInterval / autoMult) * speedMult
end

-- Calculate the potion duration in seconds
function BalanceConfig.CalculatePotionDurationSeconds(baseDurationSeconds, potionDurationPoints)
	local baseDuration = math.max(1, math.floor(tonumber(baseDurationSeconds) or 1))
	local points = math.max(0, math.floor(tonumber(potionDurationPoints) or 0))
	local multiplier = 1 + (points * BalanceConfig.POTION_DURATION_BONUS_PER_POINT)
	return math.max(1, math.floor(baseDuration * multiplier))
end

-- Calculate the foil chance percent
function BalanceConfig.CalculateFoilChancePercent(foilChancePoints)
	local points = math.max(0, math.floor(tonumber(foilChancePoints) or 0))
	return math.max(0, points * BalanceConfig.FOIL_CHANCE_PERCENT_PER_POINT)
end

-- Get foil tier based on foil chance points
function BalanceConfig.GetFoilTier(foilChancePoints)
	local points = math.max(0, math.floor(tonumber(foilChancePoints) or 0))
	local resolvedTier = BalanceConfig.DEFAULT_FOIL_TIER
	for _, tierName in ipairs(BalanceConfig.FOIL_TIER_ORDER) do
		local threshold = math.max(0, math.floor(tonumber(BalanceConfig.FOIL_TIER_THRESHOLDS[tierName]) or 0))
		if points >= threshold then
			resolvedTier = tierName
		end
	end
	return resolvedTier
end

-- Roll a foil tier via weighted probability.
-- All four tiers are always rollable; FoilChance points gradually shift
-- weight from Silver toward rarer tiers as a reward for stat investment.
-- Math: each point adds a small bonus to Gold/Diamond/Rainbow weights;
-- Silver absorbs the reduction, clamped to a minimum of 1 so it never vanishes.
function BalanceConfig.RollFoilTier(foilChancePoints)
	local points = math.max(0, math.floor(tonumber(foilChancePoints) or 0))
	local shift = BalanceConfig.FOIL_TIER_WEIGHT_SHIFT_PER_POINT
	local base  = BalanceConfig.FOIL_TIER_BASE_WEIGHTS

	-- Compute bonuses (uncapped per-tier, Silver absorbs total reduction).
	local goldBonus    = points * shift.Gold
	local diamondBonus = points * shift.Diamond
	local rainbowBonus = points * shift.Rainbow
	local silverWeight = math.max(1, base.Silver - goldBonus - diamondBonus - rainbowBonus)

	-- Ordered weight table — order matches FOIL_TIER_ORDER for future safety.
	local weights = {
		{ tier = "Silver",  weight = silverWeight },
		{ tier = "Gold",    weight = base.Gold    + goldBonus },
		{ tier = "Diamond", weight = base.Diamond + diamondBonus },
		{ tier = "Rainbow", weight = base.Rainbow + rainbowBonus },
	}

	local total = 0
	for _, entry in ipairs(weights) do
		total += entry.weight
	end

	-- Uniform [0, total) roll; iterate until cumulative weight exceeds roll value.
	local roll = math.random() * total
	local running = 0
	for _, entry in ipairs(weights) do
		running += entry.weight
		if roll < running then
			return entry.tier
		end
	end
	return BalanceConfig.DEFAULT_FOIL_TIER
end

-- Get foil multipliers based on foil chance points
function BalanceConfig.GetFoilMultipliers(foilChancePoints)
	local tierName = BalanceConfig.GetFoilTier(foilChancePoints)
	local multipliers = BalanceConfig.FOIL_TIER_MULTIPLIERS[tierName] or BalanceConfig.FOIL_TIER_MULTIPLIERS[BalanceConfig.DEFAULT_FOIL_TIER] or {AtkMultiplier = 1, HpMultiplier = 1}
	return {
		AtkMultiplier = math.max(1, tonumber(multipliers.AtkMultiplier) or 1),
		HpMultiplier = math.max(1, tonumber(multipliers.HpMultiplier) or 1),
		Tier = tierName,
	}
end

-- Get foil visuals
function BalanceConfig.GetFoilVisuals()
	return BalanceConfig.FOIL_VISUALS
end

-- Get rarity rates with luck applied
function BalanceConfig.GetRarityRatesWithLuck(luckValue)
	local luckMult = BalanceConfig.CalculateLuckMultiplier(luckValue)
	
	return {
		God = BalanceConfig.BASE_RARITY_RATES.God * luckMult,
		Legendary = BalanceConfig.BASE_RARITY_RATES.Legendary * luckMult,
		Epic = BalanceConfig.BASE_RARITY_RATES.Epic * luckMult,
		Rare = BalanceConfig.BASE_RARITY_RATES.Rare * luckMult,
		Uncommon = BalanceConfig.BASE_RARITY_RATES.Uncommon,
	}
end

-- ============================================================================
-- QUICK REFERENCE / DOCUMENTATION
-- ============================================================================

--[[

HOW TO PATCH FOR BALANCE UPDATES:

1. TO MAKE LUCK MORE POWERFUL:
   - Increase LUCK_MULTIPLIER_PER_POINT (e.g., 0.05 -> 0.08)
   - Each Luck point now gives 8% increased rare drops instead of 5%

2. TO MAKE ROLL SPEED MORE POWERFUL:
   - Increase ROLL_SPEED_REDUCTION_PER_POINT (e.g., 0.10 -> 0.15)
   - Each Roll Speed point now reduces interval by 15% instead of 10%
   - OR decrease ROLL_SPEED_MIN_MULTIPLIER (e.g., 0.5 -> 0.3)
   - Allows faster maximum roll speed

3. TO ADJUST BASE ROLL SPEED:
   - Change BASE_AUTO_ROLL_INTERVAL (e.g., 2 -> 3 for slower base rolls)

4. TO ADJUST BASE RARITY RATES:
   - Modify BASE_RARITY_RATES table
   - Ensure all values sum to approximately 100

5. TO ADD STAT CAPS:
   - Set STAT_CAPS.Luck or STAT_CAPS.RollSpeed to a number
   - Example: STAT_CAPS.Luck = 50 means max 50 Luck points

EXAMPLES OF DIFFERENT BALANCE SCENARIOS:

SCENARIO A: Luck-Heavy Game
- LUCK_MULTIPLIER_PER_POINT = 0.10 (10% per point)
- BASE_RARITY_RATES.God = 0.005 (even rarer base)
- 20 Luck = 3x rare drop rates (200% increase)

SCENARIO B: Fast Rolling Game
- ROLL_SPEED_REDUCTION_PER_POINT = 0.15 (15% per point)
- ROLL_SPEED_MIN_MULTIPLIER = 0.3 (3.3x max speed)
- 10 Roll Speed = 0.3x interval = 6x faster rolling

SCENARIO C: Slow And Steady
- BASE_AUTO_ROLL_INTERVAL = 5 (5 seconds per roll)
- LUCK_MULTIPLIER_PER_POINT = 0.03 (3% per point)
- Focus on strategic play over speed

--]]

return BalanceConfig
