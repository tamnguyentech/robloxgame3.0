local BoosterBalanceConfig = {}

-- Shared booster balance used by both client UI and server validation.
BoosterBalanceConfig.Packs = {
	{
		Id = "starter_pack",
		Name = "Starter Pack",
		Price = 100,
		CardsPerOpen = 10,
		Image = "rbxassetid://118741134181130",
		RarityRates = {
			Common = 60,
			Uncommon = 25,
			Rare = 10,
			Epic = 4,
			Legendary = 1,
		},
	},
	{
		Id = "epic_pack",
		Name = "Epic Pack",
		Price = 300,
		CardsPerOpen = 10,
		Image = "rbxassetid://105911485212785",
		RarityRates = {
			Common = 35,
			Uncommon = 30,
			Rare = 20,
			Epic = 12,
			Legendary = 3,
		},
	},
}

BoosterBalanceConfig.DefaultRarityRates = {
	Common = 60,
	Uncommon = 25,
	Rare = 10,
	Epic = 4,
	Legendary = 1,
}

BoosterBalanceConfig.DefaultCardsPerOpen = 10

function BoosterBalanceConfig.GetPackById(packId)
	if type(packId) ~= "string" then
		return nil
	end
	for _, pack in ipairs(BoosterBalanceConfig.Packs) do
		if pack.Id == packId then
			return pack
		end
	end
	return nil
end

return BoosterBalanceConfig
