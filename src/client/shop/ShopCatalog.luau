local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EconomyCatalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EconomyCatalog"))
local BoosterBalanceConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BoosterBalanceConfig"))
local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))

local ShopCatalog = {}

local TAB_META = {
	Packs = {
		Label = "Packs",
		Accent = Color3.fromRGB(74, 182, 110),
	},
	Items = {
		Label = "Items",
		Accent = Color3.fromRGB(79, 134, 210),
	},
	Cards = {
		Label = "Cards",
		Accent = Color3.fromRGB(190, 126, 82),
	},
}

local function shallowClone(tbl)
	return table.clone(tbl or {})
end

local function getPackEntries()
	local entries = {}
	for _, pack in ipairs(BoosterBalanceConfig.Packs or {}) do
		table.insert(entries, {
			Id = pack.Id,
			Name = pack.Name or pack.Id,
			Description = string.format("%d cards per open", tonumber(pack.CardsPerOpen) or BoosterBalanceConfig.DefaultCardsPerOpen or 1),
			Price = math.max(0, math.floor(tonumber(pack.Price) or 0)),
			Accent = TAB_META.Packs.Accent,
			Kind = "Pack",
			Action = "BuyPack",
			Payload = {
				packId = pack.Id,
				amount = 1,
			},
		})
	end
	return entries
end

local function getItemEntries()
	local entries = {}
	for _, offer in ipairs(EconomyCatalog.GetAllItemOffersSorted()) do
		table.insert(entries, {
			Id = offer.Id,
			Name = offer.Name or offer.Id,
			Description = offer.Description or offer.Id,
			Price = math.max(0, math.floor(tonumber(offer.Price) or 0)),
			Accent = TAB_META.Items.Accent,
			Kind = offer.Category or "Item",
			Action = "BuyItem",
			Payload = {
				itemId = offer.Id,
				amount = 1,
			},
		})
	end
	return entries
end

local function getCardEntries()
	local entries = {}
	for _, offer in ipairs(EconomyCatalog.GetAllDirectCardOffersSorted()) do
		local cardData = CardDatabase.GetCardData(offer.Id)
		table.insert(entries, {
			Id = offer.Id,
			Name = offer.Name or offer.Id,
			Description = string.format("%s | CP %s", offer.Rarity or "Common", CardDatabase.FormatCombatPower(offer.Id)),
			Price = math.max(0, math.floor(tonumber(offer.Price) or 0)),
			Accent = TAB_META.Cards.Accent,
			Kind = offer.Rarity or "Card",
			Action = "BuyDirectCard",
			Image = cardData and cardData.ArtAssetId or "",
			Payload = {
				cardId = offer.Id,
				amount = 1,
			},
		})
	end
	return entries
end

function ShopCatalog.GetTabs()
	return {
		{
			Id = "Packs",
			Label = TAB_META.Packs.Label,
			Accent = TAB_META.Packs.Accent,
			Entries = getPackEntries(),
		},
		{
			Id = "Items",
			Label = TAB_META.Items.Label,
			Accent = TAB_META.Items.Accent,
			Entries = getItemEntries(),
		},
		{
			Id = "Cards",
			Label = TAB_META.Cards.Label,
			Accent = TAB_META.Cards.Accent,
			Entries = getCardEntries(),
		},
	}
end

function ShopCatalog.GetMeta(tabId)
	return shallowClone(TAB_META[tabId])
end

return ShopCatalog
