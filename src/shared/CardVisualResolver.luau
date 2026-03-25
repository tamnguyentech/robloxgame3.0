-- CardVisualResolver.luau  (shared)
-- Single source of truth: given a cardRef string + optional foilChancePoints,
-- return one CardVisualStyle table that every surface (Inventory, HoverPreview,
-- NpcBattle, PvpBattle) can consume identically.
--
-- CardVisualStyle {
--   isBordered  : boolean
--   tierKey     : string | nil   -- "Silver" | "Gold" | "Diamond" | "Rainbow"
--   strokeColor : Color3         -- tinted UIStroke colour (Rainbow tier: accent only;
--                                  actual outline uses RainbowBorderStroke on client)
--   foilOpts    : table | nil    -- opts table forwarded to HoloFoilController.Attach
-- }
--
-- Why: avoids duplicating tier-resolution logic across four client files.
-- How: checks parsed.BorderTier first (explicit in ref), then falls back to
--      BalanceConfig.GetBorderTier(borderChancePoints) for legacy ::Bordered refs.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CardDatabase  = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local BalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BalanceConfig"))

-- Per-tier stroke accent colours so each tier has a distinct border hue.
local TIER_STROKE_COLORS = {
	Silver    = Color3.fromRGB(210, 218, 232),
	Gold      = Color3.fromRGB(255, 210, 60),
	Diamond   = Color3.fromRGB(178, 224, 255),
	Rainbow   = Color3.fromRGB(255, 160, 210),
	Corrupted = Color3.fromRGB(255, 100, 50),
}

local CardVisualResolver = {}

-- Resolve a CardVisualStyle from a cardRef + optional borderChancePoints.
-- rarityColor is used as the stroke colour for non-bordered cards.
-- Resolve a CardVisualStyle directly from a known tier key (bypasses card ref parsing).
-- Use this when the tier is already known (e.g., from parsed.BorderTier or GetBorderTier).
function CardVisualResolver.resolveFromTier(tier)
	return {
		isBordered  = true,
		tierKey     = tier,
		strokeColor = TIER_STROKE_COLORS[tier] or BalanceConfig.GetFoilVisuals().StrokeColor,
		foilOpts    = { tier = tier },
	}
end

function CardVisualResolver.resolve(cardRef, foilChancePoints, rarityColor)
	local parsed = CardDatabase.ParseCardReference(cardRef)

	if not (parsed and parsed.IsBordered) then
		return {
			isBordered  = false,
			tierKey     = nil,
			strokeColor = rarityColor or Color3.fromRGB(200, 200, 200),
			foilOpts    = nil,
		}
	end

	-- Explicit tier in the ref takes precedence over the stat-derived tier so that
	-- shop/test cards like "BeliodusX::Foil::Gold" always display the correct tier.
	local tier = parsed.BorderTier
		or BalanceConfig.GetFoilTier(tonumber(foilChancePoints) or 0)

	return {
		isBordered  = true,
		tierKey     = tier,
		strokeColor = TIER_STROKE_COLORS[tier] or BalanceConfig.GetFoilVisuals().StrokeColor,
		foilOpts    = { tier = tier },
	}
end

return CardVisualResolver
