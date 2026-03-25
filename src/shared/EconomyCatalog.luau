local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BoosterBalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BoosterBalanceConfig"))
local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))

local EconomyCatalog = {}

local CARD_PRICE_BY_RARITY = {
    Common = 20,
    Uncommon = 35,
    Rare = 60,
    Mythic = 110,
    Legendary = 220,
    God = 400,
    Transcendent = 900,
}

local ITEM_DEFINITIONS = {
    -- ── Dev / visual-test border tier items removed ───────────────────────────
    -- The "Set FoilChance to X" items that mutated player stats were replaced
    -- by the Shop Cards-tab gallery (Shop → Cards → Border Tier Gallery), which
    -- previews Silver/Gold/Diamond/Rainbow foils visually without any stat change.
    -- ─────────────────────────────────────────────────────────────────────────

    AutoRoll2x20s = {
        Name = "2x Auto Roll",
        Description = "Doubles auto-roll speed for 20 seconds.",
        Price = 25,
        GrantAmount = 1,
        Category = "Boosts",
        SortOrder = 10,
        Effect = {
            type = "AutoRoll",
            multiplier = 2,
            duration = 20,
        },
    },
    LuckPotion = {
        Name = "Luck Potion",
        Description = "Boosts luck for a limited time. Duration scales with Potion Duration.",
        Price = 90,
        GrantAmount = 1,
        Category = "Potions",
        SortOrder = 20,
        Effect = {
            type = "Luck",
            luckBonus = 4,
            duration = 180,
        },
    },
    FoilChancePotion = {
        Name = "Foil Chance Potion",
        Description = "Temporarily increases foil chance. Duration scales with Potion Duration.",
        Price = 120,
        GrantAmount = 1,
        Category = "Potions",
        SortOrder = 30,
        Effect = {
            type = "FoilChance",
            foilChanceBonus = 4,
            duration = 180,
        },
    },
}

local DIRECT_CARD_OVERRIDES = {
    BeliodusX = {
        Price = 1200,
        GrantAmount = 1,
        SortOrder = 9990,
    },
    AstraEclipse = {
        Price = 1200,
        GrantAmount = 1,
        SortOrder = 9991,
    },
    -- Dev/test: one tiered BeliodusX bordered card per tier at 1 coin each.
    -- Buy these in the Shop → Cards tab and hover to see each foil effect.
    -- The tier is encoded in the card reference so card-rarity (God) and
    -- border-tier-rarity remain fully independent systems.
    ["BeliodusX::Foil::Silver"] = {
        Price = 1,
        GrantAmount = 1,
        SortOrder = 9985,
    },
    ["BeliodusX::Foil::Gold"] = {
        Price = 1,
        GrantAmount = 1,
        SortOrder = 9986,
    },
    ["BeliodusX::Foil::Diamond"] = {
        Price = 1,
        GrantAmount = 1,
        SortOrder = 9987,
    },
    ["BeliodusX::Foil::Rainbow"] = {
        Price = 1,
        GrantAmount = 1,
        SortOrder = 9988,
    },
}

local function cloneTableShallow(tbl)
    local out = {}
    for key, value in pairs(tbl or {}) do
        out[key] = value
    end
    return out
end

local function getRarityBasePrice(rarity)
    return CARD_PRICE_BY_RARITY[rarity] or CARD_PRICE_BY_RARITY.Common
end

local function getDynamicCardPrice(cardId)
    local data = CardDatabase.GetCardData(cardId)
    if not data then
        return 0
    end
    local base = getRarityBasePrice(data.Rarity)
    local combatPower = CardDatabase.GetCombatPower(cardId)
    local scaled = math.floor(combatPower * 0.04)
    return math.max(base, base + scaled)
end

function EconomyCatalog.GetItemOffer(itemId)
    if type(itemId) ~= "string" then
        return nil
    end
    local item = ITEM_DEFINITIONS[itemId]
    if not item then
        return nil
    end
    local offer = cloneTableShallow(item)
    offer.Id = itemId
    return offer
end

function EconomyCatalog.GetAllItemOffersSorted()
    local offers = {}
    for itemId in pairs(ITEM_DEFINITIONS) do
        local offer = EconomyCatalog.GetItemOffer(itemId)
        if offer then
            table.insert(offers, offer)
        end
    end
    table.sort(offers, function(a, b)
        local aOrder = tonumber(a.SortOrder) or 0
        local bOrder = tonumber(b.SortOrder) or 0
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end
        return tostring(a.Name or a.Id) < tostring(b.Name or b.Id)
    end)
    return offers
end

function EconomyCatalog.GetDirectCardOffer(cardId)
    if type(cardId) ~= "string" then
        return nil
    end
    local data = CardDatabase.GetCardData(cardId)
    if not data or data.Category == "NPC" then
        return nil
    end
    local override = DIRECT_CARD_OVERRIDES[cardId] or {}
    return {
        Id = cardId,
        Name = data.Name or cardId,
        Description = string.format("%s card offer", data.Rarity or "Common"),
        Price = 1,
        GrantAmount = override.GrantAmount or 1,
        SortOrder = override.SortOrder or (getRarityBasePrice(data.Rarity) * 10),
        Rarity = data.Rarity or "Common",
    }
end

function EconomyCatalog.GetAllDirectCardOffersSorted()
    local offers = {}
    for _, cardId in ipairs(CardDatabase.GetAllCardIdsSorted()) do
        local offer = EconomyCatalog.GetDirectCardOffer(cardId)
        if offer then
            table.insert(offers, offer)
        end
    end
    table.sort(offers, function(a, b)
        local aOrder = tonumber(a.SortOrder) or 0
        local bOrder = tonumber(b.SortOrder) or 0
        if aOrder ~= bOrder then
            return aOrder < bOrder
        end
        return tostring(a.Name or a.Id) < tostring(b.Name or b.Id)
    end)
    return offers
end

function EconomyCatalog.GetCardSellValue(cardId)
    local offer = EconomyCatalog.GetDirectCardOffer(cardId)
    if not offer then
        return 0
    end
    return math.max(1, math.floor((tonumber(offer.Price) or 0) * 0.35))
end

function EconomyCatalog.GetPack(packId)
    return BoosterBalanceConfig.GetPackById(packId)
end

return EconomyCatalog
