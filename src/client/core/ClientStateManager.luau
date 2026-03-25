-- ClientStateManager.luau
-- Centralized client-side state management for all game systems
-- Single source of truth for client state to prevent duplication and inconsistencies

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CardDatabase = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("CardDatabase"))
local Players = game:GetService("Players")
local _player = Players.LocalPlayer

local ClientStateManager = {}

-- State containers
local state = {
	-- Player progression
	level = 1,
	rollCount = 0,
	coins = 0,
	
	-- Stats (from PlayerStatsService)
	stats = {
		Luck = 0,
		RollSpeed = 1,
		PotionDuration = 0,
		FoilChance = 0,
		Points = 0,
	},
	
	-- Inventory
	inventory = {}, -- array of cardIds
	combatDeck = {}, -- array of cardIds for combat slots
	
	-- Economy
	boosterPacks = {}, -- {packId = count}
	items = {} :: { [string]: number }, -- {itemId = count}
	
	-- Boosts
	autoRollMultiplier = 1,
	buffEndTime = 0,
}

-- Event system for state changes
local listeners = {}

local function normalizeCardReference(cardRef)
	if type(cardRef) ~= "string" or cardRef == "" then
		return nil
	end
	return CardDatabase.NormalizeCardReference(cardRef)
end

function ClientStateManager.subscribe(key, callback)
	if not listeners[key] then
		listeners[key] = {}
	end
	table.insert(listeners[key], callback)
	return function() -- unsubscribe function
		for i, cb in ipairs(listeners[key]) do
			if cb == callback then
				table.remove(listeners[key], i)
				break
			end
		end
	end
end

local function notify(key, value)
	if listeners[key] then
		for _, callback in ipairs(listeners[key]) do
			pcall(callback, value)
		end
	end
end

-- State getters
function ClientStateManager.getLevel() return state.level end
function ClientStateManager.getRollCount() return state.rollCount end
function ClientStateManager.getCoins() return state.coins end
function ClientStateManager.getStats() return table.clone(state.stats) end
function ClientStateManager.getInventory() return table.clone(state.inventory) end
function ClientStateManager.getCombatDeck() return table.clone(state.combatDeck) end
function ClientStateManager.getBoosterPacks() return table.clone(state.boosterPacks) end
function ClientStateManager.getItems() return table.clone(state.items) end

-- State setters (with notifications)
function ClientStateManager.setLevel(value)
	state.level = math.max(1, math.floor(tonumber(value) or 1))
	notify("level", state.level)
end

function ClientStateManager.setRollCount(value)
	state.rollCount = math.max(0, math.floor(tonumber(value) or 0))
	notify("rollCount", state.rollCount)
end

function ClientStateManager.setCoins(value)
	state.coins = math.max(0, math.floor(tonumber(value) or 0))
	notify("coins", state.coins)
	
	-- Update IntValue for compatibility
	local coinsValue = ReplicatedStorage:FindFirstChild("PlayerCurrencyValue")
	if coinsValue and coinsValue:IsA("IntValue") then
		coinsValue.Value = state.coins
	end
end

function ClientStateManager.setStats(stats)
	if type(stats) == "table" then
		state.stats.Luck = math.max(0, math.floor(tonumber(stats.Luck) or state.stats.Luck))
		state.stats.RollSpeed = math.max(1, math.floor(tonumber(stats.RollSpeed) or state.stats.RollSpeed))
		state.stats.PotionDuration = math.max(0, math.floor(tonumber(stats.PotionDuration) or state.stats.PotionDuration))
		state.stats.FoilChance = math.max(0, math.floor(tonumber(stats.FoilChance or stats.BorderChance) or state.stats.FoilChance))
		state.stats.Points = math.max(0, math.floor(tonumber(stats.Points) or state.stats.Points))
		notify("stats", table.clone(state.stats))
	end
end

function ClientStateManager.setInventory(inventory)
	if type(inventory) == "table" then
		state.inventory = {}
		for _, cardId in ipairs(inventory) do
			local normalized = normalizeCardReference(cardId)
			if normalized then
				table.insert(state.inventory, normalized)
			end
		end
		notify("inventory", table.clone(state.inventory))
	end
end

function ClientStateManager.addCardToInventory(cardId)
	local normalized = normalizeCardReference(cardId)
	if normalized then
		table.insert(state.inventory, normalized)
		notify("inventory", table.clone(state.inventory))
		notify("cardAdded", normalized)
	end
end

function ClientStateManager.addMultipleCards(cardIds)
	if type(cardIds) == "table" then
		local normalizedCards = {}
		for _, cardId in ipairs(cardIds) do
			local normalized = normalizeCardReference(cardId)
			if normalized then
				table.insert(state.inventory, normalized)
				table.insert(normalizedCards, normalized)
			end
		end
		notify("inventory", table.clone(state.inventory))
		notify("cardsAdded", normalizedCards)
	end
end

function ClientStateManager.setCombatDeck(deck)
	if type(deck) == "table" then
		state.combatDeck = {}
		for index, cardRef in ipairs(deck) do
			state.combatDeck[index] = normalizeCardReference(cardRef) or ""
		end
		notify("combatDeck", state.combatDeck)
	end
end

function ClientStateManager.setBoosterPacks(packs)
	if type(packs) == "table" then
		state.boosterPacks = table.clone(packs)
		notify("boosterPacks", state.boosterPacks)
	end
end

function ClientStateManager.setItems(items)
	if type(items) == "table" then
		state.items = table.clone(items)
		notify("items", state.items)
		
		-- Update AutoRoll value for compatibility
		local autoRollValue = ReplicatedStorage:FindFirstChild("ItemOwned_AutoRoll2x20s")
		if autoRollValue and autoRollValue:IsA("IntValue") then
			autoRollValue.Value = state.items.AutoRoll2x20s or 0
		end
		local luckPotionValue = ReplicatedStorage:FindFirstChild("ItemOwned_LuckPotion")
		if luckPotionValue and luckPotionValue:IsA("IntValue") then
			luckPotionValue.Value = state.items.LuckPotion or 0
		end
		local foilChancePotionValue = ReplicatedStorage:FindFirstChild("ItemOwned_FoilChancePotion")
		if foilChancePotionValue and foilChancePotionValue:IsA("IntValue") then
			foilChancePotionValue.Value = state.items.FoilChancePotion or 0
		end
	end
end

-- Full state update from server
function ClientStateManager.syncFromServer(data)
	if type(data) ~= "table" then return end
	
	if data.level ~= nil then ClientStateManager.setLevel(data.level) end
	if data.rollCount ~= nil then ClientStateManager.setRollCount(data.rollCount) end
	if data.coins ~= nil then ClientStateManager.setCoins(data.coins) end
	if data.stats ~= nil then ClientStateManager.setStats(data.stats) end
	if data.inventory ~= nil then ClientStateManager.setInventory(data.inventory) end
	if data.combat ~= nil then ClientStateManager.setCombatDeck(data.combat) end
	if data.boosterPacks ~= nil then ClientStateManager.setBoosterPacks(data.boosterPacks) end
	if data.items ~= nil then ClientStateManager.setItems(data.items) end
	
	-- Update exposed level value for other systems
	local levelValue = ReplicatedStorage:FindFirstChild("PlayerCurrentLevel")
	if levelValue and levelValue:IsA("IntValue") then
		levelValue.Value = state.level
	end
end

-- Get full state (for saving)
function ClientStateManager.getFullState()
	return {
		level = state.level,
		rollCount = state.rollCount,
		coins = state.coins,
		stats = table.clone(state.stats),
		inventory = table.clone(state.inventory),
		combat = table.clone(state.combatDeck),
		boosterPacks = table.clone(state.boosterPacks),
		items = table.clone(state.items),
	}
end

-- Expose level value for other systems (like ProfileUI reset)
local levelValue = Instance.new("IntValue")
levelValue.Name = "PlayerCurrentLevel"
levelValue.Value = 1
levelValue.Parent = ReplicatedStorage

-- Listen for real-time stats updates from server (level-up, reset, potion use).
-- WaitForChild blocks synchronously here so the listener is guaranteed to be connected
-- before any server-fired StatsUpdatedEvent can arrive on the client.
local _statsEvent = ReplicatedStorage:WaitForChild("StatsUpdatedEvent", 30)
if _statsEvent and _statsEvent:IsA("RemoteEvent") then
	_statsEvent.OnClientEvent:Connect(function(stats)
		if type(stats) == "table" then
			ClientStateManager.setStats(stats)
		end
	end)
end

return ClientStateManager
